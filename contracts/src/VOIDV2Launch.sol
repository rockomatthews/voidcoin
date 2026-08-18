// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {VOIDCoinV2} from "./VOIDCoinV2.sol";
import {VOIDPositionLocker} from "./VOIDPositionLocker.sol";

interface IVOIDV3PoolState {
    function slot0() external view returns (uint160 sqrtPriceX96);
}

interface IVOIDV2PositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96)
        external
        payable
        returns (address pool);
    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

/// @title VOIDV2Launch
/// @notice Atomically creates VOIDCOIN V2 and its visible, one-sided Uniswap v3 USDC market.
/// @dev The range starts at roughly $0.000001 per token, so the first 1,000,000-token takeover
///      costs roughly one US dollar before pool fees and price impact. No ETH/USDC seed capital is required.
contract VOIDV2Launch {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10_000;
    uint256 public constant MINIMUM_MINT_BPS = 9_990;
    uint24 public constant POOL_FEE = 10_000; // 1%
    int24 public constant TOKEN0_START_TICK = -414_600;
    int24 public constant TOKEN0_END_TICK = -322_400;
    int24 public constant TOKEN1_START_TICK = 322_400;
    int24 public constant TOKEN1_END_TICK = 414_600;
    uint160 public constant TOKEN0_START_SQRT_PRICE_X96 = 78_778_025_264_164_499_494;
    // Exact Uniswap TickMath.getSqrtRatioAtTick(414600). Using a decimal approximation one unit below the
    // tick boundary would put the pool inside the range and make a token-only token1 mint request USDC.
    uint160 public constant TOKEN1_START_SQRT_PRICE_X96 = 79_680_871_846_404_160_720_201_234_303_411_693_634;
    uint64 public constant TREASURY_VESTING_DURATION = 365 days;

    VOIDCoinV2 public immutable token;
    VestingWallet public immutable vestingWallet;
    VOIDPositionLocker public immutable positionLocker;
    IVOIDV2PositionManager public immutable positionManager;
    IERC20 public immutable usdc;
    address public immutable pool;
    uint256 public immutable positionTokenId;
    uint128 public immutable positionLiquidity;
    uint256 public immutable tokensSeeded;
    uint256 public immutable launchDustBurned;

    struct MarketResult {
        address pool;
        uint256 tokenId;
        uint128 liquidity;
        uint256 tokenUsed;
        uint160 startingPrice;
        int24 tickLower;
        int24 tickUpper;
    }

    error ZeroAddress();
    error InvalidContract();
    error HostilePoolPrice();
    error InsufficientLiquidityMinted();
    error UnexpectedAssetUse();

    event VisibleMarketCreated(
        address indexed token,
        address indexed pool,
        uint256 indexed positionTokenId,
        address locker,
        uint256 tokenAmount,
        uint128 liquidity,
        uint160 startingSqrtPriceX96,
        int24 tickLower,
        int24 tickUpper
    );
    event LaunchDustBurned(uint256 amount);

    constructor(address safe, IVOIDV2PositionManager positionManager_, IERC20 usdc_, string memory initialTokenURI) {
        if (safe == address(0) || address(positionManager_) == address(0) || address(usdc_) == address(0)) {
            revert ZeroAddress();
        }
        if (safe.code.length == 0 || address(positionManager_).code.length == 0 || address(usdc_).code.length == 0) {
            revert InvalidContract();
        }
        if (bytes(initialTokenURI).length == 0) revert InvalidContract();

        VOIDPositionLocker locker = new VOIDPositionLocker(IERC721(address(positionManager_)), safe);
        VestingWallet vesting = new VestingWallet(safe, uint64(block.timestamp), TREASURY_VESTING_DURATION);
        VOIDCoinV2 coin = new VOIDCoinV2(safe, address(this), address(vesting), initialTokenURI);
        MarketResult memory market = _createMarket(positionManager_, usdc_, coin, locker);

        uint256 dust = coin.balanceOf(address(this));
        if (dust > 0) {
            coin.burnLaunchReserve(dust);
            emit LaunchDustBurned(dust);
        }
        if (coin.balanceOf(address(this)) != 0) revert UnexpectedAssetUse();

        token = coin;
        vestingWallet = vesting;
        positionLocker = locker;
        positionManager = positionManager_;
        usdc = usdc_;
        pool = market.pool;
        positionTokenId = market.tokenId;
        positionLiquidity = market.liquidity;
        tokensSeeded = market.tokenUsed;
        launchDustBurned = dust;

        emit VisibleMarketCreated(
            address(coin),
            market.pool,
            market.tokenId,
            address(locker),
            market.tokenUsed,
            market.liquidity,
            market.startingPrice,
            market.tickLower,
            market.tickUpper
        );
    }

    // All branches select symmetric token ordering or enforce post-conditions for one atomic market creation.
    // slither-disable-next-line cyclomatic-complexity
    function _createMarket(
        IVOIDV2PositionManager positionManager_,
        IERC20 usdc_,
        VOIDCoinV2 coin,
        VOIDPositionLocker locker
    ) private returns (MarketResult memory result) {
        bool tokenIsToken0 = address(coin) < address(usdc_);
        address token0 = tokenIsToken0 ? address(coin) : address(usdc_);
        address token1 = tokenIsToken0 ? address(usdc_) : address(coin);
        result.startingPrice = tokenIsToken0 ? TOKEN0_START_SQRT_PRICE_X96 : TOKEN1_START_SQRT_PRICE_X96;
        result.tickLower = tokenIsToken0 ? TOKEN0_START_TICK : TOKEN1_START_TICK;
        result.tickUpper = tokenIsToken0 ? TOKEN0_END_TICK : TOKEN1_END_TICK;

        result.pool =
            positionManager_.createAndInitializePoolIfNecessary(token0, token1, POOL_FEE, result.startingPrice);
        // Exact zero is the intentional sentinel for an invalid pool address.
        // slither-disable-next-line incorrect-equality
        if (result.pool == address(0) || result.pool.code.length == 0) revert InvalidContract();
        uint160 livePrice = IVOIDV3PoolState(result.pool).slot0();
        if (livePrice != result.startingPrice) revert HostilePoolPrice();

        uint256 launchAllocation = coin.LAUNCH_ALLOCATION();
        uint256 minimumTokenUse = Math.mulDiv(launchAllocation, MINIMUM_MINT_BPS, BPS);
        IERC20(address(coin)).forceApprove(address(positionManager_), launchAllocation);
        IVOIDV2PositionManager.MintParams memory params = IVOIDV2PositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: POOL_FEE,
            tickLower: result.tickLower,
            tickUpper: result.tickUpper,
            amount0Desired: tokenIsToken0 ? launchAllocation : 0,
            amount1Desired: tokenIsToken0 ? 0 : launchAllocation,
            amount0Min: tokenIsToken0 ? minimumTokenUse : 0,
            amount1Min: tokenIsToken0 ? 0 : minimumTokenUse,
            recipient: address(locker),
            deadline: block.timestamp
        });
        uint256 amount0;
        uint256 amount1;
        (result.tokenId, result.liquidity, amount0, amount1) = positionManager_.mint(params);
        IERC20(address(coin)).forceApprove(address(positionManager_), 0);

        result.tokenUsed = tokenIsToken0 ? amount0 : amount1;
        uint256 usdcUsed = tokenIsToken0 ? amount1 : amount0;
        // Zero token IDs/liquidity are explicit invalid mint sentinels.
        // slither-disable-next-line incorrect-equality
        if (result.tokenId == 0 || result.liquidity == 0 || result.tokenUsed < minimumTokenUse) {
            revert InsufficientLiquidityMinted();
        }
        if (usdcUsed != 0 || result.tokenUsed > launchAllocation) revert UnexpectedAssetUse();
        locker.registerPosition(result.tokenId);
    }
}

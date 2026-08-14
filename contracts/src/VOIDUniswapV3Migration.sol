// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IVOIDWETH9 is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface IVOIDUniswapV3PositionManager {
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

    function factory() external view returns (address);
    // Canonical Uniswap v3 periphery selector; capitalization is fixed by the deployed interface.
    // slither-disable-next-line naming-convention
    function WETH9() external view returns (address);
    function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96)
        external
        payable
        returns (address pool);
    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface IVOIDPositionLockRegistration {
    function registerPosition(uint256 tokenId) external;
}

/// @title VOIDUniswapV3Migration
/// @notice Permissionless, stateless adapter that converts graduation assets into a full-range Base Uniswap v3 LP NFT.
/// @dev Any token holder can use this adapter, just as anyone can create a Uniswap pool. It holds no owner authority.
contract VOIDUniswapV3Migration is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10_000;
    uint256 public constant MINIMUM_MINT_BPS = 9_990;
    uint24 public constant POOL_FEE = 10_000;
    int24 public constant TICK_LOWER = -887_200;
    int24 public constant TICK_UPPER = 887_200;
    uint160 public constant MIN_SQRT_RATIO = 4_295_128_739;
    uint160 public constant MAX_SQRT_RATIO = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;
    uint256 private constant Q192 = 1 << 192;

    IVOIDUniswapV3PositionManager public immutable positionManager;
    IVOIDWETH9 public immutable weth9;
    address public immutable dustRecipient;

    struct MintResult {
        address pool;
        uint256 tokenId;
        uint128 liquidity;
        uint256 tokenUsed;
        uint256 wethUsed;
    }

    error ZeroAddress();
    error InvalidContract();
    error InvalidAsset();
    error InvalidAmount();
    error InvalidPrice();
    error DeflationaryTokenUnsupported();
    error InsufficientLiquidityMinted();
    error UnexpectedBalance();
    error DirectEthDisabled();

    event PositionCreated(
        address indexed token,
        address indexed pool,
        address indexed recipient,
        uint256 tokenId,
        uint128 liquidity,
        uint256 tokenAmount,
        uint256 wethAmount,
        uint256 tokenDust,
        uint256 ethDust
    );
    event PoolSeeded(
        address indexed token,
        address indexed pool,
        address indexed recipient,
        uint256 tokenId,
        uint128 liquidity,
        uint256 tokenUsed,
        uint256 wethUsed,
        uint256 tokenReturned,
        uint256 ethReturned
    );

    constructor(IVOIDUniswapV3PositionManager positionManager_, address dustRecipient_) {
        if (address(positionManager_) == address(0) || dustRecipient_ == address(0)) revert ZeroAddress();
        if (address(positionManager_).code.length == 0) revert InvalidContract();
        address wrappedNative = positionManager_.WETH9();
        if (wrappedNative == address(0) || wrappedNative.code.length == 0) revert InvalidContract();
        if (positionManager_.factory() == address(0)) revert InvalidContract();
        positionManager = positionManager_;
        weth9 = IVOIDWETH9(wrappedNative);
        dustRecipient = dustRecipient_;
    }

    receive() external payable {
        if (msg.sender != address(weth9)) revert DirectEthDisabled();
    }

    // Slither cannot infer that nonReentrant prevents callbacks from every immutable external dependency. The final
    // baseline comparisons are deliberate post-conditions, not state used to authorize an external call.
    // slither-disable-start reentrancy-balance
    function migrate(address token, uint256 tokenAmount, address positionRecipient)
        external
        payable
        nonReentrant
        returns (bytes32 outcomeId, uint256)
    {
        if (token == address(0) || positionRecipient == address(0)) revert ZeroAddress();
        if (positionRecipient.code.length == 0) revert InvalidContract();
        if (token == address(weth9)) revert InvalidAsset();
        if (tokenAmount == 0 || msg.value == 0) revert InvalidAmount();

        IERC20 launchToken = IERC20(token);
        uint256 tokenBalanceBefore = launchToken.balanceOf(address(this));
        uint256 wethBalanceBefore = weth9.balanceOf(address(this));
        uint256 ethBalanceBefore = address(this).balance - msg.value;
        launchToken.safeTransferFrom(msg.sender, address(this), tokenAmount);
        if (launchToken.balanceOf(address(this)) - tokenBalanceBefore != tokenAmount) {
            revert DeflationaryTokenUnsupported();
        }
        weth9.deposit{value: msg.value}();

        MintResult memory result = _mintPosition(launchToken, token, tokenAmount, msg.value, positionRecipient, true);
        uint256 tokenDust = tokenAmount - result.tokenUsed;
        uint256 ethDust = msg.value - result.wethUsed;
        IVOIDPositionLockRegistration(positionRecipient).registerPosition(result.tokenId);
        if (tokenDust > 0) launchToken.safeTransfer(dustRecipient, tokenDust);
        if (ethDust > 0) {
            weth9.withdraw(ethDust);
            Address.sendValue(payable(dustRecipient), ethDust);
        }
        // Every external state-changing path above is protected by nonReentrant. These baseline comparisons ensure
        // the stateless adapter retains none of this call's assets while preserving any forced preexisting balances.
        // slither-disable-next-line reentrancy-balance
        if (
            launchToken.balanceOf(address(this)) != tokenBalanceBefore
                || weth9.balanceOf(address(this)) != wethBalanceBefore || address(this).balance != ethBalanceBefore
        ) revert UnexpectedBalance();

        outcomeId = _recordPosition(token, positionRecipient, result, tokenDust, ethDust);
        return (outcomeId, result.tokenId);
    }

    /// @notice Creates a capped first position even if a stranger initialized the pool at a hostile price.
    /// @dev Mint minimums are intentionally zero only for this bounded seed. Every unused unit is returned to the
    /// caller, which is expected to be the bonding curve. Full migration retains its strict 99.9% minimums.
    function seed(address token, uint256 tokenAmount, address positionRecipient)
        external
        payable
        nonReentrant
        returns (bytes32, uint256, uint256, uint256)
    {
        if (token == address(0) || positionRecipient == address(0)) revert ZeroAddress();
        if (positionRecipient.code.length == 0) revert InvalidContract();
        if (token == address(weth9)) revert InvalidAsset();
        if (tokenAmount == 0 || msg.value == 0) revert InvalidAmount();

        IERC20 launchToken = IERC20(token);
        uint256 tokenBalanceBefore = launchToken.balanceOf(address(this));
        uint256 wethBalanceBefore = weth9.balanceOf(address(this));
        uint256 ethBalanceBefore = address(this).balance - msg.value;
        launchToken.safeTransferFrom(msg.sender, address(this), tokenAmount);
        if (launchToken.balanceOf(address(this)) - tokenBalanceBefore != tokenAmount) {
            revert DeflationaryTokenUnsupported();
        }
        weth9.deposit{value: msg.value}();

        MintResult memory result = _mintPosition(launchToken, token, tokenAmount, msg.value, positionRecipient, false);
        uint256 tokenReturned = tokenAmount - result.tokenUsed;
        uint256 ethReturned = msg.value - result.wethUsed;
        IVOIDPositionLockRegistration(positionRecipient).registerPosition(result.tokenId);
        if (tokenReturned > 0) launchToken.safeTransfer(msg.sender, tokenReturned);
        if (ethReturned > 0) {
            weth9.withdraw(ethReturned);
            Address.sendValue(payable(msg.sender), ethReturned);
        }
        if (
            launchToken.balanceOf(address(this)) != tokenBalanceBefore
                || weth9.balanceOf(address(this)) != wethBalanceBefore || address(this).balance != ethBalanceBefore
        ) revert UnexpectedBalance();

        bytes32 outcomeId = _recordSeed(token, positionRecipient, result, tokenReturned, ethReturned);
        return (outcomeId, result.tokenId, result.tokenUsed, result.wethUsed);
    }
    // slither-disable-end reentrancy-balance

    function _recordPosition(
        address token,
        address positionRecipient,
        MintResult memory result,
        uint256 tokenDust,
        uint256 ethDust
    ) private returns (bytes32 outcomeId) {
        outcomeId = keccak256(
            abi.encode(
                block.chainid,
                address(this),
                result.pool,
                result.tokenId,
                result.liquidity,
                result.tokenUsed,
                result.wethUsed,
                positionRecipient
            )
        );
        emit PositionCreated(
            token,
            result.pool,
            positionRecipient,
            result.tokenId,
            result.liquidity,
            result.tokenUsed,
            result.wethUsed,
            tokenDust,
            ethDust
        );
    }

    function _recordSeed(
        address token,
        address positionRecipient,
        MintResult memory result,
        uint256 tokenReturned,
        uint256 ethReturned
    ) private returns (bytes32 outcomeId) {
        outcomeId = keccak256(
            abi.encode(
                block.chainid,
                address(this),
                result.pool,
                result.tokenId,
                result.liquidity,
                result.tokenUsed,
                result.wethUsed,
                positionRecipient,
                bytes32("VOID_POOL_SEED")
            )
        );
        emit PoolSeeded(
            token,
            result.pool,
            positionRecipient,
            result.tokenId,
            result.liquidity,
            result.tokenUsed,
            result.wethUsed,
            tokenReturned,
            ethReturned
        );
    }

    function _mintPosition(
        IERC20 launchToken,
        address token,
        uint256 tokenAmount,
        uint256 ethAmount,
        address positionRecipient,
        bool strictMinimums
    ) private returns (MintResult memory result) {
        bool tokenIsToken0 = token < address(weth9);
        // All fields are assigned below before the struct crosses an external-call boundary.
        // slither-disable-next-line uninitialized-local
        IVOIDUniswapV3PositionManager.MintParams memory params;
        params.token0 = tokenIsToken0 ? token : address(weth9);
        params.token1 = tokenIsToken0 ? address(weth9) : token;
        params.fee = POOL_FEE;
        params.tickLower = TICK_LOWER;
        params.tickUpper = TICK_UPPER;
        params.amount0Desired = tokenIsToken0 ? tokenAmount : ethAmount;
        params.amount1Desired = tokenIsToken0 ? ethAmount : tokenAmount;
        if (strictMinimums) {
            params.amount0Min = Math.mulDiv(params.amount0Desired, MINIMUM_MINT_BPS, BPS, Math.Rounding.Ceil);
            params.amount1Min = Math.mulDiv(params.amount1Desired, MINIMUM_MINT_BPS, BPS, Math.Rounding.Ceil);
        }
        params.recipient = positionRecipient;
        params.deadline = block.timestamp;

        uint160 sqrtPriceX96 = _encodeSqrtRatioX96(params.amount1Desired, params.amount0Desired);
        result.pool =
            positionManager.createAndInitializePoolIfNecessary(params.token0, params.token1, POOL_FEE, sqrtPriceX96);
        if (result.pool == address(0)) revert InvalidContract();
        launchToken.forceApprove(address(positionManager), tokenAmount);
        IERC20(address(weth9)).forceApprove(address(positionManager), ethAmount);
        uint256 amount0;
        uint256 amount1;
        (result.tokenId, result.liquidity, amount0, amount1) = positionManager.mint(params);
        if (
            result.liquidity < 1 || amount0 < params.amount0Min || amount1 < params.amount1Min
                || amount0 > params.amount0Desired || amount1 > params.amount1Desired
        ) revert InsufficientLiquidityMinted();
        launchToken.forceApprove(address(positionManager), 0);
        IERC20(address(weth9)).forceApprove(address(positionManager), 0);
        result.tokenUsed = tokenIsToken0 ? amount0 : amount1;
        result.wethUsed = tokenIsToken0 ? amount1 : amount0;
    }

    function _encodeSqrtRatioX96(uint256 amount1, uint256 amount0) private pure returns (uint160 sqrtPriceX96) {
        uint256 ratioX192 = Math.mulDiv(amount1, Q192, amount0);
        uint256 sqrtRatio = Math.sqrt(ratioX192);
        if (sqrtRatio <= MIN_SQRT_RATIO || sqrtRatio >= MAX_SQRT_RATIO) revert InvalidPrice();
        sqrtPriceX96 = uint160(sqrtRatio);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {VOIDUniswapV3Migration, IVOIDUniswapV3PositionManager, IVOIDWETH9} from "../src/VOIDUniswapV3Migration.sol";
import {VOIDPositionLocker} from "../src/VOIDPositionLocker.sol";
import {VOIDLaunch} from "../src/VOIDLaunch.sol";
import {VOIDBondingCurve} from "../src/VOIDBondingCurve.sol";
import {VOIDCoin} from "../src/VOIDCoin.sol";

interface IVOIDPositionOwner {
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IVOIDSwapRouter02 {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

contract ForkLaunchToken is ERC20 {
    constructor() ERC20("VOID Fork Rehearsal", "VFORK") {
        _mint(msg.sender, 980_000_000 ether);
    }
}

/// @dev Run explicitly with `forge test --root contracts --fork-url <BASE_MAINNET_RPC> --match-contract VOIDUniswapV3MigrationForkTest`.
contract VOIDUniswapV3MigrationForkTest is Test {
    address internal constant POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    address internal constant SWAP_ROUTER_02 = 0x2626664c2603336E57B271c5C0b26F421741e481;

    struct RecoveryContext {
        IERC20 token;
        VOIDUniswapV3Migration adapter;
        VOIDPositionLocker locker;
        address weth;
        address token0;
        address token1;
        uint256 tokenAmount;
        uint256 ethAmount;
    }

    receive() external payable {}

    function testBaseMainnetPositionManagerCreatesAndTransfersFullRangePosition() public {
        if (block.chainid != 8453) vm.skip(true);

        address beneficiary = makeAddr("fork-safe");
        ForkLaunchToken token = new ForkLaunchToken();
        VOIDUniswapV3Migration adapter =
            new VOIDUniswapV3Migration(IVOIDUniswapV3PositionManager(POSITION_MANAGER), address(this));
        VOIDPositionLocker locker = new VOIDPositionLocker(IERC721(POSITION_MANAGER), beneficiary);
        uint256 tokenAmount = 900_000_000 ether;
        uint256 ethAmount = 2 ether;
        vm.deal(address(this), ethAmount);
        IERC20(address(token)).approve(address(adapter), tokenAmount);

        vm.recordLogs();
        (bytes32 outcome,) = adapter.migrate{value: ethAmount}(address(token), tokenAmount, address(locker));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertNotEq(outcome, bytes32(0));
        assertEq(token.balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);

        bytes32 signature =
            keccak256("PositionCreated(address,address,address,uint256,uint128,uint256,uint256,uint256,uint256)");
        uint256 tokenId;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(adapter) && logs[i].topics[0] == signature) {
                (tokenId,,,,,) = abi.decode(logs[i].data, (uint256, uint128, uint256, uint256, uint256, uint256));
                break;
            }
        }
        assertGt(tokenId, 0);
        assertEq(IVOIDPositionOwner(POSITION_MANAGER).ownerOf(tokenId), address(locker));
        assertEq(locker.unlockAt(tokenId), uint64(block.timestamp + locker.LOCK_DURATION()));
    }

    function testBaseMainnetHostilePreInitializationIsRecoverableAfterCappedSeed() public {
        if (block.chainid != 8453) vm.skip(true);

        address beneficiary = makeAddr("fork-hostile-safe");
        ForkLaunchToken token = new ForkLaunchToken();
        IVOIDUniswapV3PositionManager manager = IVOIDUniswapV3PositionManager(POSITION_MANAGER);
        VOIDUniswapV3Migration adapter = new VOIDUniswapV3Migration(manager, address(this));
        VOIDPositionLocker locker = new VOIDPositionLocker(IERC721(POSITION_MANAGER), beneficiary);
        uint256 tokenAmount = 900_000_000 ether;
        uint256 ethAmount = 2 ether;
        address weth = manager.WETH9();
        (address token0, address token1) = address(token) < weth ? (address(token), weth) : (weth, address(token));
        uint256 amount0 = token0 == address(token) ? tokenAmount : ethAmount;
        uint256 amount1 = token1 == address(token) ? tokenAmount : ethAmount;
        uint256 ratioX192 = Math.mulDiv(amount1, uint256(1) << 192, amount0);
        uint160 hostileSqrtPriceX96 = uint160(Math.sqrt(ratioX192) * 2);

        manager.createAndInitializePoolIfNecessary(token0, token1, adapter.POOL_FEE(), hostileSqrtPriceX96);
        RecoveryContext memory context = RecoveryContext({
            token: IERC20(address(token)),
            adapter: adapter,
            locker: locker,
            weth: weth,
            token0: token0,
            token1: token1,
            tokenAmount: tokenAmount,
            ethAmount: ethAmount
        });
        _seedArbitrageAndMigrate(context);
    }

    function testBaseMainnetFullProductionGraduationBurnsExcessAtContinuousPrice() public {
        if (block.chainid != 8453) vm.skip(true);

        IVOIDUniswapV3PositionManager manager = IVOIDUniswapV3PositionManager(POSITION_MANAGER);
        VOIDUniswapV3Migration adapter = new VOIDUniswapV3Migration(manager, address(this));
        VOIDPositionLocker locker = new VOIDPositionLocker(IERC721(POSITION_MANAGER), address(this));
        VOIDLaunch launch =
            new VOIDLaunch(address(this), address(adapter), address(locker), 100 ether, 25 ether, "ipfs://fork");
        VOIDCoin token = launch.token();
        VOIDBondingCurve curve = launch.bondingCurve();
        vm.deal(address(this), 100 ether);

        for (uint256 i; i < 25; ++i) {
            uint256 quote = curve.quoteBuy(1 ether);
            curve.buy{value: 1 ether}(quote, block.timestamp);
        }
        uint256 supplyBefore = token.totalSupply();
        (uint256 preSeedLiquidityTokens,) = curve.graduationLiquidityQuote();
        address weth = manager.WETH9();
        (address token0, address token1) = address(token) < weth ? (address(token), weth) : (weth, address(token));
        uint160 hostileSqrtPriceX96 = _sqrtPrice(
            token0 == address(token) ? preSeedLiquidityTokens : curve.ethReserve(),
            token1 == address(token) ? preSeedLiquidityTokens : curve.ethReserve()
        ) * 2;
        manager.createAndInitializePoolIfNecessary(token0, token1, adapter.POOL_FEE(), hostileSqrtPriceX96);

        curve.seedMigrationPool();
        (uint256 liquidityTokens, uint256 tokensToBurn) = curve.graduationLiquidityQuote();
        RecoveryContext memory context = RecoveryContext({
            token: IERC20(address(token)),
            adapter: adapter,
            locker: locker,
            weth: weth,
            token0: token0,
            token1: token1,
            tokenAmount: liquidityTokens,
            ethAmount: curve.ethReserve()
        });
        _arbitrageToFairPrice(context, liquidityTokens, curve.ethReserve());
        curve.graduate();

        assertTrue(curve.graduated());
        assertEq(token.totalSupply(), supplyBefore - tokensToBurn);
        assertEq(token.balanceOf(address(curve)), 0);
        assertEq(token.balanceOf(address(launch)), 0);
        assertEq(curve.tokenReserve(), 0);
        assertEq(curve.ethReserve(), 0);
    }

    function _seedArbitrageAndMigrate(RecoveryContext memory context) private {
        vm.deal(address(this), 20 ether);
        (uint256 remainingTokens, uint256 remainingEth) = _seedHostilePool(context);
        _arbitrageToFairPrice(context, remainingTokens, remainingEth);
        (bytes32 outcome, uint256 finalTokenId) = context.adapter.migrate{value: remainingEth}(
            address(context.token), remainingTokens, address(context.locker)
        );
        assertNotEq(outcome, bytes32(0));
        assertTrue(context.locker.isRegisteredPosition(finalTokenId, address(context.adapter)));
    }

    function _seedHostilePool(RecoveryContext memory context)
        private
        returns (uint256 remainingTokens, uint256 remainingEth)
    {
        uint256 tokenSeedCap = context.tokenAmount / 1_000;
        uint256 ethSeedCap = context.ethAmount / 1_000;
        IERC20(address(context.token)).approve(address(context.adapter), context.tokenAmount + tokenSeedCap);

        (, uint256 seedTokenId, uint256 tokenUsed, uint256 ethUsed) =
            context.adapter.seed{value: ethSeedCap}(address(context.token), tokenSeedCap, address(context.locker));
        assertTrue(tokenUsed <= tokenSeedCap && ethUsed <= ethSeedCap);
        assertTrue(tokenUsed > 0 || ethUsed > 0);
        assertTrue(context.locker.isRegisteredPosition(seedTokenId, address(context.adapter)));

        remainingTokens = context.tokenAmount - tokenUsed;
        remainingEth = context.ethAmount - ethUsed;
    }

    function _arbitrageToFairPrice(RecoveryContext memory context, uint256 remainingTokens, uint256 remainingEth)
        private
    {
        uint160 fairSqrtPriceX96 = _sqrtPrice(
            context.token0 == address(context.token) ? remainingTokens : remainingEth,
            context.token1 == address(context.token) ? remainingTokens : remainingEth
        );
        uint256 swapAmount = context.token0 == address(context.token) ? 100_000_000 ether : 10 ether;
        if (context.token0 == address(context.token)) {
            IERC20(address(context.token)).approve(SWAP_ROUTER_02, swapAmount);
        } else {
            IVOIDWETH9(context.weth).deposit{value: swapAmount}();
            IERC20(context.weth).approve(SWAP_ROUTER_02, swapAmount);
        }
        IVOIDSwapRouter02(SWAP_ROUTER_02)
            .exactInputSingle(
                IVOIDSwapRouter02.ExactInputSingleParams({
                tokenIn: context.token0,
                tokenOut: context.token1,
                fee: context.adapter.POOL_FEE(),
                recipient: address(this),
                amountIn: swapAmount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: fairSqrtPriceX96
            })
            );
    }

    function _sqrtPrice(uint256 amount0, uint256 amount1) private pure returns (uint160) {
        return uint160(Math.sqrt(Math.mulDiv(amount1, uint256(1) << 192, amount0)));
    }
}

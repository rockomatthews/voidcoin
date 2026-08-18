// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VOIDV2Launch, IVOIDV2PositionManager} from "../src/VOIDV2Launch.sol";
import {VOIDV2BuyRouter, IVOIDV2WETH, IVOIDV2SwapRouter} from "../src/VOIDV2BuyRouter.sol";

interface IVOIDV3PoolStateFull {
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
}

interface IWETH9Reader {
    // Canonical deployed selector; capitalization is fixed by Uniswap.
    // slither-disable-next-line naming-convention
    function WETH9() external view returns (address);
}

contract V2ForkSafe {}

contract VOIDV2LaunchForkTest is Test {
    address internal constant POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    address internal constant SWAP_ROUTER_02 = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    uint24 internal constant WETH_USDC_FEE = 500;

    function _forkAndLaunch() private returns (VOIDV2Launch launch) {
        string memory rpc = vm.envOr("BASE_MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return launch;
        }
        vm.createSelectFork(rpc);
        launch = new VOIDV2Launch(
            address(new V2ForkSafe()), IVOIDV2PositionManager(POSITION_MANAGER), IERC20(USDC), "ipfs://genesis"
        );
    }

    function testBaseMainnetVirginPoolLaunchAndRealEthPurchase() public {
        VOIDV2Launch launch = _forkAndLaunch();
        if (address(launch) == address(0)) return;
        address token = address(launch.token());
        (uint160 startingPrice,,,,,,) = IVOIDV3PoolStateFull(launch.pool()).slot0();
        uint160 expectedPrice =
            token < USDC ? launch.TOKEN0_START_SQRT_PRICE_X96() : launch.TOKEN1_START_SQRT_PRICE_X96();
        assertEq(startingPrice, expectedPrice);
        assertEq(IWETH9Reader(POSITION_MANAGER).WETH9(), WETH);
        assertEq(launch.tokensSeeded() + launch.launchDustBurned(), launch.token().LAUNCH_ALLOCATION());

        VOIDV2BuyRouter buyRouter = new VOIDV2BuyRouter(
            IVOIDV2WETH(WETH),
            IERC20(USDC),
            IERC20(token),
            IVOIDV2SwapRouter(SWAP_ROUTER_02),
            WETH_USDC_FEE,
            launch.POOL_FEE()
        );
        address buyer = makeAddr("forkBuyer");
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        uint256 tokensOut = buyRouter.buyWithETH{value: 0.0001 ether}(1);

        assertGt(tokensOut, 0);
        assertEq(IERC20(token).balanceOf(buyer), tokensOut);
        (uint160 priceAfter,,,,,,) = IVOIDV3PoolStateFull(launch.pool()).slot0();
        if (token < USDC) assertGt(priceAfter, startingPrice);
        else assertLt(priceAfter, startingPrice);

        uint256 tokensToSell = tokensOut / 2;
        vm.startPrank(buyer);
        IERC20(token).approve(SWAP_ROUTER_02, tokensToSell);
        uint256 usdcOut = IVOIDV2SwapRouter(SWAP_ROUTER_02)
            .exactInput(
                IVOIDV2SwapRouter.ExactInputParams({
                path: abi.encodePacked(token, launch.POOL_FEE(), USDC),
                recipient: buyer,
                amountIn: tokensToSell,
                amountOutMinimum: 1
            })
            );
        vm.stopPrank();
        assertGt(usdcOut, 0);
        assertEq(IERC20(USDC).balanceOf(buyer), usdcOut);
        (uint160 priceAfterSell,,,,,,) = IVOIDV3PoolStateFull(launch.pool()).slot0();
        if (token < USDC) assertLt(priceAfterSell, priceAfter);
        else assertGt(priceAfterSell, priceAfter);
    }

    function testOneDollarAtGenesisBuysApproximatelyInitialTakeover() public {
        VOIDV2Launch launch = _forkAndLaunch();
        if (address(launch) == address(0)) return;

        address buyer = makeAddr("oneDollarBuyer");
        deal(USDC, buyer, 1_000_000);
        vm.startPrank(buyer);
        IERC20(USDC).approve(SWAP_ROUTER_02, 1_000_000);
        uint256 tokensOut = IVOIDV2SwapRouter(SWAP_ROUTER_02)
            .exactInput(
                IVOIDV2SwapRouter.ExactInputParams({
                path: abi.encodePacked(USDC, launch.POOL_FEE(), address(launch.token())),
                recipient: buyer,
                amountIn: 1_000_000,
                amountOutMinimum: 1
            })
            );
        vm.stopPrank();

        assertEq(IERC20(USDC).balanceOf(buyer), 0);
        assertEq(launch.token().balanceOf(buyer), tokensOut);
        emit log_named_decimal_uint("VOID received for exactly 1 USDC", tokensOut, 18);
        assertGe(tokensOut, launch.token().INITIAL_BURN());
        assertLe(tokensOut, 1_020_000 ether);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VOIDBondingCurve} from "../src/VOIDBondingCurve.sol";
import {VOIDCoin} from "../src/VOIDCoin.sol";
import {VOIDLaunch} from "../src/VOIDLaunch.sol";

contract MockMigrationTarget {
    address public migratedToken;
    uint256 public migratedTokens;
    uint256 public migratedEth;

    function migrate(address token, uint256 tokenAmount) external payable {
        migratedToken = token;
        migratedTokens = tokenAmount;
        migratedEth = msg.value;
        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);
    }
}

contract VOIDLaunchTest is Test {
    address internal safe = makeAddr("safe");
    address internal buyer = makeAddr("buyer");
    MockMigrationTarget internal migrationTarget;
    VOIDLaunch internal launch;
    VOIDCoin internal token;
    VOIDBondingCurve internal curve;

    function setUp() public {
        migrationTarget = new MockMigrationTarget();
        launch = new VOIDLaunch(safe, address(migrationTarget), 1 ether, 2 ether, "ipfs://genesis");
        token = launch.token();
        curve = launch.bondingCurve();
        vm.deal(buyer, 10 ether);
    }

    function testLaunchAllocationMovesIntoContinuousCurve() public view {
        assertEq(token.balanceOf(address(curve)), 900_000_000 ether);
        assertEq(token.balanceOf(address(launch)), 0);
        assertEq(token.balanceOf(address(launch.vestingWallet())), 100_000_000 ether);
        assertEq(token.pendingOwner(), safe);
        assertEq(token.owner(), address(launch));
        assertEq(curve.owner(), safe);
        assertEq(curve.virtualEthReserve(), 1 ether);
        assertEq(curve.graduationThreshold(), 2 ether);
    }

    function testBuyAndSellUseBuyerFundedReserve() public {
        uint256 expectedTokens = curve.quoteBuy(1 ether);
        vm.prank(buyer);
        uint256 tokensOut = curve.buy{value: 1 ether}(expectedTokens);
        assertEq(tokensOut, expectedTokens);
        assertEq(token.balanceOf(buyer), expectedTokens);
        assertEq(address(curve).balance, 1 ether);

        uint256 tokensToSell = expectedTokens / 2;
        vm.startPrank(buyer);
        token.approve(address(curve), tokensToSell);
        uint256 expectedEth = curve.quoteSell(tokensToSell);
        uint256 ethOut = curve.sell(tokensToSell, expectedEth);
        vm.stopPrank();

        assertEq(ethOut, expectedEth);
        assertEq(address(curve).balance, 1 ether - expectedEth);
    }

    function testCurveHasNoAuctionDeadline() public {
        vm.warp(block.timestamp + 365 days);
        vm.prank(buyer);
        curve.buy{value: 0.1 ether}(0);
        assertGt(token.balanceOf(buyer), 0);
        assertFalse(curve.graduationReady());
    }

    function testBuyerEthTriggersSafeGatedGraduation() public {
        vm.startPrank(buyer);
        curve.buy{value: 1 ether}(0);
        curve.buy{value: 1 ether}(0);
        vm.stopPrank();
        assertTrue(curve.graduationReady());

        vm.expectRevert();
        curve.graduate();

        uint256 remainingTokens = token.balanceOf(address(curve));
        vm.prank(safe);
        curve.graduate();

        assertTrue(curve.graduated());
        assertEq(migrationTarget.migratedToken(), address(token));
        assertEq(migrationTarget.migratedTokens(), remainingTokens);
        assertEq(migrationTarget.migratedEth(), 2 ether);
        assertEq(token.balanceOf(address(curve)), 0);
        assertEq(address(curve).balance, 0);
    }

    function testTradesCloseOnceGraduationIsReady() public {
        vm.prank(buyer);
        curve.buy{value: 2 ether}(0);

        vm.expectRevert(VOIDBondingCurve.CurveClosed.selector);
        vm.prank(buyer);
        curve.buy{value: 0.1 ether}(0);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VOIDBondingCurve} from "../src/VOIDBondingCurve.sol";
import {VOIDCoin} from "../src/VOIDCoin.sol";
import {VOIDLaunch} from "../src/VOIDLaunch.sol";
import {VOIDTreasuryVesting} from "../src/VOIDTreasuryVesting.sol";

contract MockSafe {}

contract MockPositionRecipient {}

contract MockMigrationTarget {
    address public migratedToken;
    uint256 public migratedTokens;
    uint256 public migratedEth;
    address public positionRecipient;
    bool public shouldRevert;

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function migrate(address token, uint256 tokenAmount, address recipient) external payable returns (bytes32) {
        if (shouldRevert) revert("offline");
        migratedToken = token;
        migratedTokens = tokenAmount;
        migratedEth = msg.value;
        positionRecipient = recipient;
        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);
        return keccak256(abi.encode(token, tokenAmount, msg.value, recipient));
    }
}

contract VOIDLaunchTest is Test {
    address internal safe;
    address internal buyer = makeAddr("buyer");
    address internal positionRecipient;
    MockMigrationTarget internal migrationTarget;
    VOIDLaunch internal launch;
    VOIDCoin internal token;
    VOIDBondingCurve internal curve;
    VOIDTreasuryVesting internal vesting;

    function setUp() public {
        safe = address(new MockSafe());
        positionRecipient = address(new MockPositionRecipient());
        migrationTarget = new MockMigrationTarget();
        launch = new VOIDLaunch(safe, address(migrationTarget), positionRecipient, 1 ether, 2 ether, "ipfs://genesis");
        token = launch.token();
        curve = launch.bondingCurve();
        vesting = launch.vestingWallet();
        vm.deal(buyer, 10 ether);
    }

    function testLaunchAllocationAndAuthority() public view {
        assertEq(token.balanceOf(address(curve)), 980_000_000 ether);
        assertEq(curve.tokenReserve(), 980_000_000 ether);
        assertEq(token.balanceOf(address(launch)), 0);
        assertEq(token.balanceOf(address(vesting)), 20_000_000 ether);
        assertEq(token.owner(), safe);
        assertEq(curve.owner(), safe);
        assertEq(curve.positionRecipient(), positionRecipient);
        assertEq(curve.virtualEthReserve(), 1 ether);
        assertEq(curve.graduationThreshold(), 2 ether);
        assertTrue(token.renamePaused());
    }

    function testBuyAndSellChargeOnePercentAndRoundAgainstTrader() public {
        uint256 expectedTokens = curve.quoteBuy(1 ether);
        vm.prank(buyer);
        uint256 tokensOut = curve.buy{value: 1 ether}(expectedTokens, block.timestamp);
        assertEq(tokensOut, expectedTokens);
        assertEq(token.balanceOf(buyer), expectedTokens);
        assertEq(curve.ethReserve(), 1 ether);

        vm.startPrank(buyer);
        token.approve(address(curve), tokensOut);
        uint256 expectedEth = curve.quoteSell(tokensOut);
        uint256 ethOut = curve.sell(tokensOut, expectedEth, block.timestamp);
        vm.stopPrank();

        assertEq(ethOut, expectedEth);
        assertLt(ethOut, 1 ether);
        assertEq(address(curve).balance, curve.ethReserve());
    }

    function testForcedEthDoesNotAffectPriceOrGraduation() public {
        uint256 quoteBefore = curve.quoteBuy(1 ether);
        vm.deal(address(curve), 100 ether);
        assertEq(curve.quoteBuy(1 ether), quoteBefore);
        assertFalse(curve.graduationReady());
        assertEq(curve.ethReserve(), 0);
    }

    function testTradingRemainsOpenAfterThresholdUntilSuccessfulMigration() public {
        uint256 quote = curve.quoteBuy(2 ether);
        vm.prank(buyer);
        curve.buy{value: 2 ether}(quote, block.timestamp);
        assertTrue(curve.graduationReady());

        uint256 sellAmount = token.balanceOf(buyer) / 10;
        vm.startPrank(buyer);
        token.approve(address(curve), sellAmount);
        uint256 ethQuote = curve.quoteSell(sellAmount);
        curve.sell(sellAmount, ethQuote, block.timestamp);
        vm.stopPrank();
    }

    function testMigrationFailureLeavesTradingOpen() public {
        uint256 quote = curve.quoteBuy(2 ether);
        vm.prank(buyer);
        curve.buy{value: 2 ether}(quote, block.timestamp);
        migrationTarget.setShouldRevert(true);

        vm.expectRevert(VOIDBondingCurve.MigrationFailed.selector);
        vm.prank(safe);
        curve.graduate();

        assertFalse(curve.graduated());
        assertTrue(curve.graduationReady());
        assertEq(curve.ethReserve(), 2 ether);
        uint256 sellAmount = token.balanceOf(buyer) / 10;
        vm.startPrank(buyer);
        token.approve(address(curve), sellAmount);
        curve.sell(sellAmount, curve.quoteSell(sellAmount), block.timestamp);
        vm.stopPrank();
    }

    function testSuccessfulGraduationStartsTreasuryVesting() public {
        uint256 quote = curve.quoteBuy(2 ether);
        vm.prank(buyer);
        curve.buy{value: 2 ether}(quote, block.timestamp);
        uint256 remainingTokens = curve.tokenReserve();

        vm.prank(safe);
        curve.graduate();

        assertTrue(curve.graduated());
        assertGt(curve.graduatedAt(), 0);
        assertEq(migrationTarget.migratedTokens(), remainingTokens);
        assertEq(migrationTarget.migratedEth(), 2 ether);
        assertEq(migrationTarget.positionRecipient(), positionRecipient);
        vm.expectRevert(VOIDTreasuryVesting.NothingToRelease.selector);
        vesting.release();

        vm.warp(block.timestamp + 182.5 days);
        uint256 released = vesting.release();
        assertApproxEqAbs(released, 10_000_000 ether, 1 ether);
        assertEq(token.balanceOf(safe), released);
    }

    function testDeadlinesAndNonzeroSlippageAreRequired() public {
        vm.expectRevert(VOIDBondingCurve.ZeroInput.selector);
        vm.prank(buyer);
        curve.buy{value: 1 ether}(0, block.timestamp);

        vm.expectRevert(VOIDBondingCurve.DeadlineExpired.selector);
        vm.prank(buyer);
        curve.buy{value: 1 ether}(1, block.timestamp - 1);
    }

    function testMaxSellableMakesUnpayableSellExplicit() public {
        uint256 quote = curve.quoteBuy(1 ether);
        vm.prank(buyer);
        curve.buy{value: 1 ether}(quote, block.timestamp);

        uint256 maximum = curve.maxSellable();
        assertGt(maximum, 0);
        assertLe(curve.quoteSell(maximum), curve.ethReserve());

        vm.expectRevert(VOIDBondingCurve.InsufficientCurveLiquidity.selector);
        curve.quoteSell(type(uint128).max);
    }

    function testOwnershipCannotBeRenounced() public {
        vm.expectRevert(VOIDBondingCurve.RenouncingDisabled.selector);
        vm.prank(safe);
        curve.renounceOwnership();

        vm.expectRevert(VOIDCoin.RenouncingDisabled.selector);
        vm.prank(safe);
        token.renounceOwnership();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {VOIDBondingCurve} from "../src/VOIDBondingCurve.sol";
import {VOIDCoin} from "../src/VOIDCoin.sol";
import {VOIDLaunch} from "../src/VOIDLaunch.sol";
import {VOIDTreasuryVesting} from "../src/VOIDTreasuryVesting.sol";

contract MockSafe {}

contract MockPositionRecipient {
    mapping(uint256 tokenId => address registrar) public registeredBy;

    function registerPosition(uint256 tokenId) external {
        registeredBy[tokenId] = msg.sender;
    }

    function isRegisteredPosition(uint256 tokenId, address registrar) external view returns (bool) {
        return registeredBy[tokenId] == registrar;
    }
}

contract MockMigrationTarget {
    address public migratedToken;
    uint256 public migratedTokens;
    uint256 public migratedEth;
    address public positionRecipient;
    bool public shouldRevert;
    uint256 public seededTokens;
    uint256 public seededEth;
    uint256 public nextPositionTokenId = 1;

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function migrate(address token, uint256 tokenAmount, address recipient)
        external
        payable
        returns (bytes32, uint256)
    {
        if (shouldRevert) revert("offline");
        migratedToken = token;
        migratedTokens = tokenAmount;
        migratedEth = msg.value;
        positionRecipient = recipient;
        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);
        uint256 tokenId = nextPositionTokenId++;
        MockPositionRecipient(recipient).registerPosition(tokenId);
        return (keccak256(abi.encode(token, tokenAmount, msg.value, recipient)), tokenId);
    }

    function seed(address token, uint256 tokenAmount, address recipient)
        external
        payable
        returns (bytes32, uint256, uint256, uint256)
    {
        if (shouldRevert) revert("offline");
        seededTokens += tokenAmount;
        seededEth += msg.value;
        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);
        uint256 tokenId = nextPositionTokenId++;
        MockPositionRecipient(recipient).registerPosition(tokenId);
        return
            (keccak256(abi.encode("seed", token, tokenAmount, msg.value, recipient)), tokenId, tokenAmount, msg.value);
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
        launch = new VOIDLaunch(safe, address(migrationTarget), positionRecipient, 100 ether, 2 ether, "ipfs://genesis");
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
        assertEq(curve.virtualEthReserve(), 100 ether);
        assertEq(curve.maxBuyAmount(), 1 ether);
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
        _fundToThreshold();
        assertTrue(curve.graduationReady());

        uint256 sellAmount = token.balanceOf(buyer) / 10;
        vm.startPrank(buyer);
        token.approve(address(curve), sellAmount);
        uint256 ethQuote = curve.quoteSell(sellAmount);
        curve.sell(sellAmount, ethQuote, block.timestamp);
        vm.stopPrank();
        assertTrue(curve.graduationReady(), "threshold eligibility must remain latched after a sell");
    }

    function testMigrationProposalCanBeCancelledAndExpires() public {
        MockMigrationTarget replacement = new MockMigrationTarget();
        vm.prank(safe);
        curve.proposeMigrationTarget(address(replacement));
        vm.prank(safe);
        curve.cancelMigrationTarget();
        assertEq(curve.pendingMigrationTarget(), address(0));

        vm.prank(safe);
        curve.proposeMigrationTarget(address(replacement));
        vm.warp(block.timestamp + curve.MIGRATION_DELAY() + curve.MIGRATION_PROPOSAL_WINDOW() + 1);
        vm.expectRevert(VOIDBondingCurve.MigrationProposalExpired.selector);
        vm.prank(safe);
        curve.acceptMigrationTarget();
    }

    function testMigrationFailureLeavesTradingOpen() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();
        uint256 supplyBefore = token.totalSupply();
        uint256 reserveBefore = curve.tokenReserve();
        migrationTarget.setShouldRevert(true);

        vm.expectRevert(VOIDBondingCurve.MigrationFailed.selector);
        vm.prank(safe);
        curve.graduate();

        assertFalse(curve.graduated());
        assertTrue(curve.graduationReady());
        assertEq(curve.ethReserve() + curve.seededEthLiquidity(), 2 ether);
        assertEq(curve.tokenReserve(), reserveBefore);
        assertEq(token.totalSupply(), supplyBefore);
        uint256 sellAmount = token.balanceOf(buyer) / 10;
        vm.startPrank(buyer);
        token.approve(address(curve), sellAmount);
        curve.sell(sellAmount, curve.quoteSell(sellAmount), block.timestamp);
        vm.stopPrank();
    }

    function testSuccessfulGraduationStartsTreasuryVesting() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();
        uint256 reserveTokens = curve.tokenReserve();
        uint256 supplyBefore = token.totalSupply();
        (uint256 liquidityTokens, uint256 tokensToBurn) = curve.graduationLiquidityQuote();
        assertEq(
            liquidityTokens,
            Math.mulDiv(curve.ethReserve(), reserveTokens, curve.virtualEthReserve() + curve.ethReserve())
        );

        vm.prank(makeAddr("graduation-keeper"));
        curve.graduate();

        assertTrue(curve.graduated());
        assertGt(curve.graduatedAt(), 0);
        assertEq(migrationTarget.migratedTokens(), liquidityTokens);
        assertEq(migrationTarget.migratedEth() + migrationTarget.seededEth(), 2 ether);
        assertEq(token.totalSupply(), supplyBefore - tokensToBurn);
        assertEq(token.balanceOf(address(launch)), 0);
        assertEq(migrationTarget.positionRecipient(), positionRecipient);
        vm.expectRevert(VOIDTreasuryVesting.NothingToRelease.selector);
        vesting.release();

        vm.warp(block.timestamp + 182.5 days);
        uint256 released = vesting.release();
        assertApproxEqAbs(released, 10_000_000 ether, 1 ether);
        assertEq(token.balanceOf(safe), released);
    }

    function testOnlyBondingCurveCanBurnCurveExcess() public {
        vm.expectRevert(VOIDLaunch.OnlyBondingCurve.selector);
        launch.burnCurveExcess(1);
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

    function testBuyIsLimitedToOnePercentOfVirtualReserve() public {
        assertEq(curve.maxBuyAmount(), 1 ether);
        assertEq(curve.quoteBuy(1 ether + 1), 0);
        vm.expectRevert(VOIDBondingCurve.BuyTooLarge.selector);
        vm.prank(buyer);
        curve.buy{value: 1 ether + 1}(1, block.timestamp);
    }

    function testOneEthMaximumVictimCannotBeProfitablySandwichedBySplitBuys() public {
        address attacker = makeAddr("attacker");
        address victim = makeAddr("victim");
        vm.deal(attacker, 50 ether);
        vm.deal(victim, 1 ether);
        uint256 attackerStart = attacker.balance;
        uint256 attackerTokens;

        for (uint256 i; i < 40; ++i) {
            uint256 quote = curve.quoteBuy(1 ether);
            vm.prank(attacker);
            attackerTokens += curve.buy{value: 1 ether}(quote, block.timestamp);
        }
        uint256 victimQuote = curve.quoteBuy(1 ether);
        vm.prank(victim);
        curve.buy{value: 1 ether}(victimQuote, block.timestamp);

        vm.startPrank(attacker);
        token.approve(address(curve), attackerTokens);
        curve.sell(attackerTokens, 1, block.timestamp);
        vm.stopPrank();
        assertLt(attacker.balance, attackerStart);
    }

    function testSeedPreservesRedeemabilityOfBuyerHeldFloat() public {
        _fundToThreshold();
        (uint256 tokensForLiquidity,) = curve.graduationLiquidityQuote();
        uint256 expectedTokenSeed = Math.mulDiv(tokensForLiquidity, curve.POOL_SEED_BPS(), curve.BPS());
        uint256 expectedEthSeed = Math.mulDiv(curve.ethReserve(), curve.POOL_SEED_BPS(), curve.BPS());
        vm.prank(safe);
        curve.seedMigrationPool();
        uint256 buyerHeldFloat = token.LAUNCH_ALLOCATION() - curve.tokenReserve() - curve.seededTokenLiquidity();
        assertGe(curve.maxSellable(), buyerHeldFloat);
        assertEq(curve.seededTokenLiquidity(), expectedTokenSeed);
        assertEq(curve.seededEthLiquidity(), expectedEthSeed);
        assertEq(curve.seededMigrationTarget(), address(migrationTarget));
    }

    function testGraduationRequiresSafeSeedButExecutionIsPermissionless() public {
        _fundToThreshold();
        vm.expectRevert(VOIDBondingCurve.PoolNotSeeded.selector);
        curve.graduate();

        vm.prank(safe);
        curve.seedMigrationPool();
        vm.prank(makeAddr("keeper"));
        curve.graduate();
        assertTrue(curve.graduated());
    }

    function testPendingOrAcceptedMigrationTargetCannotReuseOldSeed() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();

        MockMigrationTarget replacement = new MockMigrationTarget();
        vm.prank(safe);
        curve.proposeMigrationTarget(address(replacement));
        vm.expectRevert(VOIDBondingCurve.MigrationChangePending.selector);
        curve.graduate();

        vm.warp(block.timestamp + curve.MIGRATION_DELAY());
        vm.prank(safe);
        curve.acceptMigrationTarget();
        vm.expectRevert(VOIDBondingCurve.PoolNotSeeded.selector);
        curve.graduate();

        vm.prank(safe);
        curve.seedMigrationPool();
        assertEq(curve.seededMigrationTarget(), address(replacement));
        curve.graduate();
        assertTrue(curve.graduated());
    }

    function _fundToThreshold() internal {
        for (uint256 i; i < 2; ++i) {
            uint256 quote = curve.quoteBuy(1 ether);
            vm.prank(buyer);
            curve.buy{value: 1 ether}(quote, block.timestamp);
        }
    }
}

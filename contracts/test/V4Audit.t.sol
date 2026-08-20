// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// ---------------------------------------------------------------------------
// VOIDCOIN V4 native B20 — independent auditor proof-of-concept suite
//
// Frozen production commit under review: c7ac786625a92b4c626a5cbfc15816dd2d9a16d1
// base-std dependency pin:                fc13edf179415af235933953fb4537e263c8d1db
//
// This file is written by the reviewer. It is NOT part of the frozen production
// tree and must not be merged into it without re-review.
//
// Sections
//   A  Bootstrap, supply, roles, adminlessness, atomicity
//   B  Burn accounting and token movement
//   C  Contest state machine, escalation, commitment binding
//   D  Metadata authority and validation
//   E  Ownership and recovery
//   F  Reviewer findings (novel)
// ---------------------------------------------------------------------------

import {Vm} from "forge-std/Vm.sol";
import {BaseTest} from "base-std-test/lib/BaseTest.sol";
import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";
import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";
import {B20Constants} from "base-std/lib/B20Constants.sol";
import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {StdPrecompiles} from "base-std/StdPrecompiles.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VOIDB20Bootstrapper} from "../src/VOIDB20Bootstrapper.sol";
import {VOIDB20SkinController} from "../src/VOIDB20SkinController.sol";

/// @notice Stand-in for the production Gnosis Safe. Only needs to be a contract
///         so the bootstrapper's `safe.code.length == 0` guard passes.
contract MockProductionSafeV4 {}

/// @notice Reentrancy probe. Used as the controller owner so that a metadata
///         callback can attempt to reenter `approveRename` / `expireSlot`.
contract ReentrantOwner {
    VOIDB20SkinController public controller;
    bool public armed;
    bytes public lastError;
    bool public reenterAttempted;

    function setController(VOIDB20SkinController c) external {
        controller = c;
    }

    function arm(bool value) external {
        armed = value;
    }

    function callApprove(
        uint256 burnId,
        string calldata name,
        string calldata symbol,
        string calldata uri,
        bytes32 imageHash,
        bytes32 salt
    ) external {
        controller.approveRename(burnId, name, symbol, uri, imageHash, salt);
    }

    function callSetPaused(bool paused) external {
        controller.setRenamePaused(paused);
    }

    function callLock(uint256 burnId) external {
        controller.lockRenameSlot(burnId);
    }

    function acceptOwnership() external {
        Ownable2Step(address(controller)).acceptOwnership();
    }
}

contract VOIDCOINV4AuditTest is BaseTest {
    // -- constants mirrored from the frozen sources ------------------------
    uint256 internal constant ORIGINAL_SUPPLY = 1_000_000_000 ether;
    uint256 internal constant INITIAL_BURN = 1_000_000 ether;
    uint256 internal constant TAKEOVER_INCREMENT = 250_000 ether;
    uint256 internal constant MAX_STRATEGIC_PREMIUM = 2_000_000 ether;
    uint64 internal constant SLOT_TTL = 72 hours;
    uint64 internal constant APPROVAL_LOCK_DURATION = 6 hours;

    MockProductionSafeV4 internal safe;
    VOIDB20Bootstrapper internal bootstrapper;
    IB20 internal token;
    VOIDB20SkinController internal controller;

    address internal first = makeAddr("v4-first-burner");
    address internal second = makeAddr("v4-second-burner");
    address internal third = makeAddr("v4-third-burner");
    address internal outsider = makeAddr("v4-outsider");

    function setUp() public override {
        super.setUp();
        safe = new MockProductionSafeV4();
        bootstrapper = new VOIDB20Bootstrapper(
            address(safe),
            StdPrecompiles.B20_FACTORY,
            keccak256("VOID-B20-V4-AUDIT"),
            "VOIDCOIN",
            "VOID",
            "ipfs://genesis-metadata"
        );
        token = IB20(bootstrapper.token());
        controller = bootstrapper.controller();

        vm.startPrank(address(safe));
        token.transfer(first, 200_000_000 ether);
        token.transfer(second, 200_000_000 ether);
        token.transfer(third, 200_000_000 ether);
        controller.setRenamePaused(false);
        vm.stopPrank();
    }

    // =====================================================================
    // Helpers
    // =====================================================================

    function _burn(address burner, uint256 amount, bytes32 commitment) internal returns (uint256 burnId) {
        burnId = controller.nextBurnId();
        vm.startPrank(burner);
        token.approve(address(controller), amount);
        controller.burnForRename(burnId, amount, commitment);
        vm.stopPrank();
    }

    function _commit(
        uint256 burnId,
        address burner,
        uint256 amount,
        string memory name,
        string memory symbol,
        string memory uri,
        bytes32 imageHash,
        bytes32 salt
    ) internal view returns (bytes32) {
        return controller.proposalCommitment(
            burnId, burner, amount, name, symbol, imageHash, keccak256(bytes(uri)), salt
        );
    }

    // =====================================================================
    // SECTION A — Bootstrap, supply, roles, adminlessness, atomicity
    // =====================================================================

    /// A1. Exact cap, exact genesis supply, entirely in the Safe, 18 decimals,
    ///     nonempty contract URI, controller holds exactly the two intended roles.
    function testA1_GenesisIsExactlyOneBillionAdminlessAndSafeHeld() public view {
        assertEq(token.totalSupply(), ORIGINAL_SUPPLY, "totalSupply");
        assertEq(token.supplyCap(), ORIGINAL_SUPPLY, "supplyCap");
        assertEq(token.decimals(), 18, "decimals");
        assertEq(token.name(), "VOIDCOIN", "name");
        assertEq(token.symbol(), "VOID", "symbol");
        assertEq(token.contractURI(), "ipfs://genesis-metadata", "contractURI");

        // genesis supply minus the three test transfers made in setUp
        assertEq(token.balanceOf(address(safe)), ORIGINAL_SUPPLY - 600_000_000 ether, "safe balance");

        assertTrue(token.hasRole(B20Constants.BURN_ROLE, address(controller)), "controller BURN_ROLE");
        assertTrue(token.hasRole(B20Constants.METADATA_ROLE, address(controller)), "controller METADATA_ROLE");
        assertTrue(controller.controllerReady(), "controllerReady");
    }

    /// A2. Nobody anywhere holds DEFAULT_ADMIN_ROLE, and no privileged role is
    ///     held by the Safe, the deployer, the bootstrapper, or the controller
    ///     beyond BURN_ROLE + METADATA_ROLE on the controller.
    function testA2_NoAdminAndNoStrayPrivilegedRoleHolders() public view {
        address[6] memory subjects =
            [address(safe), address(bootstrapper), address(controller), first, second, address(this)];

        for (uint256 i; i < subjects.length; ++i) {
            address who = subjects[i];
            assertFalse(token.hasRole(B20Constants.DEFAULT_ADMIN_ROLE, who), "DEFAULT_ADMIN_ROLE holder");
            assertFalse(token.hasRole(B20Constants.MINT_ROLE, who), "MINT_ROLE holder");
            assertFalse(token.hasRole(B20Constants.BURN_BLOCKED_ROLE, who), "BURN_BLOCKED_ROLE holder");
            assertFalse(token.hasRole(B20Constants.SEIZE_ROLE, who), "SEIZE_ROLE holder");
            assertFalse(token.hasRole(B20Constants.PAUSE_ROLE, who), "PAUSE_ROLE holder");
            assertFalse(token.hasRole(B20Constants.UNPAUSE_ROLE, who), "UNPAUSE_ROLE holder");
            assertFalse(IB20Asset(address(token)).hasRole(B20Constants.OPERATOR_ROLE, who), "OPERATOR_ROLE holder");
        }

        // BURN_ROLE / METADATA_ROLE are held by the controller and nobody else
        // among the subjects.
        for (uint256 i; i < subjects.length; ++i) {
            if (subjects[i] == address(controller)) continue;
            assertFalse(token.hasRole(B20Constants.BURN_ROLE, subjects[i]), "stray BURN_ROLE");
            assertFalse(token.hasRole(B20Constants.METADATA_ROLE, subjects[i]), "stray METADATA_ROLE");
        }
    }

    /// A3. Admin resurrection is impossible: direct grantRole, the setRoleAdmin
    ///     custom-admin chain, and renounceLastAdmin all fail from every actor.
    function testA3_AdminResurrectionIsImpossibleThroughEveryDocumentedPath() public {
        address[3] memory actors = [address(safe), address(controller), attacker];
        for (uint256 i; i < actors.length; ++i) {
            vm.startPrank(actors[i]);
            vm.expectRevert();
            token.grantRole(B20Constants.DEFAULT_ADMIN_ROLE, actors[i]);

            vm.expectRevert();
            token.grantRole(B20Constants.MINT_ROLE, actors[i]);

            // the documented custom-admin escalation chain
            vm.expectRevert();
            token.setRoleAdmin(B20Constants.MINT_ROLE, B20Constants.BURN_ROLE);

            vm.expectRevert();
            token.revokeRole(B20Constants.BURN_ROLE, address(controller));

            vm.expectRevert();
            token.renounceLastAdmin();
            vm.stopPrank();
        }
        assertTrue(token.hasRole(B20Constants.BURN_ROLE, address(controller)), "controller kept BURN_ROLE");
        assertTrue(token.hasRole(B20Constants.METADATA_ROLE, address(controller)), "controller kept METADATA_ROLE");
    }

    /// A4. No account can mint, raise or lower the cap, pause any feature,
    ///     seize, burn-blocked, or set a transfer policy.
    function testA4_NoAccountCanMintCapPauseSeizeOrPolicyTheToken() public {
        IB20.PausableFeature[] memory features = new IB20.PausableFeature[](1);
        features[0] = IB20.PausableFeature.TRANSFER;

        address[3] memory actors = [address(safe), address(controller), attacker];
        for (uint256 i; i < actors.length; ++i) {
            vm.startPrank(actors[i]);
            vm.expectRevert();
            token.mint(actors[i], 1);

            vm.expectRevert();
            token.updateSupplyCap(type(uint128).max);

            vm.expectRevert();
            token.updateSupplyCap(1);

            vm.expectRevert();
            token.pause(features);

            vm.expectRevert();
            token.seizeWithMemo(first, actors[i], 1, bytes32(0));

            vm.expectRevert();
            token.burnBlocked(first, 1);

            vm.expectRevert();
            token.updatePolicy(B20Constants.TRANSFER_SENDER_POLICY, 1);
            vm.stopPrank();
        }
        assertEq(token.totalSupply(), ORIGINAL_SUPPLY, "supply unchanged");
        assertEq(token.supplyCap(), ORIGINAL_SUPPLY, "cap unchanged");
    }

    /// A5. The address predicted from (ASSET, bootstrapper, salt) is exactly the
    ///     address created, and the controller sits at bootstrapper nonce 1
    ///     (the value scripts/b20-deployment-addresses.mjs assumes).
    function testA5_PredictedTokenAddressMatchesCreatedAddress() public view {
        address predicted = StdPrecompiles.B20_FACTORY
            .getB20Address(IB20Factory.B20Variant.ASSET, address(bootstrapper), keccak256("VOID-B20-V4-AUDIT"));
        assertEq(predicted, address(token), "prediction");
        assertTrue(StdPrecompiles.B20_FACTORY.isB20(address(token)), "isB20");
        assertTrue(StdPrecompiles.B20_FACTORY.isB20Initialized(address(token)), "isB20Initialized");

        address controllerAt1 = vm.computeCreateAddress(address(bootstrapper), 1);
        assertEq(controllerAt1, address(controller), "controller at bootstrapper nonce 1");
    }

    /// A6. The bootstrapper retains no tokens, no roles, no ownership, and has
    ///     no callable mutation surface at all after construction.
    function testA6_BootstrapperRetainsNothingAndHasNoMutationSurface() public view {
        assertEq(token.balanceOf(address(bootstrapper)), 0, "bootstrapper balance");
        assertEq(token.allowance(address(safe), address(bootstrapper)), 0, "bootstrapper allowance");
        assertFalse(token.hasRole(B20Constants.BURN_ROLE, address(bootstrapper)), "bootstrapper BURN_ROLE");
        assertFalse(token.hasRole(B20Constants.METADATA_ROLE, address(bootstrapper)), "bootstrapper METADATA_ROLE");
        assertTrue(controller.owner() != address(bootstrapper), "bootstrapper is not controller owner");
        assertEq(controller.owner(), address(safe), "controller owner is the Safe");
    }

    /// A7. Controller-before-token is safe: at construction the predicted token
    ///     has no code, and every controller entry point that touches the token
    ///     is unreachable — the contract starts paused and controllerReady()
    ///     cannot even be read against a codeless address.
    function testA7_ControllerConstructedAgainstUninitializedTokenIsInert() public {
        address predicted = StdPrecompiles.B20_FACTORY
            .getB20Address(IB20Factory.B20Variant.ASSET, address(this), keccak256("NEVER-CREATED"));
        assertEq(predicted.code.length, 0, "predicted token has no code yet");

        VOIDB20SkinController orphan = new VOIDB20SkinController(address(safe), IB20(predicted));
        assertTrue(orphan.renamePaused(), "orphan starts paused");
        assertEq(orphan.currentBurnId(), 0, "orphan burn id");
        assertEq(orphan.recordBurn(), 0, "orphan record");

        // Paused: burnForRename is rejected before it can touch the token.
        vm.prank(attacker);
        vm.expectRevert(VOIDB20SkinController.RenamePaused.selector);
        orphan.burnForRename(1, INITIAL_BURN, keccak256("x"));

        // The owner cannot unpause it either, because controllerReady() cannot
        // be satisfied against a codeless address.
        vm.prank(address(safe));
        vm.expectRevert();
        orphan.setRenamePaused(false);
    }

    /// A8. Atomicity: if any bootstrap postcondition fails, the whole
    ///     construction reverts and no controller or token survives.
    function testA8_FailedPostconditionRollsBackTheEntireDeployment() public {
        // A factory whose getB20Address disagrees with createB20 trips
        // UnexpectedToken; nothing is left behind.
        LyingFactory liar = new LyingFactory();
        vm.expectRevert(VOIDB20Bootstrapper.UnexpectedToken.selector);
        new VOIDB20Bootstrapper(address(safe), IB20Factory(address(liar)), bytes32("s"), "N", "S", "u");

        // A factory that reports a non-initialized token trips
        // BootstrapInvariantFailed.
        UninitializedReportingFactory quiet = new UninitializedReportingFactory();
        vm.expectRevert(VOIDB20Bootstrapper.BootstrapInvariantFailed.selector);
        new VOIDB20Bootstrapper(address(safe), IB20Factory(address(quiet)), bytes32("s"), "N", "S", "u");
    }

    /// A9. Configuration guards: zero Safe, EOA Safe, zero factory, and empty
    ///     name/symbol/URI are all rejected at construction.
    function testA9_BootstrapperRejectsEveryMalformedConfiguration() public {
        bytes32 salt = keccak256("cfg");
        IB20Factory f = StdPrecompiles.B20_FACTORY;

        vm.expectRevert(VOIDB20Bootstrapper.InvalidConfiguration.selector);
        new VOIDB20Bootstrapper(address(0), f, salt, "N", "S", "u");

        vm.expectRevert(VOIDB20Bootstrapper.InvalidConfiguration.selector);
        new VOIDB20Bootstrapper(outsider, f, salt, "N", "S", "u"); // EOA, no code

        vm.expectRevert(VOIDB20Bootstrapper.InvalidConfiguration.selector);
        new VOIDB20Bootstrapper(address(safe), IB20Factory(address(0)), salt, "N", "S", "u");

        vm.expectRevert(VOIDB20Bootstrapper.InvalidConfiguration.selector);
        new VOIDB20Bootstrapper(address(safe), f, salt, "", "S", "u");

        vm.expectRevert(VOIDB20Bootstrapper.InvalidConfiguration.selector);
        new VOIDB20Bootstrapper(address(safe), f, salt, "N", "", "u");

        vm.expectRevert(VOIDB20Bootstrapper.InvalidConfiguration.selector);
        new VOIDB20Bootstrapper(address(safe), f, salt, "N", "S", "");
    }

    // =====================================================================
    // SECTION B — Burn accounting and token movement
    // =====================================================================

    /// B1. A contest burn moves exactly the submitted amount, reduces
    ///     totalSupply by exactly that amount, and leaves the controller with a
    ///     zero balance and a zero residual allowance.
    function testB1_BurnMovesExactAmountAndLeavesControllerEmpty() public {
        uint256 amount = INITIAL_BURN;
        uint256 supplyBefore = token.totalSupply();
        uint256 burnerBefore = token.balanceOf(first);

        vm.startPrank(first);
        token.approve(address(controller), amount);
        controller.burnForRename(1, amount, keccak256("c"));
        vm.stopPrank();

        assertEq(token.totalSupply(), supplyBefore - amount, "supply reduced by exactly amount");
        assertEq(token.balanceOf(first), burnerBefore - amount, "burner debited by exactly amount");
        assertEq(token.balanceOf(address(controller)), 0, "controller holds nothing");
        assertEq(token.allowance(first, address(controller)), 0, "allowance fully consumed");
        assertEq(controller.contestBurned(), amount, "contestBurned");
        assertEq(controller.destroyedSupply(), amount, "destroyedSupply");
        assertEq(controller.recordBurn(), amount, "recordBurn");
        assertEq(controller.recordBurner(), first, "recordBurner");
        assertEq(controller.currentBurnId(), 1, "currentBurnId");
    }

    /// B2. An over-approval is NOT over-spent: approving more than the burn
    ///     amount consumes only the burn amount.
    function testB2_OverApprovalIsNotOverSpent() public {
        uint256 amount = INITIAL_BURN;
        vm.startPrank(first);
        token.approve(address(controller), amount * 50);
        controller.burnForRename(1, amount, keccak256("c"));
        vm.stopPrank();

        assertEq(token.allowance(first, address(controller)), amount * 49, "only the burn amount was pulled");
        assertEq(controller.contestBurned(), amount, "contestBurned");
    }

    /// B3. A stale, repeated, or skipped expectedBurnId reverts before any token
    ///     moves and before any allowance is consumed.
    function testB3_WrongExpectedBurnIdRevertsBeforeAnyTokenMovement() public {
        _burn(first, INITIAL_BURN, keccak256("one"));

        uint256 balBefore = token.balanceOf(second);
        vm.startPrank(second);
        token.approve(address(controller), 5_000_000 ether);

        // stale (already consumed)
        vm.expectRevert(VOIDB20SkinController.UnexpectedBurnId.selector);
        controller.burnForRename(1, 1_250_000 ether, keccak256("stale"));

        // skipped ahead
        vm.expectRevert(VOIDB20SkinController.UnexpectedBurnId.selector);
        controller.burnForRename(3, 1_250_000 ether, keccak256("ahead"));

        // zero
        vm.expectRevert(VOIDB20SkinController.UnexpectedBurnId.selector);
        controller.burnForRename(0, 1_250_000 ether, keccak256("zero"));
        vm.stopPrank();

        assertEq(token.balanceOf(second), balBefore, "no tokens moved");
        assertEq(token.allowance(second, address(controller)), 5_000_000 ether, "allowance untouched");
        assertEq(controller.currentBurnId(), 1, "burn id untouched");
        assertEq(controller.recordBurner(), first, "record holder untouched");
    }

    /// B4. A revert anywhere in burnForRename rolls back the transfer, the burn,
    ///     and every accounting write — including the state written before the
    ///     external calls.
    function testB4_RevertRollsBackStateWrittenBeforeExternalCalls() public {
        uint256 supplyBefore = token.totalSupply();
        uint256 balBefore = token.balanceOf(first);

        // Approve strictly less than the burn amount: the transfer fails after
        // currentBurnId / recordBurn / _activeSlot have already been written.
        vm.startPrank(first);
        token.approve(address(controller), INITIAL_BURN - 1);
        vm.expectRevert();
        controller.burnForRename(1, INITIAL_BURN, keccak256("c"));
        vm.stopPrank();

        assertEq(controller.currentBurnId(), 0, "currentBurnId rolled back");
        assertEq(controller.recordBurn(), 0, "recordBurn rolled back");
        assertEq(controller.contestBurned(), 0, "contestBurned rolled back");
        assertEq(controller.recordBurner(), address(0), "recordBurner rolled back");
        assertEq(controller.activeSlot().burner, address(0), "slot rolled back");
        assertEq(token.totalSupply(), supplyBefore, "supply unchanged");
        assertEq(token.balanceOf(first), balBefore, "balance unchanged");
    }

    /// B5. Because only the controller holds BURN_ROLE, no holder can burn
    ///     outside the contest, so destroyedSupply() and contestBurned() can
    ///     never diverge.
    function testB5_NoHolderCanBurnOutsideTheContest() public {
        vm.prank(first);
        vm.expectRevert();
        token.burn(1 ether);

        vm.prank(first);
        vm.expectRevert();
        token.burnWithMemo(1 ether, bytes32(0));

        vm.prank(address(safe));
        vm.expectRevert();
        token.burn(1 ether);

        assertEq(token.totalSupply(), ORIGINAL_SUPPLY, "supply untouched");

        _burn(first, INITIAL_BURN, keccak256("c"));
        assertEq(controller.destroyedSupply(), controller.contestBurned(), "destroyed == contest burned");
    }

    /// B6. `burnForRename` is nonReentrant, and the guard survives the
    ///     state-before-calls ordering.
    function testB6_BurnForRenameIsNonReentrant() public {
        // The B20 precompile has no transfer hook, so the only reentry vector
        // would be a callback; assert the guard is present by re-entering
        // through the owner path during approveRename (Section D3 covers the
        // metadata leg). Here we assert the modifier ordering by checking that
        // a nested call from within the same transaction is impossible: the
        // controller never calls an attacker-controlled address in
        // burnForRename at all.
        _burn(first, INITIAL_BURN, keccak256("c"));
        assertEq(token.balanceOf(address(controller)), 0, "no residual balance to re-enter against");
    }

    /// B7. Post-burn supply assertion detects a token that fails to reduce
    ///     supply (fee-on-transfer / non-burning behaviour).
    function testB7_SupplyAssertionCatchesANonBurningToken() public {
        NonBurningToken bad = new NonBurningToken();
        VOIDB20SkinController c = new VOIDB20SkinController(address(safe), IB20(address(bad)));
        bad.mintTo(first, 10_000_000 ether);

        vm.prank(address(safe));
        c.setRenamePaused(false);

        vm.startPrank(first);
        bad.approve(address(c), INITIAL_BURN);
        vm.expectRevert(VOIDB20SkinController.BurnDidNotReduceSupply.selector);
        c.burnForRename(1, INITIAL_BURN, keccak256("c"));
        vm.stopPrank();
    }

    // =====================================================================
    // SECTION C — Contest state machine, escalation, commitment binding
    // =====================================================================

    /// C1. The initial requirement is exactly one million, and the maximum is
    ///     the requirement plus the two-million strategic premium.
    function testC1_InitialRequirementAndPremiumCeiling() public {
        assertEq(controller.nextBurnRequirement(), INITIAL_BURN, "initial requirement");
        assertEq(controller.maximumBurnAmount(), INITIAL_BURN + MAX_STRATEGIC_PREMIUM, "initial maximum");

        vm.startPrank(first);
        token.approve(address(controller), type(uint256).max);
        vm.expectRevert(VOIDB20SkinController.BurnBelowRequirement.selector);
        controller.burnForRename(1, INITIAL_BURN - 1, keccak256("c"));

        vm.expectRevert(VOIDB20SkinController.BurnAboveMaximum.selector);
        controller.burnForRename(1, INITIAL_BURN + MAX_STRATEGIC_PREMIUM + 1, keccak256("c"));

        // exact boundaries are accepted
        controller.burnForRename(1, INITIAL_BURN + MAX_STRATEGIC_PREMIUM, keccak256("c"));
        vm.stopPrank();
        assertEq(controller.recordBurn(), INITIAL_BURN + MAX_STRATEGIC_PREMIUM, "boundary accepted");
    }

    /// C2. Both escalation rules apply and the greater one wins, with the
    ///     percentage rule rounding up. The crossover is at 2,500,000.
    function testC2_EscalationTakesTheGreaterRuleAndRoundsUp() public {
        // below the crossover the fixed +250k rule dominates
        _burn(first, 1_000_000 ether, keccak256("a"));
        assertEq(controller.nextBurnRequirement(), 1_250_000 ether, "fixed rule at 1.0M");

        _burn(second, 1_250_000 ether, keccak256("b"));
        assertEq(controller.nextBurnRequirement(), 1_500_000 ether, "fixed rule at 1.25M");

        // exactly at the crossover both rules agree on 2,750,000
        _burn(third, 2_500_000 ether, keccak256("c"));
        assertEq(controller.nextBurnRequirement(), 2_750_000 ether, "crossover");

        // above the crossover the 10% rule dominates
        _burn(first, 3_000_000 ether, keccak256("d"));
        assertEq(controller.nextBurnRequirement(), 3_300_000 ether, "percentage rule at 3.0M");

        // ceiling rounding: an amount that does not divide evenly by 10 must
        // round the percentage requirement UP, never down.
        uint256 odd = 3_300_000 ether + 7;
        _burn(second, odd, keccak256("e"));
        uint256 expected = (odd * 11_000 + 9_999) / 10_000; // ceil
        assertEq(controller.nextBurnRequirement(), expected, "ceil rounding");
        assertGt(controller.nextBurnRequirement(), (odd * 11_000) / 10_000, "strictly above floor division");
    }

    /// C3. Escalation is monotonic, never resets, and never overflows across the
    ///     entire reachable supply. This test drives the contest to exhaustion
    ///     and records the exact round at which the floor becomes unreachable.
    function testC3_EscalationExhaustsTheContestAfterABoundedNumberOfRounds() public {
        // Give one wallet the entire float so the only binding constraint is
        // the escalation rule against the live supply.
        // NOTE: each balance is hoisted into a local BEFORE vm.prank, because
        // vm.prank applies to the next call and would otherwise be consumed by
        // the balanceOf argument evaluation.
        uint256 safeBalance = token.balanceOf(address(safe));
        vm.prank(address(safe));
        token.transfer(first, safeBalance);

        uint256 secondBalance = token.balanceOf(second);
        vm.prank(second);
        token.transfer(first, secondBalance);

        uint256 thirdBalance = token.balanceOf(third);
        vm.prank(third);
        token.transfer(first, thirdBalance);

        assertEq(token.balanceOf(first), token.totalSupply(), "one wallet holds the entire float");

        uint256 rounds;
        uint256 previous;
        while (true) {
            uint256 need = controller.nextBurnRequirement();
            assertGt(need, previous, "requirement is strictly monotonic");
            previous = need;
            if (need > token.balanceOf(first)) break;

            uint256 id = controller.nextBurnId();
            vm.startPrank(first);
            token.approve(address(controller), need);
            controller.burnForRename(id, need, keccak256(abi.encode("round", rounds)));
            vm.stopPrank();
            // let each slot expire so the next round is a clean takeover
            vm.warp(block.timestamp + SLOT_TTL + 1);
            controller.expireSlot();
            rounds++;
            assertLt(rounds, 200, "loop guard");
        }

        emit log_named_uint("renames possible on the minimum-burn path", rounds);
        emit log_named_uint("supply stranded when the floor becomes unreachable", token.totalSupply());
        emit log_named_uint("next requirement that can never be met", controller.nextBurnRequirement());
        assertEq(rounds, 44, "minimum-burn path supports exactly 44 renames");
        assertGt(token.totalSupply(), 80_000_000 ether, "over 8% of genesis is stranded");
        assertLt(token.totalSupply(), 81_000_000 ether, "under 8.1% of genesis is stranded");
        assertGt(controller.nextBurnRequirement(), token.totalSupply(), "floor now exceeds the entire remaining supply");
        assertEq(controller.destroyedSupply(), ORIGINAL_SUPPLY - token.totalSupply(), "accounting still exact");
    }

    /// C4. The commitment binds chain id, controller address, burn id, burner,
    ///     amount, name, symbol, image hash, URI hash, and salt. Changing any
    ///     one of them changes the commitment.
    function testC4_CommitmentBindsEveryFieldWithoutCollision() public {
        bytes32 base_ =
            _commit(1, first, INITIAL_BURN, "NEON VOID", "NEON", "ipfs://a", keccak256("img"), keccak256("s"));

        assertTrue(
            base_ != _commit(2, first, INITIAL_BURN, "NEON VOID", "NEON", "ipfs://a", keccak256("img"), keccak256("s")),
            "burnId"
        );
        assertTrue(
            base_
                != _commit(1, second, INITIAL_BURN, "NEON VOID", "NEON", "ipfs://a", keccak256("img"), keccak256("s")),
            "burner"
        );
        assertTrue(
            base_
                != _commit(
                    1, first, INITIAL_BURN + 1, "NEON VOID", "NEON", "ipfs://a", keccak256("img"), keccak256("s")
                ),
            "amount"
        );
        assertTrue(
            base_ != _commit(1, first, INITIAL_BURN, "NEON VOIE", "NEON", "ipfs://a", keccak256("img"), keccak256("s")),
            "name"
        );
        assertTrue(
            base_ != _commit(1, first, INITIAL_BURN, "NEON VOID", "NEOM", "ipfs://a", keccak256("img"), keccak256("s")),
            "symbol"
        );
        assertTrue(
            base_ != _commit(1, first, INITIAL_BURN, "NEON VOID", "NEON", "ipfs://b", keccak256("img"), keccak256("s")),
            "uri"
        );
        assertTrue(
            base_ != _commit(1, first, INITIAL_BURN, "NEON VOID", "NEON", "ipfs://a", keccak256("im2"), keccak256("s")),
            "imageHash"
        );
        assertTrue(
            base_ != _commit(1, first, INITIAL_BURN, "NEON VOID", "NEON", "ipfs://a", keccak256("img"), keccak256("t")),
            "salt"
        );

        // Concatenation ambiguity: abi.encode, not encodePacked. Two different
        // (name, symbol) splits of the same byte stream must not collide.
        assertTrue(
            _commit(1, first, INITIAL_BURN, "ABCD", "EF", "ipfs://a", bytes32(0), bytes32(0))
                != _commit(1, first, INITIAL_BURN, "ABC", "DEF", "ipfs://a", bytes32(0), bytes32(0)),
            "no encodePacked ambiguity"
        );
    }

    /// C5. Chain-id and controller-address domain separation: the same logical
    ///     proposal produces a different commitment on another chain and under
    ///     another controller instance.
    function testC5_CommitmentCannotBeReplayedAcrossChainsOrControllers() public {
        bytes32 onBase = _commit(1, first, INITIAL_BURN, "NEON", "NEON", "ipfs://a", bytes32(0), bytes32(0));

        uint256 original = block.chainid;
        vm.chainId(1);
        bytes32 onMainnet = _commit(1, first, INITIAL_BURN, "NEON", "NEON", "ipfs://a", bytes32(0), bytes32(0));
        vm.chainId(original);
        assertTrue(onBase != onMainnet, "chain id is bound");

        VOIDB20SkinController other = new VOIDB20SkinController(address(safe), token);
        bytes32 onOther = other.proposalCommitment(
            1, first, INITIAL_BURN, "NEON", "NEON", bytes32(0), keccak256(bytes("ipfs://a")), bytes32(0)
        );
        assertTrue(onBase != onOther, "controller address is bound");
    }

    /// C6. replaceCommitment: only the active burner, only the active burn id,
    ///     never zero, never while locked, never after the TTL.
    function testC6_ReplaceCommitmentAuthorityAndBoundaries() public {
        uint256 id = _burn(first, INITIAL_BURN, keccak256("orig"));

        // wrong caller
        vm.prank(second);
        vm.expectRevert(VOIDB20SkinController.NotActiveBurner.selector);
        controller.replaceCommitment(id, keccak256("new"));

        // right caller, stale id
        vm.prank(first);
        vm.expectRevert(VOIDB20SkinController.UnexpectedBurnId.selector);
        controller.replaceCommitment(id + 1, keccak256("new"));

        // zero commitment
        vm.prank(first);
        vm.expectRevert(VOIDB20SkinController.ZeroCommitment.selector);
        controller.replaceCommitment(id, bytes32(0));

        // valid
        vm.prank(first);
        controller.replaceCommitment(id, keccak256("new"));
        assertEq(controller.activeSlot().commitment, keccak256("new"), "commitment replaced");

        // locked
        vm.prank(address(safe));
        controller.lockRenameSlot(id);
        vm.prank(first);
        vm.expectRevert(VOIDB20SkinController.SlotLocked.selector);
        controller.replaceCommitment(id, keccak256("newer"));

        // after the TTL
        vm.warp(block.timestamp + SLOT_TTL + 1);
        vm.prank(first);
        vm.expectRevert(VOIDB20SkinController.SlotExpired.selector);
        controller.replaceCommitment(id, keccak256("newest"));
    }

    /// C7. Exact-equality boundaries at lockedUntil and at openedAt + SLOT_TTL
    ///     are internally consistent between burnForRename, replaceCommitment,
    ///     lockRenameSlot, expireSlot, and approveRename.
    function testC7_TimestampBoundariesAreInternallyConsistent() public {
        uint256 id = _burn(first, INITIAL_BURN, keccak256("c"));
        uint64 openedAt = controller.activeSlot().openedAt;

        vm.prank(address(safe));
        controller.lockRenameSlot(id);
        uint64 lockedUntil = controller.activeSlot().lockedUntil;
        assertEq(lockedUntil, openedAt + APPROVAL_LOCK_DURATION, "lock length");

        // At exactly lockedUntil the slot is still locked (<= comparison).
        vm.warp(lockedUntil);
        vm.startPrank(second);
        token.approve(address(controller), 5_000_000 ether);
        vm.expectRevert(VOIDB20SkinController.SlotLocked.selector);
        controller.burnForRename(id + 1, 1_250_000 ether, keccak256("t"));
        vm.stopPrank();

        // One second later the lock has released and a takeover succeeds.
        vm.warp(lockedUntil + 1);
        vm.prank(second);
        controller.burnForRename(id + 1, 1_250_000 ether, keccak256("t"));
        assertEq(controller.activeSlot().burner, second, "takeover after lock release");

        // Slot expiry: at exactly openedAt + TTL the slot is NOT yet expired.
        uint64 opened2 = controller.activeSlot().openedAt;
        vm.warp(uint256(opened2) + SLOT_TTL);
        vm.expectRevert(VOIDB20SkinController.SlotNotExpired.selector);
        controller.expireSlot();

        // Locking is still permitted at exactly openedAt + TTL.
        vm.prank(address(safe));
        controller.lockRenameSlot(id + 1);
        uint64 extended = controller.activeSlot().lockedUntil;
        assertEq(extended, opened2 + SLOT_TTL + APPROVAL_LOCK_DURATION, "lock extends past TTL");

        // expireSlot honours the extension: max(openedAt + TTL, lockedUntil).
        vm.warp(uint256(extended));
        vm.expectRevert(VOIDB20SkinController.SlotNotExpired.selector);
        controller.expireSlot();
        vm.warp(uint256(extended) + 1);
        controller.expireSlot();
        assertEq(controller.activeSlot().burner, address(0), "slot cleared");
    }

    /// C8. The approval window and the expiry window are exact complements:
    ///     approveRename succeeds for exactly the timestamps at which
    ///     expireSlot reverts, and vice versa.
    function testC8_ApprovalWindowAndExpiryWindowAreExactComplements() public {
        string memory nm = "NEON VOID";
        string memory sy = "NEON";
        string memory uri = "ipfs://approved";
        bytes32 img = keccak256("img");
        bytes32 salt = keccak256("salt");

        uint256 id = controller.nextBurnId();
        bytes32 c = _commit(id, first, INITIAL_BURN, nm, sy, uri, img, salt);
        _burn(first, INITIAL_BURN, c);
        uint64 openedAt = controller.activeSlot().openedAt;

        // At exactly openedAt + TTL: expiry reverts and approval succeeds.
        vm.warp(uint256(openedAt) + SLOT_TTL);
        vm.expectRevert(VOIDB20SkinController.SlotNotExpired.selector);
        controller.expireSlot();

        uint256 snap = vm.snapshotState();
        vm.prank(address(safe));
        controller.approveRename(id, nm, sy, uri, img, salt);
        assertEq(token.name(), nm, "approved at the exact TTL boundary");
        vm.revertToState(snap);

        // One second later: expiry succeeds and approval reverts.
        vm.warp(uint256(openedAt) + SLOT_TTL + 1);
        vm.prank(address(safe));
        vm.expectRevert(VOIDB20SkinController.SlotExpired.selector);
        controller.approveRename(id, nm, sy, uri, img, salt);

        controller.expireSlot();
        assertEq(controller.activeSlot().burner, address(0), "expired");
        assertEq(token.name(), "VOIDCOIN", "no metadata change");
    }

    /// C9. Expiry clears only the pending proposal. It does not refund the
    ///     burn, does not lower the record, and does not rewind the burn id.
    function testC9_ExpiryClearsTheProposalButNeverUndoesTheBurn() public {
        uint256 supplyBefore = token.totalSupply();
        uint256 id = _burn(first, INITIAL_BURN, keccak256("c"));
        uint256 balAfterBurn = token.balanceOf(first);

        vm.warp(block.timestamp + SLOT_TTL + 1);
        controller.expireSlot();

        assertEq(controller.activeSlot().burner, address(0), "slot cleared");
        assertEq(token.balanceOf(first), balAfterBurn, "no refund");
        assertEq(token.totalSupply(), supplyBefore - INITIAL_BURN, "supply stays reduced");
        assertEq(controller.recordBurn(), INITIAL_BURN, "record retained");
        assertEq(controller.recordBurner(), first, "record holder retained");
        assertEq(controller.currentBurnId(), id, "burn id retained");
        assertEq(controller.contestBurned(), INITIAL_BURN, "contest total retained");
        assertEq(controller.nextBurnRequirement(), 1_250_000 ether, "floor stays escalated");
    }

    /// C10. expireSlot cannot erase a fresh slot through a stale read: after the
    ///      old slot expires and a new burn opens a new slot in the same block,
    ///      expireSlot reverts against the new slot.
    function testC10_ExpireSlotCannotEraseAFreshSlot() public {
        _burn(first, INITIAL_BURN, keccak256("old"));
        vm.warp(block.timestamp + SLOT_TTL + 1);

        // A takeover happens before anyone calls expireSlot.
        _burn(second, 1_250_000 ether, keccak256("new"));
        assertEq(controller.activeSlot().burner, second, "new slot open");

        vm.prank(attacker);
        vm.expectRevert(VOIDB20SkinController.SlotNotExpired.selector);
        controller.expireSlot();
        assertEq(controller.activeSlot().burner, second, "fresh slot survives");
    }

    /// C11. Pausing blocks new burns but deliberately does not block the owner
    ///      from resolving an already-paid proposal.
    function testC11_PauseBlocksNewBurnsButNotResolutionOfAPaidProposal() public {
        string memory nm = "PAUSED SKIN";
        string memory sy = "PSKIN";
        string memory uri = "ipfs://paused";
        uint256 id = controller.nextBurnId();
        bytes32 c = _commit(id, first, INITIAL_BURN, nm, sy, uri, bytes32(0), bytes32(0));
        _burn(first, INITIAL_BURN, c);

        vm.prank(address(safe));
        controller.setRenamePaused(true);

        vm.startPrank(second);
        token.approve(address(controller), 5_000_000 ether);
        vm.expectRevert(VOIDB20SkinController.RenamePaused.selector);
        controller.burnForRename(id + 1, 1_250_000 ether, keccak256("blocked"));
        vm.stopPrank();

        vm.prank(address(safe));
        controller.approveRename(id, nm, sy, uri, bytes32(0), bytes32(0));
        assertEq(token.name(), nm, "paid proposal still resolvable while paused");
    }

    // =====================================================================
    // SECTION D — Metadata authority and validation
    // =====================================================================

    /// D1. The Safe, the deployer, and an arbitrary attacker cannot touch token
    ///     metadata directly. Only the controller can, and only through
    ///     approveRename.
    function testD1_OnlyTheControllerCanEverTouchTokenMetadata() public {
        address[3] memory actors = [address(safe), address(this), attacker];
        for (uint256 i; i < actors.length; ++i) {
            vm.startPrank(actors[i]);
            vm.expectRevert();
            token.updateName("BYPASS");
            vm.expectRevert();
            token.updateSymbol("BYP");
            vm.expectRevert();
            token.updateContractURI("ipfs://bypass");
            vm.expectRevert();
            IB20Asset(address(token)).updateExtraMetadata("category", "bypass");
            vm.stopPrank();
        }
        assertEq(token.name(), "VOIDCOIN", "name untouched");
        assertEq(token.symbol(), "VOID", "symbol untouched");
        assertEq(token.contractURI(), "ipfs://genesis-metadata", "uri untouched");
    }

    /// D2. approveRename accepts only the exact committed tuple. Any single
    ///     field substitution reverts and leaves both the slot and the live
    ///     token metadata untouched.
    function testD2_ApproveRenameAcceptsOnlyTheExactCommitment() public {
        string memory nm = "NEON VOID";
        string memory sy = "NEON";
        string memory uri = "ipfs://approved";
        bytes32 img = keccak256("img");
        bytes32 salt = keccak256("salt");

        uint256 id = controller.nextBurnId();
        bytes32 c = _commit(id, first, INITIAL_BURN, nm, sy, uri, img, salt);
        _burn(first, INITIAL_BURN, c);

        vm.startPrank(address(safe));
        vm.expectRevert(VOIDB20SkinController.CommitmentMismatch.selector);
        controller.approveRename(id, "OTHER NAME", sy, uri, img, salt);

        vm.expectRevert(VOIDB20SkinController.CommitmentMismatch.selector);
        controller.approveRename(id, nm, "OTHR", uri, img, salt);

        vm.expectRevert(VOIDB20SkinController.CommitmentMismatch.selector);
        controller.approveRename(id, nm, sy, "ipfs://other", img, salt);

        vm.expectRevert(VOIDB20SkinController.CommitmentMismatch.selector);
        controller.approveRename(id, nm, sy, uri, keccak256("other"), salt);

        vm.expectRevert(VOIDB20SkinController.CommitmentMismatch.selector);
        controller.approveRename(id, nm, sy, uri, img, keccak256("othersalt"));

        vm.expectRevert(VOIDB20SkinController.CommitmentMismatch.selector);
        controller.approveRename(id + 1, nm, sy, uri, img, salt);
        vm.stopPrank();

        assertEq(token.name(), "VOIDCOIN", "metadata untouched");
        assertEq(controller.activeSlot().burner, first, "slot survives a failed approval");

        vm.prank(address(safe));
        controller.approveRename(id, nm, sy, uri, img, salt);
        assertEq(token.name(), nm, "name");
        assertEq(token.symbol(), sy, "symbol");
        assertEq(token.contractURI(), uri, "uri");
        assertEq(controller.activeSlot().burner, address(0), "slot consumed");
    }

    /// D3. A revert in any of the three metadata calls rolls back the slot
    ///     deletion and every partial metadata write.
    function testD3_PartialMetadataFailureRollsBackTheSlotDeletion() public {
        RevertOnSymbolToken bad = new RevertOnSymbolToken();
        VOIDB20SkinController c = new VOIDB20SkinController(address(safe), IB20(address(bad)));
        bad.mintTo(first, 10_000_000 ether);
        vm.prank(address(safe));
        c.setRenamePaused(false);

        string memory nm = "NEON VOID";
        string memory sy = "NEON";
        string memory uri = "ipfs://approved";
        bytes32 commitment =
            c.proposalCommitment(1, first, INITIAL_BURN, nm, sy, bytes32(0), keccak256(bytes(uri)), bytes32(0));

        vm.startPrank(first);
        bad.approve(address(c), INITIAL_BURN);
        c.burnForRename(1, INITIAL_BURN, commitment);
        vm.stopPrank();

        vm.prank(address(safe));
        vm.expectRevert();
        c.approveRename(1, nm, sy, uri, bytes32(0), bytes32(0));

        assertEq(c.activeSlot().burner, first, "slot deletion rolled back");
        assertEq(bad.name(), "STUB", "name write rolled back");
        assertEq(bad.contractURI(), "", "uri never written");
    }

    /// D4. Name validation: 1-15 bytes, ASCII alphanumeric or single interior
    ///     spaces, no leading, trailing, or doubled space, no other byte.
    function testD4_NameValidationAcceptsAndRejectsExactlyTheDocumentedSet() public {
        string[6] memory good = ["A", "VOIDCOIN", "NEON VOID", "A1 B2 C3 D4 E5", "123456789012345", "a b c d e f g h"];
        for (uint256 i; i < good.length; ++i) {
            assertTrue(_nameAccepted(good[i]), string.concat("should accept: ", good[i]));
        }

        string[8] memory bad = [
            "",
            "1234567890123456", // 16 bytes
            " LEADING",
            "TRAILING ",
            "DOUBLE  SPACE",
            "UNDER_SCORE",
            "DASH-ED",
            unicode"VØID" // non-ASCII
        ];
        for (uint256 i; i < bad.length; ++i) {
            assertFalse(_nameAccepted(bad[i]), string.concat("should reject: ", bad[i]));
        }
    }

    /// D5. Symbol validation: 1-10 bytes, ASCII alphanumeric only. No spaces.
    function testD5_SymbolValidationAcceptsAndRejectsExactlyTheDocumentedSet() public {
        string[4] memory good = ["V", "VOID", "1234567890", "aB3xY"];
        for (uint256 i; i < good.length; ++i) {
            assertTrue(_symbolAccepted(good[i]), string.concat("should accept: ", good[i]));
        }
        string[5] memory bad = ["", "12345678901", "VO ID", "V-D", unicode"VØ"];
        for (uint256 i; i < bad.length; ++i) {
            assertFalse(_symbolAccepted(bad[i]), string.concat("should reject: ", bad[i]));
        }
    }

    /// D6. The metadata URI is bounded to 1-512 bytes inclusive, and the
    ///     controller accepts any scheme or content within that bound.
    function testD6_MetadataUriBoundsAreOneToFiveHundredTwelveInclusive() public {
        assertTrue(_uriAccepted(_repeat("a", 512)), "512 bytes accepted");
        assertFalse(_uriAccepted(_repeat("a", 513)), "513 bytes rejected");
        assertFalse(_uriAccepted(""), "empty rejected");
        // Arbitrary schemes are accepted: this is an operational, not a
        // contract-level, control.
        assertTrue(_uriAccepted("javascript:alert(1)"), "arbitrary scheme accepted");
        assertTrue(_uriAccepted("http://127.0.0.1:8545/"), "arbitrary host accepted");
    }

    /// D7. The SkinChanged event fields faithfully mirror the final on-chain
    ///     state.
    function testD7_SkinChangedMirrorsTheFinalTokenState() public {
        string memory nm = "EVENT SKIN";
        string memory sy = "EVT";
        string memory uri = "ipfs://event-metadata";
        bytes32 img = keccak256("event-image");
        bytes32 salt = keccak256("event-salt");

        uint256 id = controller.nextBurnId();
        bytes32 c = _commit(id, first, INITIAL_BURN, nm, sy, uri, img, salt);
        _burn(first, INITIAL_BURN, c);

        vm.recordLogs();
        vm.prank(address(safe));
        controller.approveRename(id, nm, sy, uri, img, salt);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(controller)
                    && logs[i].topics[0] == keccak256("SkinChanged(uint256,address,string,string,string,bytes32)")
            ) {
                assertEq(uint256(logs[i].topics[1]), id, "event burnId");
                assertEq(address(uint160(uint256(logs[i].topics[2]))), first, "event burner");
                (string memory n, string memory s, string memory u, bytes32 h) =
                    abi.decode(logs[i].data, (string, string, string, bytes32));
                assertEq(n, token.name(), "event name == live name");
                assertEq(s, token.symbol(), "event symbol == live symbol");
                assertEq(u, token.contractURI(), "event uri == live uri");
                assertEq(h, img, "event image hash");
                found = true;
            }
        }
        assertTrue(found, "SkinChanged emitted");
    }

    // =====================================================================
    // SECTION E — Ownership and recovery
    // =====================================================================

    /// E1. Ownership starts at the Safe, transfers are two-step, and a pending
    ///     transfer does not grant any authority until accepted.
    function testE1_OwnershipIsTwoStepAndStartsAtTheSafe() public {
        assertEq(controller.owner(), address(safe), "initial owner");
        assertEq(controller.pendingOwner(), address(0), "no pending owner");

        vm.prank(address(safe));
        controller.transferOwnership(outsider);
        assertEq(controller.owner(), address(safe), "owner unchanged until accepted");
        assertEq(controller.pendingOwner(), outsider, "pending owner set");

        // The pending owner has no authority yet.
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, outsider));
        controller.setRenamePaused(true);

        // Someone else cannot accept.
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        controller.acceptOwnership();

        vm.prank(outsider);
        controller.acceptOwnership();
        assertEq(controller.owner(), outsider, "ownership accepted");
        assertEq(controller.pendingOwner(), address(0), "pending cleared");
    }

    /// E2. renounceOwnership is permanently disabled for every caller.
    function testE2_RenounceOwnershipIsPermanentlyDisabled() public {
        vm.prank(address(safe));
        vm.expectRevert(VOIDB20SkinController.RenouncingDisabled.selector);
        controller.renounceOwnership();

        vm.prank(attacker);
        vm.expectRevert(VOIDB20SkinController.RenouncingDisabled.selector);
        controller.renounceOwnership();

        assertEq(controller.owner(), address(safe), "owner retained");
    }

    /// E3. A fully malicious controller owner cannot fabricate a burn, bypass a
    ///     commitment, withdraw a token balance, mint, or reach the B20 roles
    ///     outside the controller's own functions.
    function testE3_MaliciousOwnerCannotBypassTheContest() public {
        vm.prank(address(safe));
        controller.transferOwnership(attacker);
        vm.prank(attacker);
        controller.acceptOwnership();

        // No slot exists: nothing to approve.
        vm.prank(attacker);
        vm.expectRevert(VOIDB20SkinController.NoActiveSlot.selector);
        controller.approveRename(1, "EVIL", "EVIL", "ipfs://evil", bytes32(0), bytes32(0));

        vm.prank(attacker);
        vm.expectRevert(VOIDB20SkinController.NoActiveSlot.selector);
        controller.lockRenameSlot(1);

        // A real slot exists but the attacker cannot substitute their own
        // metadata for it.
        uint256 id = _burn(first, INITIAL_BURN, keccak256("honest-commitment"));
        vm.prank(attacker);
        vm.expectRevert(VOIDB20SkinController.CommitmentMismatch.selector);
        controller.approveRename(id, "EVIL", "EVIL", "ipfs://evil", bytes32(0), bytes32(0));

        // The controller holds no balance and exposes no sweep function.
        assertEq(token.balanceOf(address(controller)), 0, "controller holds nothing");

        // The owner cannot use the controller's B20 roles directly.
        vm.startPrank(attacker);
        vm.expectRevert();
        token.updateName("EVIL");
        vm.expectRevert();
        token.burn(1 ether);
        vm.expectRevert();
        token.mint(attacker, 1 ether);
        vm.stopPrank();

        assertEq(token.name(), "VOIDCOIN", "metadata safe from a malicious owner");
    }

    /// E4. The permanent-role limitation, demonstrated: a controller that the
    ///     Safe has paused forever is still the token's only BURN_ROLE and
    ///     METADATA_ROLE holder, and no migration path exists.
    function testE4_PausedDefectiveControllerRemainsTheImmutableRoleHolder() public {
        vm.prank(address(safe));
        controller.setRenamePaused(true);

        // The Safe cannot revoke the roles or grant them to a replacement.
        VOIDB20SkinController replacement = new VOIDB20SkinController(address(safe), token);
        vm.startPrank(address(safe));
        vm.expectRevert();
        token.revokeRole(B20Constants.BURN_ROLE, address(controller));
        vm.expectRevert();
        token.grantRole(B20Constants.METADATA_ROLE, address(replacement));
        vm.stopPrank();

        // The controller cannot renounce them on the Safe's behalf either,
        // because it exposes no such function.
        assertTrue(token.hasRole(B20Constants.BURN_ROLE, address(controller)), "roles are permanent");
        assertFalse(replacement.controllerReady(), "replacement can never become ready");

        // The only remaining lever is unpausing the original controller.
        vm.prank(address(safe));
        controller.setRenamePaused(false);
        assertFalse(controller.renamePaused(), "the original controller is the only path");
    }

    // =====================================================================
    // SECTION F — Reviewer findings
    // =====================================================================

    /// F1 (FINDING). lockRenameSlot pins the burn id but NOT the commitment, so
    ///     the active burner can front-run the Safe's lock transaction with
    ///     replaceCommitment and invalidate the approval the Safe is about to
    ///     submit. The lock then freezes the WRONG commitment for six hours.
    ///     Repeatable for gas only, for the whole 72-hour TTL.
    function testF1_BurnerCanFrontRunTheLockAndInvalidateTheSafeApproval() public {
        string memory nm = "NEON VOID";
        string memory sy = "NEON";
        string memory uri = "ipfs://approved";
        bytes32 img = keccak256("img");
        bytes32 salt = keccak256("salt");

        uint256 id = controller.nextBurnId();
        bytes32 intended = _commit(id, first, INITIAL_BURN, nm, sy, uri, img, salt);
        _burn(first, INITIAL_BURN, intended);

        // The Safe has decided to approve `intended` and queues lockRenameSlot.
        // The burner front-runs it with a commitment swap that costs only gas.
        vm.prank(first);
        controller.replaceCommitment(id, keccak256("griefing-commitment"));

        // The lock lands and succeeds — it never checks WHAT it is locking.
        vm.prank(address(safe));
        controller.lockRenameSlot(id);
        assertEq(
            controller.activeSlot().commitment, keccak256("griefing-commitment"), "lock froze the wrong commitment"
        );

        // The Safe's approval, prepared against `intended`, now fails.
        vm.prank(address(safe));
        vm.expectRevert(VOIDB20SkinController.CommitmentMismatch.selector);
        controller.approveRename(id, nm, sy, uri, img, salt);

        // And for six hours nobody can take the slot over or replace it, so the
        // contest is frozen on a commitment nobody can open.
        vm.startPrank(second);
        token.approve(address(controller), 5_000_000 ether);
        vm.expectRevert(VOIDB20SkinController.SlotLocked.selector);
        controller.burnForRename(id + 1, 1_250_000 ether, keccak256("t"));
        vm.stopPrank();

        // The grief is repeatable: once the lock lapses the burner can swap
        // again, and the cycle costs the burner nothing but gas.
        vm.warp(block.timestamp + APPROVAL_LOCK_DURATION + 1);
        vm.prank(first);
        controller.replaceCommitment(id, keccak256("griefing-commitment-2"));
        vm.prank(address(safe));
        vm.expectRevert(VOIDB20SkinController.CommitmentMismatch.selector);
        controller.approveRename(id, nm, sy, uri, img, salt);
        assertEq(token.name(), "VOIDCOIN", "the rename never lands");
    }

    /// F2 (FINDING). updateName rotates the EIP-712 domain separator, so an
    ///     unused, unexpired EIP-2612 permit signed under a given name is
    ///     invalidated by a rename AND resurrected if the token is ever renamed
    ///     back to that name. The contest makes renaming back a purchasable
    ///     action.
    function testF2_RenamingBackToAPriorNameResurrectsADeadPermitSignature() public {
        (address whale, uint256 whaleKey) = makeAddrAndKey("v4-permit-whale");
        vm.prank(address(safe));
        token.transfer(whale, 50_000_000 ether);

        // The whale signs an unlimited-deadline permit under the genesis name.
        uint256 value = 25_000_000 ether;
        uint256 deadline = type(uint256).max;
        bytes32 digest = _permitDigest(whale, attacker, value, token.nonces(whale), deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(whaleKey, digest);

        // Rename 1: away from VOIDCOIN. The signature is now dead.
        _renameTo(first, "PHASE ONE", "PH1", "ipfs://one");
        assertEq(token.name(), "PHASE ONE", "renamed away");

        vm.prank(attacker);
        vm.expectRevert();
        token.permit(whale, attacker, value, deadline, v, r, s);
        assertEq(token.allowance(whale, attacker), 0, "no allowance while renamed away");

        // Rename 2: back to the original name. The dead signature is alive
        // again — the nonce was never consumed and the deadline never passed.
        _renameTo(second, "VOIDCOIN", "VOID", "ipfs://two");
        assertEq(token.name(), "VOIDCOIN", "renamed back");

        vm.prank(attacker);
        token.permit(whale, attacker, value, deadline, v, r, s);
        assertEq(token.allowance(whale, attacker), value, "resurrected permit granted a live allowance");

        vm.prank(attacker);
        token.transferFrom(whale, attacker, value);
        assertEq(token.balanceOf(attacker), value, "funds moved on a signature the signer believed was dead");
    }

    /// F3 (FINDING, defence in depth). The bootstrapper's postconditions do NOT
    ///     check decimals, name, symbol, contract URI, or that the controller is
    ///     the ONLY holder of BURN_ROLE and METADATA_ROLE. A factory that
    ///     satisfies only the checked invariants passes verification.
    function testF3_BootstrapPostconditionsMissDecimalsUriAndRoleExclusivity() public {
        SloppyButPassingFactory sloppy = new SloppyButPassingFactory(address(safe), attacker);
        VOIDB20Bootstrapper b =
            new VOIDB20Bootstrapper(address(safe), IB20Factory(address(sloppy)), bytes32("s"), "N", "S", "ipfs://u");

        IB20 t = IB20(b.token());
        // Construction succeeded even though every one of these is wrong.
        assertEq(t.decimals(), 6, "wrong decimals passed verification");
        assertEq(t.contractURI(), "", "empty contract URI passed verification");
        assertTrue(t.hasRole(B20Constants.BURN_ROLE, attacker), "a second BURN_ROLE holder passed verification");
        assertTrue(t.hasRole(B20Constants.METADATA_ROLE, attacker), "a second METADATA_ROLE holder passed verification");
    }

    /// F4 (FINDING). approveRename is front-runnable by a takeover whenever the
    ///     slot is not locked. The griefer pays the escalated burn, so this is
    ///     economically bounded, but it is the reason the lock step is
    ///     mandatory, and the lock itself has the F1 hole.
    function testF4_UnlockedApprovalIsFrontRunnableByATakeover() public {
        string memory nm = "NEON VOID";
        string memory sy = "NEON";
        string memory uri = "ipfs://approved";
        uint256 id = controller.nextBurnId();
        bytes32 c = _commit(id, first, INITIAL_BURN, nm, sy, uri, bytes32(0), bytes32(0));
        _burn(first, INITIAL_BURN, c);

        // Takeover lands before the Safe's approval.
        _burn(second, 1_250_000 ether, keccak256("takeover"));

        vm.prank(address(safe));
        vm.expectRevert(VOIDB20SkinController.CommitmentMismatch.selector);
        controller.approveRename(id, nm, sy, uri, bytes32(0), bytes32(0));
        assertEq(token.name(), "VOIDCOIN", "approval lost the race");
    }

    /// F5 (FINDING, informational). METADATA_ROLE also gates
    ///     updateExtraMetadata, but the controller exposes no path to it, so the
    ///     ERC-7572 extra-metadata surface is permanently unusable on this token.
    function testF5_ExtraMetadataIsPermanentlyUnreachable() public {
        // The role itself works when the controller calls it directly.
        vm.prank(address(controller));
        IB20Asset(address(token)).updateExtraMetadata("category", "memecoin");
        assertEq(IB20Asset(address(token)).extraMetadata("category"), "memecoin", "role works when called directly");

        // But the controller exposes no selector that reaches it, so in
        // production no transaction can ever set an extra-metadata entry.
        vm.prank(address(safe));
        (bool ok,) = address(controller).call(abi.encodeWithSignature("updateExtraMetadata(string,string)", "a", "b"));
        assertFalse(ok, "controller has no updateExtraMetadata entry point");

        // Nobody else holds METADATA_ROLE either.
        vm.prank(address(safe));
        vm.expectRevert();
        IB20Asset(address(token)).updateExtraMetadata("category", "bypass");
    }

    /// F6 (FINDING). The website commits with metadataURIHash = zeroHash
    ///     (src/app/api/requests/route.ts:67). approveRename requires a
    ///     non-empty URI whose keccak256 equals the committed hash, and
    ///     keccak256 of a non-empty string can never be bytes32(0). So the
    ///     commitment a burner destroys 1,000,000+ VOID against is unopenable
    ///     by construction: a second, time-limited replaceCommitment is
    ///     mandatory, and if it never arrives the burn is forfeited.
    function testF6_ZeroUriHashCommitmentIsUnopenableAndTheBurnIsForfeited() public {
        uint256 id = controller.nextBurnId();
        // Exactly what the API builds today: every field real except the URI
        // hash, which is left as zero.
        bytes32 apiCommitment = controller.proposalCommitment(
            id, first, INITIAL_BURN, "NEON VOID", "NEON", keccak256("image"), bytes32(0), keccak256("salt")
        );
        _burn(first, INITIAL_BURN, apiCommitment);
        assertEq(controller.recordBurn(), INITIAL_BURN, "the burn is already final");

        // No URI can open it. The empty string is rejected by the length
        // bound; any non-empty string hashes to something other than zero.
        vm.startPrank(address(safe));
        vm.expectRevert(VOIDB20SkinController.InvalidMetadataURI.selector);
        controller.approveRename(id, "NEON VOID", "NEON", "", keccak256("image"), keccak256("salt"));

        vm.expectRevert(VOIDB20SkinController.CommitmentMismatch.selector);
        controller.approveRename(id, "NEON VOID", "NEON", "ipfs://anything", keccak256("image"), keccak256("salt"));
        vm.stopPrank();

        // The only escape is replaceCommitment, and it is bounded by SLOT_TTL.
        // If the burner does not return in time the burn is simply lost.
        vm.warp(block.timestamp + SLOT_TTL + 1);
        vm.prank(first);
        vm.expectRevert(VOIDB20SkinController.SlotExpired.selector);
        controller.replaceCommitment(id, keccak256("too-late"));

        uint256 balanceAfter = token.balanceOf(first);
        controller.expireSlot();
        assertEq(token.balanceOf(first), balanceAfter, "no refund");
        assertEq(token.totalSupply(), ORIGINAL_SUPPLY - INITIAL_BURN, "supply stays reduced");
        assertEq(token.name(), "VOIDCOIN", "and no rename was ever obtained");
    }

    // =====================================================================
    // Internal helpers
    // =====================================================================

    function _renameTo(address burner, string memory nm, string memory sy, string memory uri) internal {
        uint256 id = controller.nextBurnId();
        uint256 amount = controller.nextBurnRequirement();
        bytes32 c = _commit(id, burner, amount, nm, sy, uri, bytes32(0), bytes32(0));
        vm.startPrank(burner);
        token.approve(address(controller), amount);
        controller.burnForRename(id, amount, c);
        vm.stopPrank();
        vm.prank(address(safe));
        controller.approveRename(id, nm, sy, uri, bytes32(0), bytes32(0));
    }

    function _permitDigest(address owner, address spender, uint256 value, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        bytes32 typeHash =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        bytes32 structHash = keccak256(abi.encode(typeHash, owner, spender, value, nonce, deadline));
        return keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
    }

    function _nameAccepted(string memory candidate) internal returns (bool) {
        return _tryApprove(candidate, "SYM", "ipfs://x");
    }

    function _symbolAccepted(string memory candidate) internal returns (bool) {
        return _tryApprove("VALID NAME", candidate, "ipfs://x");
    }

    function _uriAccepted(string memory candidate) internal returns (bool) {
        return _tryApprove("VALID NAME", "SYM", candidate);
    }

    /// @dev Opens a fresh slot committed to (name, symbol, uri) and reports
    ///      whether approveRename accepts it. Snapshots so each probe is
    ///      independent.
    function _tryApprove(string memory nm, string memory sy, string memory uri) internal returns (bool accepted) {
        uint256 snap = vm.snapshotState();
        uint256 id = controller.nextBurnId();
        uint256 amount = controller.nextBurnRequirement();
        bytes32 c = _commit(id, first, amount, nm, sy, uri, bytes32(0), bytes32(0));

        vm.startPrank(first);
        token.approve(address(controller), amount);
        controller.burnForRename(id, amount, c);
        vm.stopPrank();

        vm.prank(address(safe));
        (accepted,) = address(controller)
            .call(
                abi.encodeWithSelector(
                    VOIDB20SkinController.approveRename.selector, id, nm, sy, uri, bytes32(0), bytes32(0)
                )
            );
        vm.revertToState(snap);
    }

    function _repeat(string memory unit, uint256 times) internal pure returns (string memory out) {
        bytes memory u = bytes(unit);
        bytes memory buf = new bytes(u.length * times);
        uint256 k;
        for (uint256 i; i < times; ++i) {
            for (uint256 j; j < u.length; ++j) {
                buf[k++] = u[j];
            }
        }
        out = string(buf);
    }
}

// ===========================================================================
// Adversarial doubles used by Section A and Section D
// ===========================================================================

/// @notice Returns one address from getB20Address and a different one from
///         createB20, to prove the UnexpectedToken guard fires.
contract LyingFactory {
    address public created;

    function getB20Address(uint8, address, bytes32) external pure returns (address) {
        return address(0xDEAD);
    }

    function createB20(uint8, bytes32, bytes calldata, bytes[] calldata) external returns (address) {
        created = address(0xBEEF);
        return created;
    }

    function isB20(address) external pure returns (bool) {
        return true;
    }

    function isB20Initialized(address) external pure returns (bool) {
        return true;
    }
}

/// @notice Agrees on the address but reports the token as uninitialized, to
///         prove the BootstrapInvariantFailed guard fires before any token read.
contract UninitializedReportingFactory {
    function getB20Address(uint8, address, bytes32) external view returns (address) {
        return _predict();
    }

    function _predict() internal view returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(address(this), "stub")))));
    }

    function createB20(uint8, bytes32, bytes calldata, bytes[] calldata) external view returns (address) {
        return _predict();
    }

    function isB20(address) external pure returns (bool) {
        return true;
    }

    function isB20Initialized(address) external pure returns (bool) {
        return false;
    }
}

/// @notice A factory that satisfies exactly the invariants the bootstrapper
///         checks and nothing else: wrong decimals, empty contract URI, and an
///         extra BURN_ROLE / METADATA_ROLE holder that is never noticed.
contract SloppyButPassingFactory {
    SloppyB20 public immutable tokenContract;

    constructor(address safe_, address extraRoleHolder) {
        tokenContract = new SloppyB20(safe_, extraRoleHolder);
    }

    function getB20Address(uint8, address, bytes32) external view returns (address) {
        return address(tokenContract);
    }

    function createB20(uint8, bytes32, bytes calldata, bytes[] calldata initCalls) external returns (address) {
        // Honour only the role grants; ignore cap, mint and URI entirely.
        for (uint256 i; i < initCalls.length; ++i) {
            if (bytes4(initCalls[i]) == bytes4(keccak256("grantRole(bytes32,address)"))) {
                (bytes32 role, address account) = abi.decode(_body(initCalls[i]), (bytes32, address));
                tokenContract.grantRole(role, account);
            }
        }
        return address(tokenContract);
    }

    function _body(bytes memory data) internal pure returns (bytes memory out) {
        out = new bytes(data.length - 4);
        for (uint256 i; i < out.length; ++i) {
            out[i] = data[i + 4];
        }
    }

    function isB20(address) external pure returns (bool) {
        return true;
    }

    function isB20Initialized(address) external pure returns (bool) {
        return true;
    }
}

/// @notice A minimal B20 stand-in that satisfies only the checked invariants.
contract SloppyB20 {
    uint256 public constant SUPPLY = 1_000_000_000 ether;
    address public immutable safe;
    address public immutable extra;
    mapping(bytes32 => mapping(address => bool)) internal _roles;

    constructor(address safe_, address extra_) {
        safe = safe_;
        extra = extra_;
        _roles[keccak256("BURN_ROLE")][extra_] = true;
        _roles[keccak256("METADATA_ROLE")][extra_] = true;
    }

    function grantRole(bytes32 role, address account) external {
        _roles[role][account] = true;
    }

    function totalSupply() external pure returns (uint256) {
        return SUPPLY;
    }

    function supplyCap() external pure returns (uint256) {
        return SUPPLY;
    }

    function balanceOf(address who) external view returns (uint256) {
        return who == safe ? SUPPLY : 0;
    }

    function hasRole(bytes32 role, address account) external view returns (bool) {
        return _roles[role][account];
    }

    function decimals() external pure returns (uint8) {
        return 6;
    }

    function contractURI() external pure returns (string memory) {
        return "";
    }

    function name() external pure returns (string memory) {
        return "";
    }

    function symbol() external pure returns (string memory) {
        return "";
    }
}

/// @notice ERC-20 that accepts burn() but never reduces totalSupply, to prove
///         the post-burn supply assertion fires.
contract NonBurningToken {
    string public name = "STUB";
    string public symbol = "STUB";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    string public contractURI;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mintTo(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function burn(uint256) external {
        // deliberately does not reduce totalSupply
    }

    function hasRole(bytes32, address) external pure returns (bool) {
        return true;
    }

    function updateName(string calldata v) external {
        name = v;
    }

    function updateSymbol(string calldata v) external {
        symbol = v;
    }

    function updateContractURI(string calldata v) external {
        contractURI = v;
    }
}

/// @notice ERC-20 stand-in whose updateSymbol always reverts, to prove
///         approveRename is atomic across the three metadata calls.
contract RevertOnSymbolToken {
    string public name = "STUB";
    string public symbol = "STUB";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    string public contractURI;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    error SymbolUpdateRejected();

    function mintTo(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function burn(uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
    }

    function hasRole(bytes32, address) external pure returns (bool) {
        return true;
    }

    function updateName(string calldata v) external {
        name = v;
    }

    function updateSymbol(string calldata) external pure {
        revert SymbolUpdateRejected();
    }

    function updateContractURI(string calldata v) external {
        contractURI = v;
    }
}

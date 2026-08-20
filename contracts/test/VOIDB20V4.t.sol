// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseTest} from "base-std-test/lib/BaseTest.sol";
import {IB20} from "base-std/interfaces/IB20.sol";
import {B20Constants} from "base-std/lib/B20Constants.sol";
import {StdPrecompiles} from "base-std/StdPrecompiles.sol";
import {VOIDB20Bootstrapper} from "../src/VOIDB20Bootstrapper.sol";
import {VOIDB20SkinController} from "../src/VOIDB20SkinController.sol";

contract MockProductionSafe {}

contract VOIDB20V4Test is BaseTest {
    MockProductionSafe internal safe;
    IB20 internal token;
    VOIDB20SkinController internal controller;
    address internal first = makeAddr("first-burner");
    address internal second = makeAddr("second-burner");

    function setUp() public override {
        super.setUp();
        safe = new MockProductionSafe();
        VOIDB20Bootstrapper bootstrapper = new VOIDB20Bootstrapper(
            address(safe),
            StdPrecompiles.B20_FACTORY,
            keccak256("VOID-B20-V4-TEST"),
            "VOIDCOIN",
            "VOID",
            "ipfs://initial-metadata"
        );
        token = IB20(bootstrapper.token());
        controller = bootstrapper.controller();

        vm.startPrank(address(safe));
        token.transfer(first, 100_000_000 ether);
        token.transfer(second, 100_000_000 ether);
        controller.setRenamePaused(false);
        vm.stopPrank();
    }

    function testBootstrapCreatesExactAdminlessOneBillionSupply() public view {
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(token.supplyCap(), 1_000_000_000 ether);
        assertEq(token.balanceOf(address(safe)), 800_000_000 ether);
        assertTrue(controller.controllerReady());
        assertFalse(token.hasRole(B20Constants.DEFAULT_ADMIN_ROLE, address(safe)));
        assertFalse(token.hasRole(B20Constants.MINT_ROLE, address(safe)));
        assertFalse(token.hasRole(B20Constants.PAUSE_ROLE, address(safe)));
        assertFalse(token.hasRole(B20Constants.UNPAUSE_ROLE, address(safe)));
        assertFalse(token.hasRole(B20Constants.SEIZE_ROLE, address(safe)));
        assertTrue(token.hasRole(B20Constants.BURN_ROLE, address(controller)));
        assertTrue(token.hasRole(B20Constants.METADATA_ROLE, address(controller)));
    }

    function testContestBurnActuallyReducesNativeB20Supply() public {
        uint256 amount = controller.INITIAL_BURN();
        vm.startPrank(first);
        token.approve(address(controller), amount);
        controller.burnForRename(1, amount, keccak256("proposal"));
        vm.stopPrank();

        assertEq(token.totalSupply(), controller.ORIGINAL_SUPPLY() - amount);
        assertEq(token.balanceOf(address(controller)), 0);
        assertEq(controller.contestBurned(), amount);
        assertEq(controller.destroyedSupply(), amount);
        assertEq(controller.recordBurner(), first);
    }

    function testApprovedProposalUpdatesNameSymbolAndContractURI() public {
        uint256 burnId = 1;
        uint256 amount = controller.INITIAL_BURN();
        string memory newName = "NEON VOID";
        string memory newSymbol = "NEON";
        string memory uri = "ipfs://approved-metadata";
        bytes32 imageHash = keccak256("image");
        bytes32 salt = keccak256("salt");
        bytes32 commitment = controller.proposalCommitment(
            burnId, first, amount, newName, newSymbol, imageHash, keccak256(bytes(uri)), salt
        );

        _burn(first, amount, commitment);
        vm.prank(address(safe));
        controller.approveRename(burnId, newName, newSymbol, uri, imageHash, salt);

        assertEq(token.name(), newName);
        assertEq(token.symbol(), newSymbol);
        assertEq(token.contractURI(), uri);
        assertEq(controller.activeSlot().burner, address(0));
    }

    function testSafeCannotBypassContestAndChangeMetadataDirectly() public {
        vm.prank(address(safe));
        vm.expectRevert();
        token.updateName("BYPASS");
    }

    function testNobodyCanMintMoreSupply() public {
        vm.prank(address(safe));
        vm.expectRevert();
        token.mint(address(safe), 1);
        assertEq(token.totalSupply(), 1_000_000_000 ether);
    }

    function testControllerWithoutRolesCannotBeUnpaused() public {
        VOIDB20SkinController unready = new VOIDB20SkinController(address(safe), token);
        vm.prank(address(safe));
        vm.expectRevert(VOIDB20SkinController.ControllerNotReady.selector);
        unready.setRenamePaused(false);
    }

    function testHigherBurnTakesControlAndBothIncreaseRulesApply() public {
        _burn(first, 1_000_000 ether, keccak256("first"));
        _burn(second, 1_250_000 ether, keccak256("second"));
        assertEq(controller.activeSlot().burner, second);
        assertEq(controller.nextBurnRequirement(), 1_500_000 ether);
        _burn(first, 3_000_000 ether, keccak256("third"));
        assertEq(controller.nextBurnRequirement(), 3_300_000 ether);
    }

    function testMismatchedApprovalRollsBackMetadataAndKeepsSlot() public {
        uint256 amount = controller.INITIAL_BURN();
        bytes32 imageHash = keccak256("image");
        bytes32 salt = keccak256("salt");
        bytes32 commitment = controller.proposalCommitment(
            1, first, amount, "NEON VOID", "NEON", imageHash, keccak256(bytes("ipfs://approved")), salt
        );
        _burn(first, amount, commitment);

        vm.prank(address(safe));
        vm.expectRevert(VOIDB20SkinController.CommitmentMismatch.selector);
        controller.approveRename(1, "WRONG", "NEON", "ipfs://approved", imageHash, salt);

        assertEq(token.name(), "VOIDCOIN");
        assertEq(token.symbol(), "VOID");
        assertEq(token.contractURI(), "ipfs://initial-metadata");
        assertEq(controller.activeSlot().burner, first);
    }

    function testStaleBurnIdRevertsBeforeTokensMoveOrAllowanceChanges() public {
        uint256 staleBurnId = controller.nextBurnId();
        _burn(first, 1_000_000 ether, keccak256("first"));
        uint256 secondBalanceBefore = token.balanceOf(second);

        vm.startPrank(second);
        token.approve(address(controller), 1_250_000 ether);
        vm.expectRevert(VOIDB20SkinController.UnexpectedBurnId.selector);
        controller.burnForRename(staleBurnId, 1_250_000 ether, keccak256("stale"));
        vm.stopPrank();

        assertEq(token.balanceOf(second), secondBalanceBefore);
        assertEq(token.allowance(second, address(controller)), 1_250_000 ether);
        assertEq(controller.currentBurnId(), 1);
    }

    function testControllerStartsPausedBeforeSafeExplicitlyUnpauses() public {
        VOIDB20Bootstrapper fresh = new VOIDB20Bootstrapper(
            address(safe),
            StdPrecompiles.B20_FACTORY,
            keccak256("SECOND-VOID-B20"),
            "VOIDCOIN",
            "VOID",
            "ipfs://initial-metadata"
        );
        assertTrue(fresh.controller().renamePaused());
    }

    function _burn(address burner, uint256 amount, bytes32 commitment) internal {
        vm.startPrank(burner);
        token.approve(address(controller), amount);
        controller.burnForRename(controller.nextBurnId(), amount, commitment);
        vm.stopPrank();
    }
}

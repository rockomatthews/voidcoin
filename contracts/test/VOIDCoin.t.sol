// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {VOIDCoin} from "../src/VOIDCoin.sol";

contract VOIDCoinTest is Test {
    VOIDCoin internal token;
    address internal safe = makeAddr("safe");
    address internal launch = makeAddr("launch");
    address internal vesting = makeAddr("vesting");
    address internal burner = makeAddr("burner");

    bytes32 internal imageHash = keccak256("image");
    bytes32 internal salt = keccak256("salt");

    function setUp() public {
        token = new VOIDCoin(safe, launch, vesting, "ipfs://genesis");
        vm.prank(launch);
        token.transfer(burner, 2_000_000 ether);
    }

    function testInitialAllocationAndIdentity() public view {
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(token.balanceOf(launch), 898_000_000 ether);
        assertEq(token.balanceOf(vesting), 100_000_000 ether);
        assertEq(token.balanceOf(burner), 2_000_000 ether);
        assertEq(token.name(), "VOIDCOIN");
        assertEq(token.symbol(), "VOID");
        assertEq(token.tokenURI(), "ipfs://genesis");
        assertTrue(token.renamePaused());
    }

    function testBurnApproveAndCooldownLifecycle() public {
        vm.prank(safe);
        token.setRenamePaused(false);

        uint256 burnId = token.nextBurnId();
        bytes32 commitment = token.proposalCommitment(burnId, burner, "Night Shift", "NIGHT", imageHash, salt);
        vm.prank(burner);
        token.burnForRename(commitment);

        assertEq(token.totalSupply(), 999_000_000 ether);
        assertEq(token.destroyedSupply(), 1_000_000 ether);
        assertEq(token.activeSlot().burner, burner);

        vm.prank(safe);
        token.approveRename(burnId, "Night Shift", "NIGHT", "ipfs://night", imageHash, salt);
        assertEq(token.name(), "Night Shift");
        assertEq(token.symbol(), "NIGHT");
        assertEq(token.tokenURI(), "ipfs://night");
        assertEq(token.activeSlot().burner, address(0));

        bytes32 secondCommitment = keccak256("second");
        vm.expectRevert(VOIDCoin.CooldownActive.selector);
        vm.prank(burner);
        token.burnForRename(secondCommitment);

        vm.warp(block.timestamp + 2 minutes);
        vm.prank(burner);
        token.burnForRename(secondCommitment);
    }

    function testActiveBurnerCanReplaceCommitmentWithoutSecondBurn() public {
        vm.prank(safe);
        token.setRenamePaused(false);
        vm.prank(burner);
        token.burnForRename(keccak256("first"));
        uint256 supplyAfterBurn = token.totalSupply();

        vm.prank(burner);
        token.replaceCommitment(keccak256("clean"));

        assertEq(token.activeSlot().commitment, keccak256("clean"));
        assertEq(token.totalSupply(), supplyAfterBurn);
    }

    function testOnlyOneSlotAndOnlyBurnerCanReplace() public {
        vm.prank(safe);
        token.setRenamePaused(false);
        vm.prank(burner);
        token.burnForRename(keccak256("first"));

        vm.expectRevert(VOIDCoin.SlotAlreadyActive.selector);
        vm.prank(launch);
        token.burnForRename(keccak256("second"));

        vm.expectRevert(VOIDCoin.NotActiveBurner.selector);
        vm.prank(launch);
        token.replaceCommitment(keccak256("replace"));
    }

    function testExpiryIsPermissionlessAndBurnIsNotRefunded() public {
        vm.prank(safe);
        token.setRenamePaused(false);
        vm.prank(burner);
        token.burnForRename(keccak256("first"));
        uint256 balanceAfterBurn = token.balanceOf(burner);

        vm.expectRevert(VOIDCoin.SlotNotExpired.selector);
        token.expireSlot();

        vm.warp(block.timestamp + 72 hours);
        token.expireSlot();
        assertEq(token.activeSlot().burner, address(0));
        assertEq(token.balanceOf(burner), balanceAfterBurn);
    }

    function testCommitmentAndValidationAreEnforced() public {
        vm.prank(safe);
        token.setRenamePaused(false);
        uint256 burnId = token.nextBurnId();
        bytes32 commitment = token.proposalCommitment(burnId, burner, "Clean Name", "CLEAN", imageHash, salt);
        vm.prank(burner);
        token.burnForRename(commitment);

        vm.expectRevert(VOIDCoin.CommitmentMismatch.selector);
        vm.prank(safe);
        token.approveRename(burnId, "Wrong Name", "CLEAN", "ipfs://clean", imageHash, salt);
    }

    function testOnlyOwnerCanApproveOrPause() public {
        vm.expectRevert();
        token.setRenamePaused(false);

        vm.expectRevert();
        token.approveRename(1, "Name", "NAME", "ipfs://name", imageHash, salt);
    }

    function testFuzzSupplyOnlyDropsByFixedBurn(uint8 burnCount) public {
        burnCount = uint8(bound(burnCount, 1, 20));
        vm.prank(launch);
        token.transfer(burner, uint256(burnCount) * 1_000_000 ether);
        vm.prank(safe);
        token.setRenamePaused(false);

        for (uint256 i; i < burnCount; ++i) {
            vm.prank(burner);
            token.burnForRename(keccak256(abi.encode(i)));
            vm.warp(block.timestamp + 72 hours);
            token.expireSlot();
        }

        assertEq(token.destroyedSupply(), uint256(burnCount) * 1_000_000 ether);
        assertEq(token.totalSupply(), token.ORIGINAL_SUPPLY() - uint256(burnCount) * 1_000_000 ether);
    }
}

contract UnauthorizedMetadataHandler {
    VOIDCoin internal immutable token;

    constructor(VOIDCoin token_) {
        token = token_;
    }

    function attemptApproval(bytes32 salt, bytes32 imageHash) external {
        try token.approveRename(1, "Unapproved", "NOPE", "ipfs://unapproved", imageHash, salt) {} catch {}
    }

    function attemptPause(bool paused) external {
        try token.setRenamePaused(paused) {} catch {}
    }
}

contract VOIDCoinInvariantTest is StdInvariant, Test {
    VOIDCoin internal token;
    UnauthorizedMetadataHandler internal handler;

    function setUp() public {
        token = new VOIDCoin(address(this), address(0xBEEF), address(0xCAFE), "ipfs://genesis");
        handler = new UnauthorizedMetadataHandler(token);
        targetContract(address(handler));
    }

    function invariantUnauthorizedCallsCannotChangeMetadata() public view {
        assertEq(token.name(), "VOIDCOIN");
        assertEq(token.symbol(), "VOID");
        assertEq(token.tokenURI(), "ipfs://genesis");
    }

    function invariantSupplyCannotIncrease() public view {
        assertLe(token.totalSupply(), token.ORIGINAL_SUPPLY());
    }
}

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
    address internal firstBurner = makeAddr("firstBurner");
    address internal challenger = makeAddr("challenger");

    bytes32 internal imageHash = keccak256("image");
    bytes32 internal salt = keccak256("salt");

    function setUp() public {
        token = new VOIDCoin(safe, launch, vesting, "ipfs://genesis");
        vm.startPrank(launch);
        token.transfer(firstBurner, 20_000_000 ether);
        token.transfer(challenger, 20_000_000 ether);
        vm.stopPrank();
    }

    function testInitialAllocationIdentityAndFirstRequirement() public view {
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(token.balanceOf(launch), 860_000_000 ether);
        assertEq(token.balanceOf(vesting), 100_000_000 ether);
        assertEq(token.name(), "VOIDCOIN");
        assertEq(token.symbol(), "VOID");
        assertEq(token.tokenURI(), "ipfs://genesis");
        assertEq(token.nextBurnRequirement(), 1_000_000 ether);
        assertTrue(token.renamePaused());
    }

    function testRecordBurnCanBeApprovedBySafe() public {
        _unpause();
        uint256 amount = token.nextBurnRequirement();
        uint256 burnId = token.nextBurnId();
        bytes32 commitment =
            token.proposalCommitment(burnId, firstBurner, amount, "Night Shift", "NIGHT", imageHash, salt);

        vm.prank(firstBurner);
        token.burnForRename(amount, commitment);

        assertEq(token.totalSupply(), 999_000_000 ether);
        assertEq(token.destroyedSupply(), amount);
        assertEq(token.recordBurn(), amount);
        assertEq(token.recordBurner(), firstBurner);
        assertEq(token.nextBurnRequirement(), 2_000_000 ether);
        assertEq(token.activeSlot().burnAmount, amount);

        vm.prank(safe);
        token.approveRename(burnId, "Night Shift", "NIGHT", "ipfs://night", imageHash, salt);
        assertEq(token.name(), "Night Shift");
        assertEq(token.symbol(), "NIGHT");
        assertEq(token.tokenURI(), "ipfs://night");
        assertEq(token.activeSlot().burner, address(0));
        assertEq(token.recordBurn(), amount);
    }

    function testChallengerAutomaticallyBurnsNextIncrement() public {
        _unpause();
        _burn(firstBurner, keccak256("first"));

        _burn(challenger, keccak256("challenge"));
        assertEq(token.recordBurner(), challenger);
        assertEq(token.recordBurn(), 2_000_000 ether);
        assertEq(token.activeSlot().burner, challenger);
        assertEq(token.destroyedSupply(), 3_000_000 ether);
    }

    function testNewRecordSupersedesPendingProposalWithoutRefund() public {
        _unpause();
        _burn(firstBurner, keccak256("first"));
        uint256 firstBalanceAfterBurn = token.balanceOf(firstBurner);

        _burn(challenger, keccak256("challenge"));

        assertEq(token.balanceOf(firstBurner), firstBalanceAfterBurn);
        assertEq(token.activeSlot().burner, challenger);
        assertEq(token.activeSlot().burnId, 2);
        assertEq(token.nextBurnRequirement(), 3_000_000 ether);
    }

    function testLeaderCanReplaceCommitmentWithoutAnotherBurn() public {
        _unpause();
        _burn(firstBurner, keccak256("first"));
        uint256 supplyAfterBurn = token.totalSupply();

        vm.prank(firstBurner);
        token.replaceCommitment(keccak256("clean"));

        assertEq(token.activeSlot().commitment, keccak256("clean"));
        assertEq(token.totalSupply(), supplyAfterBurn);
    }

    function testOnlyCurrentLeaderCanReplaceCommitment() public {
        _unpause();
        _burn(firstBurner, keccak256("first"));

        vm.expectRevert(VOIDCoin.NotActiveBurner.selector);
        vm.prank(challenger);
        token.replaceCommitment(keccak256("replace"));
    }

    function testCommitmentBindsBurnAmount() public {
        _unpause();
        _burn(challenger, keccak256("first"));
        uint256 burnId = token.nextBurnId();
        bytes32 commitment =
            token.proposalCommitment(burnId, firstBurner, 1_000_000 ether, "Clean Name", "CLEAN", imageHash, salt);
        vm.prank(firstBurner);
        token.burnForRename(2_000_000 ether, commitment);

        vm.expectRevert(VOIDCoin.CommitmentMismatch.selector);
        vm.prank(safe);
        token.approveRename(burnId, "Clean Name", "CLEAN", "ipfs://clean", imageHash, salt);
    }

    function testStaleBurnRequirementRevertsBeforeTokensAreBurned() public {
        _unpause();
        uint256 staleAmount = token.nextBurnRequirement();
        _burn(firstBurner, keccak256("first"));
        uint256 challengerBalance = token.balanceOf(challenger);

        vm.expectRevert(VOIDCoin.BurnRequirementChanged.selector);
        vm.prank(challenger);
        token.burnForRename(staleAmount, keccak256("stale"));

        assertEq(token.balanceOf(challenger), challengerBalance);
        assertEq(token.recordBurn(), 1_000_000 ether);
    }

    function testOnlyOwnerCanApproveOrPause() public {
        vm.expectRevert();
        token.setRenamePaused(false);

        vm.expectRevert();
        token.approveRename(1, "Name", "NAME", "ipfs://name", imageHash, salt);
    }

    function testFuzzSuccessiveRecordsPermanentlyReduceSupply(uint8 burnCount) public {
        burnCount = uint8(bound(burnCount, 1, 12));
        uint256 requiredBalance = uint256(burnCount) * (uint256(burnCount) + 1) / 2 * 1_000_000 ether;
        vm.prank(launch);
        token.transfer(firstBurner, requiredBalance);
        _unpause();

        uint256 expectedDestroyed;
        for (uint256 i = 1; i <= burnCount; ++i) {
            uint256 amount = i * 1_000_000 ether;
            _burn(firstBurner, keccak256(abi.encode(i)));
            expectedDestroyed += amount;
        }

        assertEq(token.destroyedSupply(), expectedDestroyed);
        assertEq(token.totalSupply(), token.ORIGINAL_SUPPLY() - expectedDestroyed);
        assertEq(token.nextBurnRequirement(), (uint256(burnCount) + 1) * 1_000_000 ether);
    }

    function _unpause() internal {
        vm.prank(safe);
        token.setRenamePaused(false);
    }

    function _burn(address burner, bytes32 commitment) internal {
        uint256 amount = token.nextBurnRequirement();
        vm.prank(burner);
        token.burnForRename(amount, commitment);
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

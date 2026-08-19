// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {VOIDBondingCurve} from "../src/VOIDBondingCurve.sol";
import {VOIDCoin} from "../src/VOIDCoin.sol";
import {VOIDLaunch} from "../src/VOIDLaunch.sol";
import {VOIDTreasuryVesting} from "../src/VOIDTreasuryVesting.sol";
import {VOIDPositionLocker} from "../src/VOIDPositionLocker.sol";
import {VOIDUniswapV3Migration, IVOIDUniswapV3PositionManager} from "../src/VOIDUniswapV3Migration.sol";
import {VOIDGraduationExecutor, IVOIDGraduationCurve, IVOIDGraduationRouter} from "../src/VOIDGraduationExecutor.sol";
import {
    ModelPool,
    ModelPositionManager,
    ModelSwapRouter02,
    BaseWETH9,
    GenerousWETH9,
    UniMath
} from "./UniV3Model.sol";

/// @notice Models a Gnosis Safe: a fallback that delegatecalls a handler.
contract SafeHandler {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract ModelSafe {
    address public handler;

    constructor(address handler_) {
        handler = handler_;
    }

    function setHandler(address handler_) external {
        handler = handler_;
    }

    receive() external payable {}

    fallback() external payable {
        address h = handler;
        assembly {
            if iszero(h) { return(0, 0) } // handler-less Safe: succeeds with empty returndata
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), h, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if iszero(ok) { revert(0, returndatasize()) }
            return(0, returndatasize())
        }
    }
}

contract ThrowawayToken is ERC20 {
    constructor(address to, uint256 amount) ERC20("Throwaway", "TWY") {
        _mint(to, amount);
    }
}

contract EthForcer {
    function forceTo(address payable target) external payable {
        selfdestruct(target);
    }
}

/// @notice Tries to reenter the executor from an ETH refund.
contract ReentrantCaller {
    VOIDGraduationExecutor public immutable executor;
    bool public tried;
    bool public succeeded;

    constructor(VOIDGraduationExecutor executor_) {
        executor = executor_;
    }

    function go() external payable {
        executor.execute{value: msg.value}(0);
    }

    receive() external payable {
        if (!tried) {
            tried = true;
            try executor.execute{value: 0}(0) {
                succeeded = true;
            } catch {}
        }
    }
}

contract Phase4PoCTest is Test {
    address internal safe;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    uint256 internal constant VIRTUAL_ETH = 100 ether;
    uint256 internal constant GRAD_THRESHOLD = 25 ether;
    uint24 internal constant POOL_FEE = 10_000;

    BaseWETH9 internal weth;
    ModelPositionManager internal manager;
    ModelSwapRouter02 internal router;
    VOIDUniswapV3Migration internal adapter;
    VOIDPositionLocker internal locker;
    VOIDLaunch internal launch;
    VOIDCoin internal token;
    VOIDBondingCurve internal curve;
    VOIDTreasuryVesting internal vesting;
    VOIDGraduationExecutor internal executor;

    receive() external payable {}

    function setUp() public {
        safe = address(new ModelSafe(address(new SafeHandler())));
        weth = new BaseWETH9();
        manager = new ModelPositionManager(address(weth));
        router = new ModelSwapRouter02(manager);
        adapter = new VOIDUniswapV3Migration(IVOIDUniswapV3PositionManager(address(manager)), safe);
        locker = new VOIDPositionLocker(IERC721(address(manager)), safe);
        launch = new VOIDLaunch(safe, address(adapter), address(locker), VIRTUAL_ETH, GRAD_THRESHOLD, "ipfs://genesis");
        token = launch.token();
        curve = launch.bondingCurve();
        vesting = launch.vestingWallet();
        executor = new VOIDGraduationExecutor(
            IVOIDGraduationCurve(address(curve)), IVOIDGraduationRouter(address(router))
        );

        vm.deal(alice, 10_000 ether);
        vm.deal(bob, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
        vm.deal(address(this), 10_000 ether);
    }

    // ---------------- helpers ----------------

    /// @dev Respects the frozen 1 ETH per-transaction cap by chunking.
    function _buy(address who, uint256 ethIn) internal returns (uint256 total) {
        uint256 cap = curve.maxBuyAmount();
        while (ethIn > 0) {
            uint256 chunk = ethIn > cap ? cap : ethIn;
            uint256 quote = curve.quoteBuy(chunk);
            vm.prank(who);
            total += curve.buy{value: chunk}(quote, block.timestamp);
            ethIn -= chunk;
        }
    }

    function _sell(address who, uint256 amount) internal {
        uint256 q = curve.quoteSell(amount);
        vm.startPrank(who);
        token.approve(address(curve), amount);
        curve.sell(amount, q, block.timestamp);
        vm.stopPrank();
    }

    /// @dev 25 production-sized purchases. Bob and the test contract each take a
    ///      slice so a VOID-side correction can be funded without perturbing the
    ///      curve after the direction has been measured.
    function _fundToThreshold() internal {
        for (uint256 i; i < 22; ++i) {
            _buy(alice, 1 ether);
        }
        _buy(bob, 2 ether);
        _buy(address(this), 1 ether);
        assertTrue(curve.graduationReady(), "threshold latched");
    }

    function _poolAddr() internal view returns (address) {
        return manager.getPool(address(token), address(weth), POOL_FEE);
    }

    function _poolPrice() internal view returns (uint160) {
        address p = _poolAddr();
        return p == address(0) ? 0 : ModelPool(p).sqrtPriceX96();
    }

    function _target() internal view returns (uint160) {
        return executor.targetSqrtPriceX96(address(weth));
    }

    function _sqrt(uint256 amount0, uint256 amount1) internal pure returns (uint160) {
        return uint160(Math.sqrt(Math.mulDiv(amount1, uint256(1) << 192, amount0)));
    }

    /// @dev The asset the executor will need for correction, given live state.
    function _correctionIsVoid() internal view returns (bool) {
        bool tokenIsToken0 = address(token) < address(weth);
        address t0 = tokenIsToken0 ? address(token) : address(weth);
        address t1 = tokenIsToken0 ? address(weth) : address(token);
        address asset = _poolPrice() > _target() ? t0 : t1;
        return asset == address(token);
    }

    /// @dev Pre-initialise the pool at `multiplier`x the fair graduation price.
    function _hostileInit(uint256 numerator, uint256 denominator) internal {
        (uint256 liq,) = curve.graduationLiquidityQuote();
        uint256 e = curve.ethReserve();
        bool tokenIsToken0 = address(token) < address(weth);
        (address t0, address t1) = tokenIsToken0 ? (address(token), address(weth)) : (address(weth), address(token));
        uint256 a0 = tokenIsToken0 ? liq : e;
        uint256 a1 = tokenIsToken0 ? e : liq;
        uint160 hostile = uint160(Math.sqrt(Math.mulDiv(Math.mulDiv(a1, numerator, denominator), 1 << 192, a0)));
        vm.prank(attacker);
        manager.createAndInitializePoolIfNecessary(t0, t1, POOL_FEE, hostile);
    }

    function _assertPriceClose(uint160 a, uint160 b, string memory why) internal pure {
        uint256 hi = a > b ? a : b;
        uint256 lo = a > b ? b : a;
        // within 1 part per billion
        assertLe(Math.mulDiv(hi - lo, 1e9, hi), 1, why);
    }

    function _executeWith(address caller, uint256 ethIn, uint256 voidIn) internal {
        if (voidIn > 0) {
            vm.prank(caller);
            token.approve(address(executor), voidIn);
        }
        vm.prank(caller);
        executor.execute{value: ethIn}(voidIn);
    }

    // =====================================================================
    // CONFIRMATION 1 — F-01 closed
    // =====================================================================

    function testC1_VirginPoolSeedThenDirectGraduateWithNoCorrectiveSwap() public {
        _fundToThreshold();

        uint256 supplyBefore = token.totalSupply();
        uint256 priceBeforeSeed = Math.mulDiv(VIRTUAL_ETH + curve.ethReserve(), 1e18, curve.tokenReserve());

        assertEq(_poolAddr(), address(0), "pool does not exist yet");

        vm.prank(safe);
        curve.seedMigrationPool();

        uint256 priceAfterSeed = Math.mulDiv(VIRTUAL_ETH + curve.ethReserve(), 1e18, curve.tokenReserve());
        console2.log("C1 curve marginal price before seed:", priceBeforeSeed);
        console2.log("C1 curve marginal price after seed: ", priceAfterSeed);
        assertEq(priceAfterSeed, priceBeforeSeed, "seed is exactly price-neutral on the curve");

        _assertPriceClose(_poolPrice(), _target(), "pool opens at the graduation target price");

        // The F-01 test: graduate directly. No swap, no executor, no adversary.
        (uint256 liq, uint256 burn) = curve.graduationLiquidityQuote();
        curve.graduate();

        assertTrue(curve.graduated(), "F-01 CLOSED: virgin-pool graduation completes unaided");
        assertEq(token.totalSupply(), supplyBefore - burn);
        assertEq(curve.ethReserve(), 0);
        assertEq(curve.tokenReserve(), 0);
        assertEq(token.balanceOf(address(curve)), 0);
        assertEq(token.balanceOf(address(launch)), 0);
        console2.log("C1 liquidity VOID:", liq);
        console2.log("C1 burned VOID:   ", burn);
        console2.log("C1 supply after:  ", token.totalSupply());
    }

    function testC1_SeedIsPriceNeutralAcrossManyBuyPatterns() public {
        for (uint256 i; i < 25; ++i) {
            _buy(alice, 1 ether);
        }
        _sell(alice, token.balanceOf(alice) / 10);
        for (uint256 i; i < 6; ++i) {
            _buy(bob, 1 ether);
        }
        assertTrue(curve.graduationReady());

        uint256 before = Math.mulDiv(VIRTUAL_ETH + curve.ethReserve(), 1e18, curve.tokenReserve());
        vm.prank(safe);
        curve.seedMigrationPool();
        uint256 after_ = Math.mulDiv(VIRTUAL_ETH + curve.ethReserve(), 1e18, curve.tokenReserve());
        assertEq(after_, before);
        _assertPriceClose(_poolPrice(), _target(), "pool matches target");
        curve.graduate();
        assertTrue(curve.graduated());
    }

    // =====================================================================
    // CONFIRMATION 2 & 5 — the executor, both directions
    // =====================================================================

    function testC2_PostSeedCurveBuyIsCorrectedAndGraduatesAtomically() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();

        // Exactly the review's 0.25 ETH case that previously reverted graduation.
        _buy(attacker, 0.25 ether);
        assertTrue(_poolPrice() != _target(), "pool is now stale relative to the curve");

        // Direct graduation still (correctly) fails.
        vm.expectRevert(VOIDBondingCurve.MigrationFailed.selector);
        curve.graduate();

        bool needsVoid = _correctionIsVoid();
        console2.log("C2 correction asset is VOID:", needsVoid);
        if (needsVoid) {
            _executeWith(bob, 0, token.balanceOf(bob));
        } else {
            _executeWith(bob, 60 ether, 0);
        }
        assertTrue(curve.graduated(), "F-02 CLOSED: correction + graduation in one transaction");
    }

    function testC2_PostSeedCurveSellIsCorrectedAndGraduatesAtomically() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();

        _sell(alice, token.balanceOf(alice) / 50);
        assertTrue(_poolPrice() != _target());

        vm.expectRevert(VOIDBondingCurve.MigrationFailed.selector);
        curve.graduate();

        bool needsVoid = _correctionIsVoid();
        console2.log("C2b correction asset is VOID:", needsVoid);
        if (needsVoid) {
            _executeWith(bob, 0, token.balanceOf(bob));
        } else {
            _executeWith(bob, 60 ether, 0);
        }
        assertTrue(curve.graduated());
    }

    function testC2_PoolSwappedAboveTargetIsCorrected() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();
        _movePoolBy(10_500, 10_000); // +5%
        assertGt(_poolPrice(), _target());
        _correctAndGraduate();
    }

    function testC2_PoolSwappedBelowTargetIsCorrected() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();
        _movePoolBy(9_500, 10_000); // -5%
        assertLt(_poolPrice(), _target());
        _correctAndGraduate();
    }

    function testC2_HostilePreInitializationIsCorrectedAndGraduates() public {
        _fundToThreshold();
        _hostileInit(4, 1); // attacker opens the pool at 4x the fair price
        vm.prank(safe);
        curve.seedMigrationPool();
        assertTrue(_poolPrice() != _target(), "hostile price survived the seed");

        vm.expectRevert(VOIDBondingCurve.MigrationFailed.selector);
        curve.graduate();

        _correctAndGraduate();
        console2.log("C2e hostile 4x pool corrected and graduated in one transaction");
    }

    function testC2_DirectGraduationWhenNoCorrectionIsNecessary() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();
        _assertPriceClose(_poolPrice(), _target(), "pool matches target");

        // The executor's documented no-op path is NOT reachable (see N-01): the
        // seed's floored caps leave a sub-ppb gap and the comparison is exact.
        vm.prank(bob);
        vm.expectRevert(VOIDGraduationExecutor.CorrectionAssetRequired.selector);
        executor.execute{value: 0}(0);

        // The supported route when no correction is economically needed is the
        // curve's own permissionless graduate(), which works.
        vm.prank(bob);
        curve.graduate();
        assertTrue(curve.graduated());
    }

    /// @dev Moves the pool price to `num/den` of the current target, modelling a
    ///      third-party swap through the pool.
    function _movePoolBy(uint256 num, uint256 den) internal {
        address pool = _poolAddr();
        uint160 want = uint160(Math.mulDiv(uint256(_target()), Math.sqrt(Math.mulDiv(num, 1e18, den)), 1e9));
        bool zeroForOne = want < ModelPool(pool).sqrtPriceX96();
        address tokenIn = zeroForOne ? ModelPool(pool).token0() : ModelPool(pool).token1();
        uint256 amount;
        if (tokenIn == address(weth)) {
            amount = 50 ether;
            weth.deposit{value: amount}();
        } else {
            amount = token.balanceOf(address(this));
            require(amount > 0, "test needs VOID");
        }
        (uint256 used, uint256 out, uint160 next) = ModelPool(pool).quoteSwap(zeroForOne, amount, want);
        IERC20(tokenIn).transfer(pool, used);
        ModelPool(pool).settleSwap(zeroForOne, next, out, address(this));
    }

    function _correctAndGraduate() internal {
        bool needsVoid = _correctionIsVoid();
        console2.log("correction asset is VOID:", needsVoid);
        if (needsVoid) {
            _executeWith(bob, 0, token.balanceOf(bob));
        } else {
            _executeWith(bob, 200 ether, 0);
        }
        assertTrue(curve.graduated());
    }

    // =====================================================================
    // CONFIRMATION 4 & 5 — executor safety
    // =====================================================================

    function testC4_InsufficientCorrectionRevertsWholeTransactionWithNoLoss() public {
        _fundToThreshold();
        _hostileInit(4, 1);
        vm.prank(safe);
        curve.seedMigrationPool();

        bool needsVoid = _correctionIsVoid();
        uint256 ethBefore = bob.balance;
        uint256 voidBefore;
        if (needsVoid) {
            voidBefore = token.balanceOf(bob);
            ethBefore = bob.balance;
            vm.prank(bob);
            token.approve(address(executor), type(uint256).max);
            vm.prank(bob);
            // Either CorrectionIncomplete or ZeroSwapOutput, depending on whether
            // the dust swap produces any output at all. Both revert everything.
            vm.expectRevert();
            executor.execute(1); // absurdly small correction budget
        } else {
            vm.prank(bob);
            vm.expectRevert();
            executor.execute{value: 1 wei}(0);
        }

        assertEq(bob.balance, ethBefore, "no ETH lost");
        assertEq(token.balanceOf(bob), voidBefore, "no VOID lost");
        assertFalse(curve.graduated());
        console2.log("C4a insufficient correction reverts cleanly; needsVoid =", needsVoid);
    }

    function testC4_WrongCorrectionAssetRevertsWithoutLoss() public {
        _fundToThreshold();
        _hostileInit(4, 1);
        vm.prank(safe);
        curve.seedMigrationPool();

        bool needsVoid = _correctionIsVoid();
        if (needsVoid) {
            // Caller supplies only ETH, but VOID is required.
            uint256 before = bob.balance;
            vm.prank(bob);
            vm.expectRevert(VOIDGraduationExecutor.CorrectionAssetRequired.selector);
            executor.execute{value: 5 ether}(0);
            assertEq(bob.balance, before);
        } else {
            uint256 before = token.balanceOf(bob);
            vm.prank(bob);
            token.approve(address(executor), before);
            vm.prank(bob);
            vm.expectRevert(VOIDGraduationExecutor.CorrectionAssetRequired.selector);
            executor.execute{value: 0}(before);
            assertEq(token.balanceOf(bob), before);
        }
    }

    function testC4_ExcessInputsAreFullyRefunded() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();
        _buy(attacker, 0.25 ether);

        bool needsVoid = _correctionIsVoid();
        uint256 ethBefore = bob.balance;
        uint256 voidBefore = token.balanceOf(bob);

        if (needsVoid) {
            _executeWith(bob, 0, voidBefore);
        } else {
            _executeWith(bob, 200 ether, 0);
        }
        assertTrue(curve.graduated());

        uint256 ethSpent = ethBefore - bob.balance;
        console2.log("C4c net ETH spent by corrector (wei):", ethSpent);
        console2.log("C4c VOID before:", voidBefore);
        console2.log("C4c VOID after: ", token.balanceOf(bob));

        // The executor must retain nothing.
        assertEq(token.balanceOf(address(executor)), 0, "executor retains no VOID");
        assertEq(weth.balanceOf(address(executor)), 0, "executor retains no WETH");
        assertEq(address(executor).balance, 0, "executor retains no ETH");
    }

    function testC4_ExecutorCannotSpendCurveReservesOrStealDonations() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();
        _buy(attacker, 0.25 ether);

        // Donate assets to the executor before anyone calls it.
        uint256 donatedVoid = 1_000 ether;
        token.transfer(address(executor), donatedVoid);
        EthForcer forcer = new EthForcer();
        forcer.forceTo{value: 3 ether}(payable(address(executor)));
        weth.deposit{value: 2 ether}();
        weth.transfer(address(executor), 2 ether);

        bool needsVoid = _correctionIsVoid();
        if (needsVoid) {
            _executeWith(bob, 0, token.balanceOf(bob));
        } else {
            _executeWith(bob, 200 ether, 0);
        }
        assertTrue(curve.graduated());

        // Donations are exactly preserved — neither stolen nor refunded to the caller.
        assertEq(token.balanceOf(address(executor)), donatedVoid, "donated VOID untouched");
        assertEq(address(executor).balance, 3 ether, "forced ETH untouched");
        assertEq(weth.balanceOf(address(executor)), 2 ether, "donated WETH untouched");
    }

    function testC4_ExecutorRouterAndVenueAreNotCallerSelectable() public view {
        // Everything the executor uses is derived from immutables or from the
        // Safe-controlled migration target. `execute` takes one uint256.
        assertEq(address(executor.swapRouter()), address(router));
        assertEq(address(executor.curve()), address(curve));
        assertEq(address(executor.token()), address(token));
    }

    function testC4_ExecutorCannotBeReenteredThroughTheEthRefund() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();
        _buy(attacker, 0.25 ether);

        if (_correctionIsVoid()) return; // this reentrancy path is ETH-refund specific

        ReentrantCaller rc = new ReentrantCaller(executor);
        vm.deal(address(rc), 60 ether);
        rc.go{value: 60 ether}();
        assertTrue(curve.graduated());
        assertTrue(rc.tried(), "reentrancy was attempted on the refund");
        assertFalse(rc.succeeded(), "reentrancy was blocked");
    }

    function testC4_DirectEthToTheExecutorIsRejected() public {
        (bool ok,) = address(executor).call{value: 1 ether}("");
        assertFalse(ok, "executor rejects ETH from anyone but WETH");
    }

    function testC4_DeeplyCapitalizedHostilePoolRevertsSafely() public {
        _fundToThreshold();
        _hostileInit(4, 1);

        // Attacker adds deep liquidity at the hostile price.
        address pool = manager.getPool(address(token), address(weth), POOL_FEE);
        _buy(attacker, 1 ether);
        uint256 atkVoid = token.balanceOf(attacker);
        vm.startPrank(attacker);
        weth.deposit{value: 500 ether}();
        token.transfer(pool, atkVoid);
        weth.transfer(pool, 500 ether);
        vm.stopPrank();
        ModelPool(pool).addLiquidity(type(uint96).max);

        vm.prank(safe);
        curve.seedMigrationPool();

        uint256 ethBefore = bob.balance;
        vm.prank(bob);
        vm.expectRevert();
        executor.execute{value: 1 ether}(0);
        assertEq(bob.balance, ethBefore, "caller loses nothing against a deep hostile pool");
        assertFalse(curve.graduated());
        console2.log("C4g deep hostile pool: correction reverts safely, no caller loss");
    }

    // =====================================================================
    // CONFIRMATION 3 & 6 — permissionless graduate cannot bypass the Safe
    // =====================================================================

    function testC3_GraduationFailsBeforeTheSafeSeeds() public {
        _fundToThreshold();
        assertFalse(curve.poolSeeded());

        vm.prank(attacker);
        vm.expectRevert(VOIDBondingCurve.PoolNotSeeded.selector);
        curve.graduate();

        vm.prank(attacker);
        vm.expectRevert(VOIDGraduationExecutor.GraduationUnavailable.selector);
        executor.execute{value: 1 ether}(0);
    }

    function testC3_OnlyTheSafeCanSeed() public {
        _fundToThreshold();
        vm.prank(attacker);
        vm.expectRevert();
        curve.seedMigrationPool();
        vm.prank(alice);
        vm.expectRevert();
        curve.seedMigrationPool();
    }

    function testC3_PendingMigrationTargetBlocksGraduation() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();
        _assertPriceClose(_poolPrice(), _target(), "pool matches target");

        VOIDUniswapV3Migration replacement =
            new VOIDUniswapV3Migration(IVOIDUniswapV3PositionManager(address(manager)), safe);
        vm.prank(safe);
        curve.proposeMigrationTarget(address(replacement));

        vm.prank(attacker);
        vm.expectRevert(VOIDBondingCurve.MigrationChangePending.selector);
        curve.graduate();

        // Cancelling restores the ability to graduate.
        vm.prank(safe);
        curve.cancelMigrationTarget();
        curve.graduate();
        assertTrue(curve.graduated());
    }

    function testC3_ReplacementAdapterCannotReuseThePriorSeed() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();
        assertEq(curve.seededMigrationTarget(), address(adapter));

        VOIDUniswapV3Migration replacement =
            new VOIDUniswapV3Migration(IVOIDUniswapV3PositionManager(address(manager)), safe);
        vm.prank(safe);
        curve.proposeMigrationTarget(address(replacement));
        vm.warp(block.timestamp + 2 days + 1);
        vm.prank(safe);
        curve.acceptMigrationTarget();

        // Seed is bound to the old target, so graduation is blocked.
        vm.prank(attacker);
        vm.expectRevert(VOIDBondingCurve.PoolNotSeeded.selector);
        curve.graduate();
        assertTrue(curve.poolSeeded(), "poolSeeded is still true, but bound to the old target");

        // A fresh Safe-authorised seed is required, and then it works.
        vm.prank(safe);
        curve.seedMigrationPool();
        assertEq(curve.seededMigrationTarget(), address(replacement));
        curve.graduate();
        assertTrue(curve.graduated());
    }

    function testC6_RepeatedTargetReplacementKeepsAccountingAndRedeemabilitySound() public {
        _fundToThreshold();

        uint256 priceStart = Math.mulDiv(VIRTUAL_ETH + curve.ethReserve(), 1e18, curve.tokenReserve());
        for (uint256 i; i < 5; ++i) {
            vm.prank(safe);
            curve.seedMigrationPool();

            // Accounting invariants after every seed.
            assertGe(address(curve).balance, curve.ethReserve(), "eth fully backed");
            assertGe(token.balanceOf(address(curve)), curve.tokenReserve(), "tokens fully backed");
            uint256 outstanding = token.LAUNCH_ALLOCATION() - curve.tokenReserve()
                - (token.LAUNCH_ALLOCATION() - curve.tokenReserve() - _heldByPublic());
            outstanding;
            assertGe(curve.maxSellable(), _heldByPublic(), "full public float still redeemable");
            _assertPriceClose(_poolPrice(), _target(), "pool still matches the live target");

            VOIDUniswapV3Migration next =
                new VOIDUniswapV3Migration(IVOIDUniswapV3PositionManager(address(manager)), safe);
            vm.prank(safe);
            curve.proposeMigrationTarget(address(next));
            vm.warp(block.timestamp + 2 days + 1);
            vm.prank(safe);
            curve.acceptMigrationTarget();
        }

        uint256 priceEnd = Math.mulDiv(VIRTUAL_ETH + curve.ethReserve(), 1e18, curve.tokenReserve());
        console2.log("C6 curve price after 5 seeds, start:", priceStart);
        console2.log("C6 curve price after 5 seeds, end:  ", priceEnd);
        assertEq(priceEnd, priceStart, "repeated seeding is price-neutral");

        vm.prank(safe);
        curve.seedMigrationPool();
        curve.graduate();
        assertTrue(curve.graduated());
        assertEq(curve.ethReserve(), 0);
        assertEq(curve.tokenReserve(), 0);
        assertEq(token.balanceOf(address(curve)), 0);
    }

    function _heldByPublic() internal view returns (uint256) {
        return token.totalSupply() - token.balanceOf(address(curve)) - token.balanceOf(address(vesting));
    }

    function testC3_PermissionlessCallerCannotRedirectAssetsOrCustody() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();

        // graduate() takes no arguments; the recipient is immutable on the curve.
        vm.prank(attacker);
        curve.graduate();
        assertTrue(curve.graduated());
        assertEq(curve.positionRecipient(), address(locker), "custody is immutable");

        // Every minted position is owned and registered by the locker.
        uint256 lastId = manager.nextTokenId() - 1;
        assertEq(manager.ownerOf(lastId), address(locker));
        assertTrue(locker.isRegisteredPosition(lastId, address(adapter)));
        assertEq(locker.beneficiary(), safe, "beneficiary is immutable");
    }

    // =====================================================================
    // CONFIRMATION 7 — L3-01 Safe ERC-721 gate
    // =====================================================================

    function testC7_DeployGateAcceptsARealSafeFallbackHandler() public view {
        (bool ok, bytes memory ret) = safe.staticcall(
            abi.encodeCall(IERC721Receiver.onERC721Received, (address(this), address(this), 0, ""))
        );
        assertTrue(ok, "staticcall through the Safe fallback succeeds");
        assertGe(ret.length, 32);
        assertEq(abi.decode(ret, (bytes4)), IERC721Receiver.onERC721Received.selector);
    }

    function testC7_DeployGateRejectsAHandlerLessSafe() public {
        address bare = address(new ModelSafe(address(0)));
        (bool ok, bytes memory ret) = bare.staticcall(
            abi.encodeCall(IERC721Receiver.onERC721Received, (address(this), address(this), 0, ""))
        );
        // A handler-less Safe returns success with EMPTY data — the length check is
        // what actually rejects it, not the success flag.
        assertTrue(ok, "handler-less Safe still returns success");
        assertEq(ret.length, 0, "but with no returndata, so the require fails");

        // And such a beneficiary really does strand the position.
        VOIDPositionLocker bareLocker = new VOIDPositionLocker(IERC721(address(manager)), bare);
        ThrowawayToken tt = new ThrowawayToken(address(this), 1_000_000 ether);
        VOIDUniswapV3Migration a2 =
            new VOIDUniswapV3Migration(IVOIDUniswapV3PositionManager(address(manager)), address(this));
        tt.approve(address(a2), 1_000_000 ether);
        a2.seed{value: 1 ether}(address(tt), 1_000_000 ether, address(bareLocker));
        uint256 id = manager.nextTokenId() - 1;
        vm.warp(block.timestamp + 366 days);
        vm.expectRevert();
        bareLocker.release(id);
    }

    /// @notice The gate is a deployment-time snapshot only. Safe owners can remove
    ///         the fallback handler afterwards and permanently strand the LP.
    function testC7_GateIsOnlyADeploymentTimeSnapshot() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();
        curve.graduate();
        uint256 id = manager.nextTokenId() - 1;

        // Safe owners later remove the fallback handler.
        ModelSafe(payable(safe)).setHandler(address(0));

        vm.warp(block.timestamp + 366 days);
        vm.expectRevert();
        locker.release(id);
        console2.log("C7c LP release breaks if the Safe's handler is removed post-deployment");
    }

    // =====================================================================
    // CONFIRMATION 8 — prior security properties
    // =====================================================================

    function testC8_ForcedEthAndDonatedTokensCannotCorruptGraduation() public {
        _fundToThreshold();
        EthForcer forcer = new EthForcer();
        forcer.forceTo{value: 40 ether}(payable(address(curve)));
        _buy(address(this), 1 ether);
        uint256 donate = 500_000 ether;
        token.transfer(address(curve), donate);

        vm.prank(safe);
        curve.seedMigrationPool();
        _assertPriceClose(_poolPrice(), _target(), "donations did not move the accounted target");
        curve.graduate();

        assertEq(curve.ethReserve(), 0);
        assertEq(curve.tokenReserve(), 0);
        assertEq(address(curve).balance, 40 ether, "forced ETH isolated and sweepable");
        assertEq(token.balanceOf(address(curve)), donate, "donated VOID isolated and sweepable");
        vm.prank(safe);
        curve.sweepExcess(payable(safe));
        assertEq(address(curve).balance, 0);
        assertEq(token.balanceOf(address(curve)), 0);
    }

    function testC8_FailedSeedRollsBackCompletely() public {
        _fundToThreshold();
        uint256 e = curve.ethReserve();
        uint256 t = curve.tokenReserve();
        uint256 supply = token.totalSupply();

        // A hostile pool so deep that the seed's own mint reverts is not reachable,
        // so instead break the adapter by pointing at a target with no code path.
        // Here we assert the simpler property: a reverted graduate changes nothing.
        _hostileInit(4, 1);
        vm.prank(safe);
        curve.seedMigrationPool(); // succeeds: seed has no minimums, by design

        vm.expectRevert(VOIDBondingCurve.MigrationFailed.selector);
        curve.graduate();

        assertEq(token.totalSupply(), supply, "no supply burned");
        assertFalse(curve.graduated());
        assertLe(curve.ethReserve(), e);
        assertLe(curve.tokenReserve(), t);
        // Trading still works both ways.
        uint256 got = _buy(bob, 0.5 ether);
        _sell(bob, got);
    }

    function testC8_BuyerTreasuryAndUnrelatedBalancesCannotBeBurned() public {
        _fundToThreshold();
        uint256 aliceBefore = token.balanceOf(alice);
        uint256 treasuryBefore = token.balanceOf(address(vesting));

        vm.prank(alice);
        vm.expectRevert(VOIDCoin.OnlyLaunchReceiver.selector);
        token.burnLaunchReserve(1);
        vm.prank(safe);
        vm.expectRevert(VOIDCoin.OnlyLaunchReceiver.selector);
        token.burnLaunchReserve(1);
        vm.prank(address(executor));
        vm.expectRevert(VOIDCoin.OnlyLaunchReceiver.selector);
        token.burnLaunchReserve(1);
        vm.prank(attacker);
        vm.expectRevert(VOIDLaunch.OnlyBondingCurve.selector);
        launch.burnCurveExcess(1);

        vm.prank(safe);
        curve.seedMigrationPool();
        curve.graduate();

        assertEq(token.balanceOf(alice), aliceBefore);
        assertEq(token.balanceOf(address(vesting)), treasuryBefore);
    }

    function testC8_SupplyCannotIncreaseAndMetadataNeedsBurnPlusSafe() public {
        assertEq(token.totalSupply(), token.ORIGINAL_SUPPLY());
        vm.prank(safe);
        token.setRenamePaused(false);
        for (uint256 i; i < 5; ++i) {
            _buy(alice, 1 ether);
        }

        // No slot: approval impossible.
        vm.prank(safe);
        vm.expectRevert(VOIDCoin.NoActiveSlot.selector);
        token.approveRename(1, "Name", "NAME", "ipfs://x", keccak256("i"), keccak256("s"));

        uint256 amount = token.nextBurnRequirement();
        uint256 burnId = token.nextBurnId();
        string memory uri = "ipfs://ok";
        bytes32 ih = keccak256("i");
        bytes32 salt = keccak256("s");
        bytes32 c =
            token.proposalCommitment(burnId, alice, amount, "Night Shift", "NIGHT", ih, keccak256(bytes(uri)), salt);
        vm.prank(alice);
        token.burnForRename(amount, c);

        vm.prank(alice);
        vm.expectRevert();
        token.approveRename(burnId, "Night Shift", "NIGHT", uri, ih, salt);
        assertEq(token.name(), "VOIDCOIN");

        vm.prank(safe);
        token.approveRename(burnId, "Night Shift", "NIGHT", uri, ih, salt);
        assertEq(token.name(), "Night Shift");
        assertLt(token.totalSupply(), token.ORIGINAL_SUPPLY());
    }

    function testFuzzC8_FullFloatRedeemableBeforeGraduation(uint8 buys, uint96 sellSeed) public {
        uint256 n = bound(uint256(buys), 1, 40);
        for (uint256 i; i < n; ++i) {
            _buy(alice, 1 ether);
        }
        uint256 amt = bound(uint256(sellSeed), 1, token.balanceOf(alice));
        if (amt <= curve.maxSellable()) {
            uint256 q = curve.quoteSell(amt);
            if (q > 0) _sell(alice, amt);
        }
        assertGe(curve.maxSellable(), _heldByPublic(), "entire public float redeemable");
        assertGe(address(curve).balance, curve.ethReserve());
        assertLe(token.totalSupply(), token.ORIGINAL_SUPPLY());
    }

    // =====================================================================
    // NEW FINDING N-01 \u2014 the executor cannot handle the benign case
    // =====================================================================

    /// @notice After a clean virgin seed with no trading and no adversary, the
    ///         pool price is NOT bit-identical to the executor's target: the seed
    ///         caps are floored, so a sub-part-per-billion gap remains. The
    ///         executor compares with EXACT equality, so its "no correction
    ///         needed" fast path never triggers and it demands a correction asset.
    function testN01_ExecutorDemandsCorrectionEvenWhenNothingIsWrong() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();

        uint160 pool = _poolPrice();
        uint160 target = _target();
        assertTrue(pool != target, "seed leaves a sub-ppb gap");
        uint256 hi = pool > target ? pool : target;
        uint256 lo = pool > target ? target : pool;
        console2.log("N-01 pool sqrtPriceX96  :", pool);
        console2.log("N-01 target sqrtPriceX96:", target);
        console2.log("N-01 absolute gap       :", hi - lo);
        console2.log("N-01 gap in parts per 1e18:", Math.mulDiv(hi - lo, 1e18, hi));

        // The documented "no correction necessary" path reverts.
        vm.prank(bob);
        vm.expectRevert(VOIDGraduationExecutor.CorrectionAssetRequired.selector);
        executor.execute{value: 0}(0);
    }

    /// @notice And supplying a generous correction budget in the correct direction
    ///         does not help either: the required swap is dust, so it produces no
    ///         output and the executor reverts ZeroSwapOutput.
    /// @notice A generous correction budget DOES close the sub-ppb gap, so the
    ///         impact is bounded: the caller must always supply a correction asset
    ///         and guess the direction, but graduation still completes.
    function testN01_ASuppliedBudgetDoesCloseTheSubPpbGap() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();

        bool needsVoid = _correctionIsVoid();
        console2.log("N-01b correction asset is VOID:", needsVoid);
        uint256 ethBefore = bob.balance;
        uint256 voidBefore = token.balanceOf(bob);

        if (needsVoid) {
            _executeWith(bob, 0, voidBefore);
            console2.log("N-01b VOID consumed to close a sub-ppb gap:", voidBefore - token.balanceOf(bob));
        } else {
            _executeWith(bob, 200 ether, 0);
            console2.log("N-01b ETH consumed to close a sub-ppb gap (wei):", ethBefore - bob.balance);
        }
        assertTrue(curve.graduated(), "graduation completes once a budget is supplied");
    }

    /// @notice Supplying BOTH assets is the safe caller pattern: the executor pulls
    ///         only the one it needs and never touches the other.
    function testN01_SupplyingBothAssetsAlwaysWorks() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();
        _buy(attacker, 0.25 ether);

        uint256 voidBefore = token.balanceOf(bob);
        vm.prank(bob);
        token.approve(address(executor), voidBefore);
        vm.prank(bob);
        executor.execute{value: 200 ether}(voidBefore);
        assertTrue(curve.graduated());
        assertEq(token.balanceOf(address(executor)), 0);
        assertEq(address(executor).balance, 0);
        assertEq(weth.balanceOf(address(executor)), 0);
    }

    // =====================================================================
    // New finding \u2014 WETH9's 2300-gas stipend vs the executor's receive()
    // =====================================================================

    /// @notice Base's WETH9 `withdraw` uses `transfer`, giving the recipient only
    ///         2300 gas. The executor's receive() makes TWO external calls before
    ///         accepting. This measures the actual headroom.
    function testGas_ExecutorReceiveUnderTheWeth9Stipend() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();
        _buy(attacker, 0.25 ether);
        if (_correctionIsVoid()) return;

        // Warm the curve and adapter exactly as execute() does before the refund,
        // then measure the executor's receive() path.
        curve.migrationTarget();
        adapter.weth9();
        address(executor).call{value: 0}("");
        uint256 gasBefore = gasleft();
        (bool ok,) = address(executor).call{value: 0}("");
        uint256 used = gasBefore - gasleft();
        ok;
        console2.log("Gas for executor.receive() with everything warm:", used);
        console2.log("WETH9 transfer() stipend is 2300; headroom:", used < 2300 ? 2300 - used : 0);

        // The real check: a refund through Base-style WETH must not run out of gas.
        _executeWith(bob, 60 ether, 0);
        assertTrue(curve.graduated(), "ETH refund survived the 2300-gas stipend");
    }

    /// @dev Control: same flow against a WETH that forwards all gas.
    function testGas_ControlWithGenerousWeth() public {
        GenerousWETH9 gw = new GenerousWETH9();
        ModelPositionManager m2 = new ModelPositionManager(address(gw));
        ModelSwapRouter02 r2 = new ModelSwapRouter02(m2);
        VOIDUniswapV3Migration a2 = new VOIDUniswapV3Migration(IVOIDUniswapV3PositionManager(address(m2)), safe);
        VOIDPositionLocker l2 = new VOIDPositionLocker(IERC721(address(m2)), safe);
        VOIDLaunch lz = new VOIDLaunch(safe, address(a2), address(l2), VIRTUAL_ETH, GRAD_THRESHOLD, "ipfs://g");
        VOIDBondingCurve c2 = lz.bondingCurve();
        VOIDGraduationExecutor e2 =
            new VOIDGraduationExecutor(IVOIDGraduationCurve(address(c2)), IVOIDGraduationRouter(address(r2)));
        for (uint256 i; i < 25; ++i) {
            uint256 q = c2.quoteBuy(1 ether);
            vm.prank(alice);
            c2.buy{value: 1 ether}(q, block.timestamp);
        }
        vm.prank(safe);
        c2.seedMigrationPool();
        uint256 q2 = c2.quoteBuy(0.25 ether);
        vm.prank(attacker);
        c2.buy{value: 0.25 ether}(q2, block.timestamp);

        bool tokenIsToken0 = address(lz.token()) < address(gw);
        address t1 = tokenIsToken0 ? address(gw) : address(lz.token());
        address pool = m2.getPool(address(lz.token()), address(gw), POOL_FEE);
        bool needsVoid = (ModelPool(pool).sqrtPriceX96() > e2.targetSqrtPriceX96(address(gw))
            ? (tokenIsToken0 ? address(lz.token()) : address(gw))
            : t1) == address(lz.token());
        if (needsVoid) return;
        vm.prank(bob);
        e2.execute{value: 60 ether}(0);
        assertTrue(c2.graduated());
    }
}

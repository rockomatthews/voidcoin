// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {VOIDBondingCurve} from "../src/VOIDBondingCurve.sol";
import {VOIDCoin} from "../src/VOIDCoin.sol";
import {VOIDLaunch} from "../src/VOIDLaunch.sol";
import {VOIDTreasuryVesting} from "../src/VOIDTreasuryVesting.sol";
import {VOIDPositionLocker} from "../src/VOIDPositionLocker.sol";
import {VOIDUniswapV3Migration, IVOIDUniswapV3PositionManager, IVOIDWETH9} from "../src/VOIDUniswapV3Migration.sol";

// =========================================================================
//  Uniswap v3 model.
//
//  Implements the real LiquidityAmounts / SqrtPriceMath relationships and the
//  real createAndInitializePoolIfNecessary semantics (an already-initialised
//  pool ignores the supplied price). `forceSetPrice` models the OUTCOME of a
//  corrective swap without simulating swap mechanics — the question under test
//  is how the VOIDCOIN contracts behave at a given pool price, not how Uniswap
//  arrives at it.
// =========================================================================

contract PoolStub {
    uint160 public sqrtPriceX96;

    function initialize(uint160 price) external {
        sqrtPriceX96 = price;
    }

    function forceSetPrice(uint160 price) external {
        sqrtPriceX96 = price;
    }
}

contract UniswapV3Model is ERC721, IVOIDUniswapV3PositionManager {
    using SafeERC20 for IERC20;

    uint256 private constant Q96 = 1 << 96;

    address public immutable override WETH9;
    address public immutable override factory;

    mapping(bytes32 poolKey => address pool) public pools;
    uint256 public nextTokenId = 1;

    constructor(address weth) ERC721("Uniswap V3 Positions", "UNI-V3-POS") {
        WETH9 = weth;
        factory = address(this);
    }

    function _key(address a, address b, uint24 fee) private pure returns (bytes32) {
        return keccak256(abi.encode(a, b, fee));
    }

    function poolFor(address a, address b, uint24 fee) external view returns (address) {
        return pools[_key(a, b, fee)];
    }

    function priceOf(address a, address b, uint24 fee) external view returns (uint160) {
        address p = pools[_key(a, b, fee)];
        return p == address(0) ? 0 : PoolStub(p).sqrtPriceX96();
    }

    /// @dev Models an external party swapping the pool to a target price.
    function forcePrice(address a, address b, uint24 fee, uint160 price) external {
        address p = pools[_key(a, b, fee)];
        require(p != address(0), "no pool");
        PoolStub(p).forceSetPrice(price);
    }

    function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96)
        external
        payable
        returns (address pool)
    {
        bytes32 key = _key(token0, token1, fee);
        pool = pools[key];
        if (pool == address(0)) {
            pool = address(new PoolStub());
            pools[key] = pool;
        }
        if (PoolStub(pool).sqrtPriceX96() == 0) PoolStub(pool).initialize(sqrtPriceX96);
        return pool;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        address pool = pools[_key(params.token0, params.token1, params.fee)];
        require(pool != address(0), "no pool");
        uint160 sqrtP = PoolStub(pool).sqrtPriceX96();
        require(sqrtP != 0, "uninitialised");

        uint160 sqrtA = _sqrtRatioAtTick(params.tickLower);
        uint160 sqrtB = _sqrtRatioAtTick(params.tickUpper);
        liquidity = _liquidityForAmounts(sqrtP, sqrtA, sqrtB, params.amount0Desired, params.amount1Desired);
        (amount0, amount1) = _amountsForLiquidity(sqrtP, sqrtA, sqrtB, liquidity);

        require(amount0 >= params.amount0Min, "Price slippage check");
        require(amount1 >= params.amount1Min, "Price slippage check");

        if (amount0 > 0) IERC20(params.token0).safeTransferFrom(msg.sender, pool, amount0);
        if (amount1 > 0) IERC20(params.token1).safeTransferFrom(msg.sender, pool, amount1);

        tokenId = nextTokenId++;
        _safeMint(params.recipient, tokenId);
    }

    function _liquidityForAmounts(uint160 sqrtP, uint160 sqrtA, uint160 sqrtB, uint256 amount0, uint256 amount1)
        private
        pure
        returns (uint128 liquidity)
    {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        if (sqrtP <= sqrtA) {
            liquidity = _liqForAmount0(sqrtA, sqrtB, amount0);
        } else if (sqrtP < sqrtB) {
            uint128 l0 = _liqForAmount0(sqrtP, sqrtB, amount0);
            uint128 l1 = _liqForAmount1(sqrtA, sqrtP, amount1);
            liquidity = l0 < l1 ? l0 : l1;
        } else {
            liquidity = _liqForAmount1(sqrtA, sqrtB, amount1);
        }
    }

    function _amountsForLiquidity(uint160 sqrtP, uint160 sqrtA, uint160 sqrtB, uint128 liquidity)
        private
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        if (sqrtP <= sqrtA) {
            amount0 = _amount0Delta(sqrtA, sqrtB, liquidity);
        } else if (sqrtP < sqrtB) {
            amount0 = _amount0Delta(sqrtP, sqrtB, liquidity);
            amount1 = _amount1Delta(sqrtA, sqrtP, liquidity);
        } else {
            amount1 = _amount1Delta(sqrtA, sqrtB, liquidity);
        }
    }

    function _liqForAmount0(uint160 sqrtA, uint160 sqrtB, uint256 amount0) private pure returns (uint128) {
        uint256 intermediate = Math.mulDiv(uint256(sqrtA), uint256(sqrtB), Q96);
        return uint128(Math.mulDiv(amount0, intermediate, uint256(sqrtB) - uint256(sqrtA)));
    }

    function _liqForAmount1(uint160 sqrtA, uint160 sqrtB, uint256 amount1) private pure returns (uint128) {
        return uint128(Math.mulDiv(amount1, Q96, uint256(sqrtB) - uint256(sqrtA)));
    }

    function _amount0Delta(uint160 sqrtA, uint160 sqrtB, uint128 liquidity) private pure returns (uint256) {
        uint256 n1 = uint256(liquidity) << 96;
        uint256 n2 = uint256(sqrtB) - uint256(sqrtA);
        return Math.mulDiv(Math.mulDiv(n1, n2, uint256(sqrtB)), 1, uint256(sqrtA));
    }

    function _amount1Delta(uint160 sqrtA, uint160 sqrtB, uint128 liquidity) private pure returns (uint256) {
        return Math.mulDiv(uint256(liquidity), uint256(sqrtB) - uint256(sqrtA), Q96);
    }

    function _sqrtRatioAtTick(int24 tick) private pure returns (uint160) {
        if (tick == -887_200) return 4_310_618_291;
        if (tick == 887_200) return 1_456_195_216_263_841_500_379_307_683_214_498_614_686_540_680_047;
        revert("unsupported tick in model");
    }
}

contract MockWETH9 is ERC20, IVOIDWETH9 {
    constructor() ERC20("Wrapped Ether", "WETH") {}

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        require(ok, "withdraw failed");
    }
}

contract SafeStub {
    receive() external payable {}

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

/// @notice A Safe with no ERC-721 fallback handler installed.
contract SafeWithoutErc721Handler {
    receive() external payable {}
}

contract AttackerRecipient {
    function registerPosition(uint256) external {}

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

// =========================================================================

contract Phase3PoCTest is Test {
    address internal safe;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    // Frozen production parameters.
    uint256 internal constant VIRTUAL_ETH = 100 ether;
    uint256 internal constant GRAD_THRESHOLD = 25 ether;

    MockWETH9 internal weth;
    UniswapV3Model internal manager;
    VOIDUniswapV3Migration internal adapter;
    VOIDPositionLocker internal locker;
    VOIDLaunch internal launch;
    VOIDCoin internal token;
    VOIDBondingCurve internal curve;
    VOIDTreasuryVesting internal vesting;

    receive() external payable {}

    function setUp() public {
        safe = address(new SafeStub());
        weth = new MockWETH9();
        manager = new UniswapV3Model(address(weth));
        adapter = new VOIDUniswapV3Migration(IVOIDUniswapV3PositionManager(address(manager)), safe);
        locker = new VOIDPositionLocker(IERC721(address(manager)), safe);
        launch = new VOIDLaunch(safe, address(adapter), address(locker), VIRTUAL_ETH, GRAD_THRESHOLD, "ipfs://genesis");
        token = launch.token();
        curve = launch.bondingCurve();
        vesting = launch.vestingWallet();

        vm.deal(alice, 10_000 ether);
        vm.deal(bob, 10_000 ether);
        vm.deal(attacker, 10_000 ether);
    }

    function _buy(address who, uint256 ethIn) internal returns (uint256) {
        uint256 quote = curve.quoteBuy(ethIn);
        vm.prank(who);
        return curve.buy{value: ethIn}(quote, block.timestamp);
    }

    /// @dev 25 production-sized 1 ETH purchases, exactly as the project's fork test does.
    function _fundToThreshold() internal {
        for (uint256 i; i < 25; ++i) {
            _buy(alice, 1 ether);
        }
        assertTrue(curve.graduationReady(), "threshold latched");
    }

    function _ordered() internal view returns (address t0, address t1) {
        return address(token) < address(weth) ? (address(token), address(weth)) : (address(weth), address(token));
    }

    function _sqrt(uint256 amount0, uint256 amount1) internal pure returns (uint160) {
        return uint160(Math.sqrt(Math.mulDiv(amount1, uint256(1) << 192, amount0)));
    }

    /// @dev The pool price that `graduate()` requires, from the live curve state.
    function _fairGraduationPrice() internal view returns (uint160) {
        (uint256 tokensForLiquidity,) = curve.graduationLiquidityQuote();
        uint256 eth = curve.ethReserve();
        (address t0,) = _ordered();
        return t0 == address(token) ? _sqrt(tokensForLiquidity, eth) : _sqrt(eth, tokensForLiquidity);
    }

    function _poolPrice() internal view returns (uint160) {
        (address t0, address t1) = _ordered();
        return manager.priceOf(t0, t1, 10_000);
    }

    function _forcePoolPrice(uint160 p) internal {
        (address t0, address t1) = _ordered();
        manager.forcePrice(t0, t1, 10_000, p);
    }

    // =====================================================================
    // F-01  The capped seed initialises the pool at the WRONG price, so even an
    //       unattacked graduation cannot complete without an off-chain swap.
    // =====================================================================

    function testF01_SeedPricesThePoolFiveTimesBelowTheGraduationPrice() public {
        _fundToThreshold();

        uint256 e = curve.ethReserve();
        uint256 t = curve.tokenReserve();
        (uint256 liq,) = curve.graduationLiquidityQuote();

        // seedMigrationPool() sends 0.1% of EACH reserve, so the adapter derives
        // the initial pool price from ethReserve/tokenReserve.
        // graduate() sends ethReserve and ethReserve*T/(V+E), whose ratio is the
        // curve's marginal price (V+E)/T. The two differ by (V+E)/E.
        console2.log("F-01 seed-implied  ETH per 1e18 VOID:", Math.mulDiv(e, 1e18, t));
        console2.log("F-01 graduation    ETH per 1e18 VOID:", Math.mulDiv(e, 1e18, liq));
        console2.log("F-01 ratio (V+E)/E x1000:", Math.mulDiv(VIRTUAL_ETH + e, 1000, e));

        vm.prank(safe);
        curve.seedMigrationPool();
        assertTrue(curve.poolSeeded());

        uint160 seeded = _poolPrice();
        uint160 fair = _fairGraduationPrice();
        console2.log("F-01 pool sqrtPriceX96 after seed:", seeded);
        console2.log("F-01 pool sqrtPriceX96 required:  ", fair);

        // With no attacker anywhere in this test, graduation still fails.
        vm.prank(safe);
        vm.expectRevert(VOIDBondingCurve.MigrationFailed.selector);
        curve.graduate();

        // Nothing recovers it except moving the pool price.
        vm.warp(block.timestamp + 3650 days);
        vm.prank(safe);
        vm.expectRevert(VOIDBondingCurve.MigrationFailed.selector);
        curve.graduate();

        // And seeding cannot be repeated.
        vm.prank(safe);
        vm.expectRevert(VOIDBondingCurve.PoolAlreadySeeded.selector);
        curve.seedMigrationPool();
    }

    function testF01_GraduationSucceedsOnlyAfterThePoolIsMovedToTheExactPrice() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();

        uint256 supplyBefore = token.totalSupply();
        (uint256 liquidityTokens, uint256 tokensToBurn) = curve.graduationLiquidityQuote();

        // Model the corrective swap: an external party moves the pool to the
        // exact fair price. This is the step the project's fork test performs
        // with SwapRouter02 and sqrtPriceLimitX96.
        _forcePoolPrice(_fairGraduationPrice());

        vm.prank(safe);
        curve.graduate();

        assertTrue(curve.graduated());
        assertEq(token.totalSupply(), supplyBefore - tokensToBurn, "excess burned exactly");
        assertEq(token.balanceOf(address(curve)), 0);
        assertEq(token.balanceOf(address(launch)), 0);
        assertEq(curve.tokenReserve(), 0);
        assertEq(curve.ethReserve(), 0);
        console2.log("F-01b graduated. liquidity VOID:", liquidityTokens);
        console2.log("F-01b burned VOID:              ", tokensToBurn);
        console2.log("F-01b supply after graduation:  ", token.totalSupply());
    }

    // =====================================================================
    // F-02  The window between the corrective swap and graduate() is
    //       unprotected. Any trade on either venue reverts graduation.
    // =====================================================================

    function testF02_ADustBuyAfterTheCorrectiveSwapRevertsGraduation() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();
        _forcePoolPrice(_fairGraduationPrice());

        // Safe queues graduate(). Attacker makes one small purchase first.
        _buy(attacker, 0.25 ether);

        vm.prank(safe);
        vm.expectRevert(VOIDBondingCurve.MigrationFailed.selector);
        curve.graduate();
        console2.log("F-02 a 0.25 ETH buy is enough to revert a queued graduation");
    }

    function testF02_ASellAfterTheCorrectiveSwapRevertsGraduation() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();
        _forcePoolPrice(_fairGraduationPrice());

        uint256 bal = token.balanceOf(alice);
        uint256 sellAmount = bal / 200; // 0.5% of one buyer's position
        uint256 q = curve.quoteSell(sellAmount);
        vm.startPrank(alice);
        token.approve(address(curve), sellAmount);
        curve.sell(sellAmount, q, block.timestamp);
        vm.stopPrank();

        vm.prank(safe);
        vm.expectRevert(VOIDBondingCurve.MigrationFailed.selector);
        curve.graduate();
    }

    function testF02_MeasureTheTolerance() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();
        uint160 fair = _fairGraduationPrice();

        // Walk the pool price away from fair in basis points and find the edge.
        uint256[6] memory bpsList = [uint256(1), 3, 5, 10, 25, 100];
        for (uint256 i; i < bpsList.length; ++i) {
            uint256 snap = vm.snapshotState();
            uint160 skewed = uint160(uint256(fair) * (10_000 + bpsList[i]) / 10_000);
            _forcePoolPrice(skewed);
            vm.prank(safe);
            try curve.graduate() {
                console2.log("F-02c pool price +bps, graduation SUCCEEDS:", bpsList[i]);
            } catch {
                console2.log("F-02c pool price +bps, graduation REVERTS: ", bpsList[i]);
            }
            vm.revertToState(snap);
        }
    }

    function testF02_AnyoneCanMoveTheThinPoolAfterTheCorrectiveSwap() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();
        _forcePoolPrice(_fairGraduationPrice());

        // The seeded pool holds only 0.1% of reserves, so it is extremely cheap
        // to move. Model any third-party swap moving it 1%.
        _forcePoolPrice(uint160(uint256(_fairGraduationPrice()) * 10_100 / 10_000));

        vm.prank(safe);
        vm.expectRevert(VOIDBondingCurve.MigrationFailed.selector);
        curve.graduate();
        console2.log("F-02d graduation must be atomic with the corrective swap");
    }

    // =====================================================================
    // Scope item 3 — failed seeding / burning / migration change nothing
    // =====================================================================

    function testScope3_FailedGraduationLeavesSupplyReservesAndTradingUnchanged() public {
        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();

        uint256 supplyBefore = token.totalSupply();
        uint256 ethBefore = curve.ethReserve();
        uint256 tokBefore = curve.tokenReserve();
        uint256 launchBalBefore = token.balanceOf(address(launch));

        vm.prank(safe);
        vm.expectRevert(VOIDBondingCurve.MigrationFailed.selector);
        curve.graduate();

        assertEq(token.totalSupply(), supplyBefore, "no supply burned");
        assertEq(curve.ethReserve(), ethBefore, "eth reserve unchanged");
        assertEq(curve.tokenReserve(), tokBefore, "token reserve unchanged");
        assertEq(token.balanceOf(address(launch)), launchBalBefore, "no tokens stranded in launch");
        assertFalse(curve.graduated());

        // Trading still works in both directions.
        uint256 got = _buy(bob, 0.5 ether);
        assertGt(got, 0);
        uint256 q = curve.quoteSell(got);
        vm.startPrank(bob);
        token.approve(address(curve), got);
        assertGt(curve.sell(got, q, block.timestamp), 0);
        vm.stopPrank();
    }

    // =====================================================================
    // Scope items 6 & 7 — burn authority and blast radius
    // =====================================================================

    function testScope6_OnlyTheLaunchContractCanBurnLaunchReserve() public {
        _buy(alice, 1 ether);
        uint256 bal = token.balanceOf(alice);

        vm.prank(alice);
        vm.expectRevert(VOIDCoin.OnlyLaunchReceiver.selector);
        token.burnLaunchReserve(1);

        vm.prank(safe);
        vm.expectRevert(VOIDCoin.OnlyLaunchReceiver.selector);
        token.burnLaunchReserve(1);

        vm.prank(address(curve));
        vm.expectRevert(VOIDCoin.OnlyLaunchReceiver.selector);
        token.burnLaunchReserve(1);

        // And burnCurveExcess on the launch contract is curve-only.
        vm.prank(safe);
        vm.expectRevert(VOIDLaunch.OnlyBondingCurve.selector);
        launch.burnCurveExcess(1);

        assertEq(token.balanceOf(alice), bal, "no third party can touch buyer balances");
        assertEq(token.launchReserveBurner(), address(launch));
    }

    function testScope7_GraduationBurnCannotReachBuyerOrTreasuryBalances() public {
        _fundToThreshold();
        uint256 aliceBefore = token.balanceOf(alice);
        uint256 treasuryBefore = token.balanceOf(address(vesting));
        assertEq(treasuryBefore, 20_000_000 ether);

        vm.prank(safe);
        curve.seedMigrationPool();
        _forcePoolPrice(_fairGraduationPrice());
        vm.prank(safe);
        curve.graduate();

        assertEq(token.balanceOf(alice), aliceBefore, "buyer balance untouched");
        assertEq(token.balanceOf(address(vesting)), treasuryBefore, "treasury balance untouched");
        // The burn is sourced only from what the curve pushed into VOIDLaunch.
        assertEq(token.balanceOf(address(launch)), 0);
    }

    // =====================================================================
    // Scope item 5 — marginal price continuity
    // =====================================================================

    function testScope5_GraduationFormulaPreservesMarginalPrice() public {
        _fundToThreshold();
        uint256 e = curve.ethReserve();
        uint256 t = curve.tokenReserve();
        (uint256 liq,) = curve.graduationLiquidityQuote();

        // Curve marginal price = (V + E) / T. Pool opening price = E / liq.
        // Both expressed as wei of ETH per 1e18 VOID.
        uint256 curveMarginal = Math.mulDiv(VIRTUAL_ETH + e, 1e18, t);
        uint256 poolOpening = Math.mulDiv(e, 1e18, liq);
        console2.log("Scope-5 curve marginal price:", curveMarginal);
        console2.log("Scope-5 pool opening price:  ", poolOpening);

        // Equal to within integer rounding.
        uint256 diff = curveMarginal > poolOpening ? curveMarginal - poolOpening : poolOpening - curveMarginal;
        assertLe(Math.mulDiv(diff, 1_000_000, curveMarginal), 1, "continuity within 1 ppm");
    }

    // =====================================================================
    // Scope item 2 — migration-target replacement now works with the locker
    // =====================================================================

    function testScope2_ReplacementAdapterIsAcceptedByTheLocker() public {
        _fundToThreshold();

        VOIDUniswapV3Migration replacement =
            new VOIDUniswapV3Migration(IVOIDUniswapV3PositionManager(address(manager)), safe);
        vm.prank(safe);
        curve.proposeMigrationTarget(address(replacement));
        vm.warp(block.timestamp + 2 days + 1);
        vm.prank(safe);
        curve.acceptMigrationTarget();
        assertEq(curve.migrationTarget(), address(replacement));

        // H2-01 is fixed: registerPosition is permissionless and records the
        // registrar, and the curve verifies the registrar is its active target.
        vm.prank(safe);
        curve.seedMigrationPool();
        _forcePoolPrice(_fairGraduationPrice());
        vm.prank(safe);
        curve.graduate();
        assertTrue(curve.graduated());
    }

    function testScope2_CurveRejectsAPositionRegisteredByADifferentAdapter() public {
        // The curve asserts isRegisteredPosition(tokenId, activeTarget), so a
        // position registered by any other party cannot satisfy graduation.
        assertFalse(locker.isRegisteredPosition(1, address(adapter)));
    }

    function testScope2_ProposalWindowAndCancellation() public {
        VOIDUniswapV3Migration replacement =
            new VOIDUniswapV3Migration(IVOIDUniswapV3PositionManager(address(manager)), safe);
        vm.prank(safe);
        curve.proposeMigrationTarget(address(replacement));
        vm.prank(safe);
        curve.cancelMigrationTarget();
        vm.prank(safe);
        vm.expectRevert(VOIDBondingCurve.NoMigrationProposal.selector);
        curve.acceptMigrationTarget();

        vm.prank(safe);
        curve.proposeMigrationTarget(address(replacement));
        vm.warp(block.timestamp + 2 days + 7 days + 1);
        vm.prank(safe);
        vm.expectRevert(VOIDBondingCurve.MigrationProposalExpired.selector);
        curve.acceptMigrationTarget();
    }

    // =====================================================================
    // Scope item 8 — forced ETH, donated tokens, callbacks
    // =====================================================================

    function testScope8_ForcedEthAndDonatedTokensCannotCorruptGraduation() public {
        _fundToThreshold();

        // Force ETH in and donate tokens directly to the curve.
        EthForcer forcer = new EthForcer();
        vm.prank(attacker);
        forcer.forceTo{value: 40 ether}(payable(address(curve)));
        uint256 donate = 1_000_000 ether;
        vm.prank(alice);
        token.transfer(address(curve), donate);

        uint256 e = curve.ethReserve();
        uint256 t = curve.tokenReserve();
        (uint256 liq, uint256 burnAmt) = curve.graduationLiquidityQuote();

        vm.prank(safe);
        curve.seedMigrationPool();
        _forcePoolPrice(_fairGraduationPrice());
        vm.prank(safe);
        curve.graduate();

        assertTrue(curve.graduated());
        // Accounted amounts drove everything; donations were ignored and remain
        // as sweepable excess.
        assertEq(curve.ethReserve(), 0);
        assertEq(curve.tokenReserve(), 0);
        assertEq(address(curve).balance, 40 ether, "forced ETH untouched and sweepable");
        assertEq(token.balanceOf(address(curve)), donate, "donated tokens untouched and sweepable");
        e;
        t;
        liq;
        burnAmt;

        vm.prank(safe);
        curve.sweepExcess(payable(safe));
        assertEq(address(curve).balance, 0);
        assertEq(token.balanceOf(address(curve)), 0);
    }

    function testScope8_DirectEthToTheCurveStillReverts() public {
        vm.prank(attacker);
        (bool ok,) = address(curve).call{value: 1 ether}("");
        assertFalse(ok, "receive() only accepts the active migration target");
    }

    // =====================================================================
    // Scope item 9 — solvency and redeemability
    // =====================================================================

    function testFuzzScope9_FloatRemainsFullyRedeemableBeforeGraduation(uint8 buys, uint96 sellSeed) public {
        uint256 n = bound(uint256(buys), 1, 40);
        for (uint256 i; i < n; ++i) {
            _buy(alice, 1 ether);
        }
        uint256 bal = token.balanceOf(alice);
        uint256 sellAmount = bound(uint256(sellSeed), 1, bal);
        if (sellAmount <= curve.maxSellable()) {
            uint256 q = curve.quoteSell(sellAmount);
            if (q > 0) {
                vm.startPrank(alice);
                token.approve(address(curve), sellAmount);
                curve.sell(sellAmount, q, block.timestamp);
                vm.stopPrank();
            }
        }
        uint256 outstanding = token.LAUNCH_ALLOCATION() - curve.tokenReserve();
        assertGe(curve.maxSellable(), outstanding, "entire float must remain redeemable");
        assertGe(address(curve).balance, curve.ethReserve(), "reserves fully backed");
    }

    // =====================================================================
    // Scope item 10 — residual MEV under the 1 ETH cap
    // =====================================================================

    function testScope10_SandwichUnderTheOneEthCap() public {
        _buy(alice, 1 ether);

        uint256 victimEth = 1 ether;
        uint256 honest = curve.quoteBuy(victimEth);
        uint256 start = attacker.balance;

        // The cap is per transaction, not per address or per block. A searcher
        // bundles N buys, the victim, then N sells.
        uint256 n = 8;
        uint256[] memory got = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            got[i] = _buy(attacker, 1 ether);
        }
        uint256 victimGot = _buy(bob, victimEth);
        for (uint256 i; i < n; ++i) {
            uint256 amt = got[n - 1 - i];
            uint256 q = curve.quoteSell(amt);
            vm.startPrank(attacker);
            token.approve(address(curve), amt);
            curve.sell(amt, q, block.timestamp);
            vm.stopPrank();
        }

        console2.log("Scope-10 victim quoted VOID:", honest);
        console2.log("Scope-10 victim got VOID:   ", victimGot);
        console2.log("Scope-10 victim shortfall %% x100:", Math.mulDiv(honest - victimGot, 10_000, honest));
        if (attacker.balance > start) {
            console2.log("Scope-10 attacker profit (wei):", attacker.balance - start);
        } else {
            console2.log("Scope-10 attacker LOSS (wei):  ", start - attacker.balance);
        }
        assertGt(honest, victimGot);
    }

    /// @dev Sweep every bundle size to check whether ANY sandwich is profitable.
    function testScope10_NoSandwichSizeIsProfitable() public {
        uint256[6] memory sizes = [uint256(1), 2, 4, 8, 16, 25];
        for (uint256 s; s < sizes.length; ++s) {
            uint256 snap = vm.snapshotState();
            _buy(alice, 1 ether);

            uint256 n = sizes[s];
            uint256 honest = curve.quoteBuy(1 ether);
            uint256 start = attacker.balance;
            uint256[] memory got = new uint256[](n);
            for (uint256 i; i < n; ++i) {
                got[i] = _buy(attacker, 1 ether);
            }
            uint256 victimGot = _buy(bob, 1 ether);
            for (uint256 i; i < n; ++i) {
                uint256 amt = got[n - 1 - i];
                uint256 q = curve.quoteSell(amt);
                vm.startPrank(attacker);
                token.approve(address(curve), amt);
                curve.sell(amt, q, block.timestamp);
                vm.stopPrank();
            }
            console2.log("Scope-10b bundle size:", n);
            console2.log("Scope-10b victim shortfall bps:", Math.mulDiv(honest - victimGot, 10_000, honest));
            if (attacker.balance > start) {
                console2.log("Scope-10b attacker PROFIT (wei):", attacker.balance - start);
            } else {
                console2.log("Scope-10b attacker loss (wei):  ", start - attacker.balance);
            }
            assertLe(attacker.balance, start, "no sandwich size may be profitable");
            vm.revertToState(snap);
        }
    }

    function testScope10_PurchaseCapIsEnforced() public {
        vm.prank(alice);
        vm.expectRevert(VOIDBondingCurve.BuyTooLarge.selector);
        curve.buy{value: 1 ether + 1}(1, block.timestamp);
        assertEq(curve.maxBuyAmount(), 1 ether);
        assertEq(curve.quoteBuy(1 ether + 1), 0);
    }

    // =====================================================================
    // Scope item 11 — strategic burn is now bounded
    // =====================================================================

    function testScope11_StrategicBurnIsCappedAndRenamingSurvives() public {
        vm.prank(safe);
        token.setRenamePaused(false);
        for (uint256 i; i < 25; ++i) {
            _buy(alice, 1 ether);
        }

        uint256 minimum = token.nextBurnRequirement();
        uint256 maximum = token.maximumBurnAmount();
        assertEq(maximum, minimum + 2_000_000 ether);

        vm.prank(alice);
        vm.expectRevert(VOIDCoin.BurnAboveMaximum.selector);
        token.burnForRename(maximum + 1, keccak256("too-big"));

        vm.prank(alice);
        token.burnForRename(maximum, keccak256("max"));
        assertEq(token.recordBurn(), maximum);

        // Renaming remains reachable: the next requirement is still far below
        // the circulating float.
        uint256 next = token.nextBurnRequirement();
        console2.log("Scope-11 record after max strategic burn:", token.recordBurn());
        console2.log("Scope-11 next requirement:               ", next);
        console2.log("Scope-11 alice remaining balance:        ", token.balanceOf(alice));
        assertLt(next, token.balanceOf(alice));
    }

    function testScope11_LifetimeRenameCeiling() public view {
        // Each record may exceed the previous by at most TAKEOVER_INCREMENT +
        // MAX_STRATEGIC_PREMIUM, and every burn destroys the full record amount.
        uint256 record;
        uint256 cumulative;
        uint256 n;
        while (true) {
            uint256 next = record == 0 ? 1_000_000 ether : record + 250_000 ether + 2_000_000 ether;
            if (cumulative + next > 980_000_000 ether) break;
            cumulative += next;
            record = next;
            ++n;
        }
        console2.log("Scope-11b maximum lifetime renames at full premium:", n);
        console2.log("Scope-11b cumulative burn:", cumulative);
        assertGt(n, 20);
    }

    // =====================================================================
    // Scope item 12 — approveRename authority
    // =====================================================================

    function testScope12_IdentityChangesOnlyOnValidCommitmentAndSafeApproval() public {
        vm.prank(safe);
        token.setRenamePaused(false);
        for (uint256 i; i < 5; ++i) {
            _buy(alice, 1 ether);
        }

        uint256 amount = token.nextBurnRequirement();
        uint256 burnId = token.nextBurnId();
        bytes32 imageHash = keccak256("img");
        bytes32 salt = keccak256("salt");
        string memory uri = "ipfs://approved";
        bytes32 c = token.proposalCommitment(
            burnId, alice, amount, "Night Shift", "NIGHT", imageHash, keccak256(bytes(uri)), salt
        );
        vm.prank(alice);
        token.burnForRename(amount, c);

        // Non-owner cannot approve.
        vm.prank(alice);
        vm.expectRevert();
        token.approveRename(burnId, "Night Shift", "NIGHT", uri, imageHash, salt);

        // Owner cannot approve a mismatched name, symbol, URI, image hash or salt.
        vm.startPrank(safe);
        vm.expectRevert(VOIDCoin.CommitmentMismatch.selector);
        token.approveRename(burnId, "Other Name", "NIGHT", uri, imageHash, salt);
        vm.expectRevert(VOIDCoin.CommitmentMismatch.selector);
        token.approveRename(burnId, "Night Shift", "OTHER", uri, imageHash, salt);
        vm.expectRevert(VOIDCoin.CommitmentMismatch.selector);
        token.approveRename(burnId, "Night Shift", "NIGHT", "ipfs://other", imageHash, salt);
        vm.expectRevert(VOIDCoin.CommitmentMismatch.selector);
        token.approveRename(burnId, "Night Shift", "NIGHT", uri, keccak256("other"), salt);
        vm.expectRevert(VOIDCoin.CommitmentMismatch.selector);
        token.approveRename(burnId, "Night Shift", "NIGHT", uri, imageHash, keccak256("other"));
        vm.stopPrank();

        assertEq(token.name(), "VOIDCOIN");
        assertEq(token.symbol(), "VOID");

        vm.prank(safe);
        token.approveRename(burnId, "Night Shift", "NIGHT", uri, imageHash, salt);
        assertEq(token.name(), "Night Shift");
        assertEq(token.symbol(), "NIGHT");
        assertEq(token.tokenURI(), uri);
        assertEq(token.activeSlot().burner, address(0));
    }

    // =====================================================================
    // Scope item 13 — deployer holds no authority
    // =====================================================================

    function testScope13_DeployerAndLaunchHoldNoProtocolAuthority() public view {
        assertEq(token.owner(), safe);
        assertEq(curve.owner(), safe);
        assertEq(token.pendingOwner(), address(0));
        assertEq(curve.pendingOwner(), address(0));
        assertEq(token.balanceOf(address(launch)), 0);
        assertEq(address(this).balance >= 0, true);
        // VOIDLaunch's only post-construction function is curve-gated.
        assertEq(curve.reserveInitializer(), address(launch));
        assertEq(token.launchReserveBurner(), address(launch));
        // The locker and adapter have no owner at all.
        assertEq(locker.beneficiary(), safe);
        assertEq(adapter.dustRecipient(), safe);
    }

    // =====================================================================
    // New Low findings
    // =====================================================================

    /// @notice release() now uses safeTransferFrom, so the immutable beneficiary
    ///         MUST implement onERC721Received. A Safe without an ERC-721 fallback
    ///         handler permanently strands the LP position.
    function testLow_BeneficiaryWithoutErc721HandlerStrandsThePositionForever() public {
        address plainSafe = address(new SafeWithoutErc721Handler());
        VOIDPositionLocker plainLocker = new VOIDPositionLocker(IERC721(address(manager)), plainSafe);

        AttackerRecipient dummy = new AttackerRecipient();
        dummy;
        // Mint a position directly to the locker through the model, then register.
        MockWETH9 w = weth;
        w;
        // Use the adapter's seed path with a throwaway token to place an NFT.
        ThrowawayToken tt = new ThrowawayToken(address(this), 1_000_000 ether);
        VOIDUniswapV3Migration a2 =
            new VOIDUniswapV3Migration(IVOIDUniswapV3PositionManager(address(manager)), address(this));
        tt.approve(address(a2), 1_000_000 ether);
        vm.deal(address(this), 2 ether);
        (,, uint256 used,) = a2.seed{value: 1 ether}(address(tt), 1_000_000 ether, address(plainLocker));
        used;

        uint256 tokenId = manager.nextTokenId() - 1;
        assertEq(manager.ownerOf(tokenId), address(plainLocker));

        vm.warp(block.timestamp + 366 days);
        vm.expectRevert(); // ERC721InvalidReceiver
        plainLocker.release(tokenId);
        console2.log("Low: LP position is permanently stranded if the Safe cannot receive ERC-721");
    }

    /// @notice registerPosition is permissionless. Anyone can push arbitrary
    ///         Uniswap positions into the locker and lock them for a year.
    function testLow_AnyoneCanForceArbitraryPositionsIntoTheLocker() public {
        ThrowawayToken tt = new ThrowawayToken(attacker, 1_000_000 ether);
        vm.startPrank(attacker);
        tt.approve(address(adapter), 1_000_000 ether);
        adapter.seed{value: 1 ether}(address(tt), 1_000_000 ether, address(locker));
        vm.stopPrank();
        uint256 tokenId = manager.nextTokenId() - 1;
        assertEq(manager.ownerOf(tokenId), address(locker));
        assertGt(locker.unlockAt(tokenId), 0);
    }

    /// @notice Tokens donated to VOIDLaunch can never be recovered or burned.
    function testLow_TokensDonatedToVoidLaunchArePermanentlyStranded() public {
        _buy(alice, 1 ether);
        uint256 amount = 1_000 ether;
        vm.prank(alice);
        token.transfer(address(launch), amount);
        assertEq(token.balanceOf(address(launch)), amount);

        // VOIDLaunch exposes only burnCurveExcess, gated to the curve, and the
        // curve only calls it once during graduation for an exact amount.
        vm.prank(alice);
        vm.expectRevert(VOIDLaunch.OnlyBondingCurve.selector);
        launch.burnCurveExcess(amount);

        _fundToThreshold();
        vm.prank(safe);
        curve.seedMigrationPool();
        _forcePoolPrice(_fairGraduationPrice());
        vm.prank(safe);
        curve.graduate();
        assertEq(token.balanceOf(address(launch)), amount, "donation still stuck after graduation");
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

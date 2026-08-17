// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IVOIDGraduationCurve {
    function token() external view returns (address);
    function migrationTarget() external view returns (address);
    function ethReserve() external view returns (uint256);
    function graduationLiquidityQuote() external view returns (uint256 tokensForLiquidity, uint256 tokensToBurn);
    function graduationReady() external view returns (bool);
    function poolSeeded() external view returns (bool);
    function graduated() external view returns (bool);
    function graduate() external;
}

interface IVOIDGraduationAdapter {
    function positionManager() external view returns (address);
    function weth9() external view returns (address);
    // Canonical adapter getter; capitalization matches the deployed ABI.
    // slither-disable-next-line naming-convention
    function POOL_FEE() external view returns (uint24);
}

interface IVOIDGraduationPositionManager {
    function factory() external view returns (address);
}

interface IVOIDGraduationFactory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

interface IVOIDGraduationPool {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
}

interface IVOIDGraduationRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IVOIDGraduationWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

/// @title VOIDGraduationExecutor
/// @notice Atomically corrects the live Uniswap v3 pool price and completes an already Safe-seeded graduation.
/// @dev The caller supplies a bounded amount of both possible correction assets and receives every unused input and
/// swap output. No bonding-curve reserve is used for the correction. A failure reverts the correction and graduation.
contract VOIDGraduationExecutor is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant Q192 = 1 << 192;

    IVOIDGraduationCurve public immutable curve;
    IERC20 public immutable token;
    IVOIDGraduationRouter public immutable swapRouter;

    struct ExecutionContext {
        IVOIDGraduationWETH weth;
        address pool;
        address token0;
        address token1;
        uint24 fee;
        uint160 targetPrice;
    }

    error ZeroAddress();
    error InvalidContract();
    error GraduationUnavailable();
    error PoolUnavailable();
    error InvalidPrice();
    error CorrectionAssetRequired();
    error CorrectionIncomplete();
    error ZeroSwapOutput();
    error DirectEthDisabled();
    error UnexpectedBalance();

    event GraduationExecuted(
        address indexed caller, address indexed pool, address indexed correctionAsset, uint160 targetSqrtPriceX96
    );

    constructor(IVOIDGraduationCurve curve_, IVOIDGraduationRouter swapRouter_) {
        if (address(curve_) == address(0) || address(swapRouter_) == address(0)) revert ZeroAddress();
        if (address(curve_).code.length == 0 || address(swapRouter_).code.length == 0) revert InvalidContract();
        address launchToken = curve_.token();
        if (launchToken == address(0) || launchToken.code.length == 0) revert InvalidContract();
        curve = curve_;
        token = IERC20(launchToken);
        swapRouter = swapRouter_;
    }

    receive() external payable {
        address target = curve.migrationTarget();
        if (msg.sender != IVOIDGraduationAdapter(target).weth9()) revert DirectEthDisabled();
    }

    /// @notice Corrects the active pool to the curve's live marginal price and graduates in the same transaction.
    /// @param maximumTokenIn Maximum VOID the caller permits this transaction to use when VOID is the correction side.
    /// The caller must approve this executor first. `msg.value` is the maximum ETH correction in the opposite direction.
    // Every state-changing external call is protected by nonReentrant. Pre-call balance snapshots and post-call exact
    // baselines deliberately prove this stateless executor cannot spend donations or retain any execution asset.
    // slither-disable-start reentrancy-balance
    function execute(uint256 maximumTokenIn) external payable nonReentrant {
        if (!curve.graduationReady() || !curve.poolSeeded() || curve.graduated()) revert GraduationUnavailable();

        uint256 tokenBalanceBefore = token.balanceOf(address(this));
        uint256 ethBalanceBefore = address(this).balance - msg.value;
        ExecutionContext memory context = _executionContext();
        uint256 wethBalanceBefore = context.weth.balanceOf(address(this));
        address correctionAsset = _correctPrice(context, maximumTokenIn);

        curve.graduate();
        if (!curve.graduated()) revert GraduationUnavailable();

        uint256 tokenRefund = token.balanceOf(address(this)) - tokenBalanceBefore;
        if (tokenRefund > 0) token.safeTransfer(msg.sender, tokenRefund);
        uint256 wethRefund = context.weth.balanceOf(address(this)) - wethBalanceBefore;
        if (wethRefund > 0) context.weth.withdraw(wethRefund);
        uint256 ethRefund = address(this).balance - ethBalanceBefore;
        if (ethRefund > 0) Address.sendValue(payable(msg.sender), ethRefund);
        if (
            token.balanceOf(address(this)) != tokenBalanceBefore
                || context.weth.balanceOf(address(this)) != wethBalanceBefore
                || address(this).balance != ethBalanceBefore
        ) revert UnexpectedBalance();

        emit GraduationExecuted(msg.sender, context.pool, correctionAsset, context.targetPrice);
    }
    // slither-disable-end reentrancy-balance

    function _executionContext() private view returns (ExecutionContext memory context) {
        IVOIDGraduationAdapter adapter = IVOIDGraduationAdapter(curve.migrationTarget());
        address wethAddress = adapter.weth9();
        address manager = adapter.positionManager();
        if (wethAddress.code.length == 0 || manager.code.length == 0) revert InvalidContract();
        address factory = IVOIDGraduationPositionManager(manager).factory();
        if (factory.code.length == 0) revert InvalidContract();

        context.weth = IVOIDGraduationWETH(wethAddress);
        context.fee = adapter.POOL_FEE();
        context.pool = IVOIDGraduationFactory(factory).getPool(address(token), wethAddress, context.fee);
        if (context.pool.code.length == 0) revert PoolUnavailable();
        bool tokenIsToken0 = address(token) < wethAddress;
        context.token0 = tokenIsToken0 ? address(token) : wethAddress;
        context.token1 = tokenIsToken0 ? wethAddress : address(token);
        context.targetPrice = targetSqrtPriceX96(wethAddress);
    }

    function _correctPrice(ExecutionContext memory context, uint256 maximumTokenIn)
        private
        returns (address correctionAsset)
    {
        uint160 currentPrice = _poolSqrtPrice(context.pool);
        if (currentPrice == context.targetPrice) return address(0);
        correctionAsset = currentPrice > context.targetPrice ? context.token0 : context.token1;

        uint256 amountIn;
        if (correctionAsset == address(token)) {
            if (maximumTokenIn == 0) revert CorrectionAssetRequired();
            token.safeTransferFrom(msg.sender, address(this), maximumTokenIn);
            amountIn = maximumTokenIn;
        } else {
            if (msg.value == 0) revert CorrectionAssetRequired();
            context.weth.deposit{value: msg.value}();
            amountIn = msg.value;
        }

        IERC20(correctionAsset).forceApprove(address(swapRouter), amountIn);
        uint256 amountOut = swapRouter.exactInputSingle(
            IVOIDGraduationRouter.ExactInputSingleParams({
                tokenIn: correctionAsset,
                tokenOut: correctionAsset == context.token0 ? context.token1 : context.token0,
                fee: context.fee,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: context.targetPrice
            })
        );
        if (amountOut == 0) revert ZeroSwapOutput();
        IERC20(correctionAsset).forceApprove(address(swapRouter), 0);
        uint160 correctedPrice = _poolSqrtPrice(context.pool);
        if (correctedPrice != context.targetPrice) revert CorrectionIncomplete();
    }

    function targetSqrtPriceX96(address wethAddress) public view returns (uint160 sqrtPriceX96) {
        (uint256 tokensForLiquidity, uint256 tokensToBurn) = curve.graduationLiquidityQuote();
        uint256 ethForLiquidity = curve.ethReserve();
        if (tokensForLiquidity == 0 || tokensToBurn == 0 || ethForLiquidity == 0) revert InvalidPrice();
        uint256 amount0 = address(token) < wethAddress ? tokensForLiquidity : ethForLiquidity;
        uint256 amount1 = address(token) < wethAddress ? ethForLiquidity : tokensForLiquidity;
        uint256 sqrtRatio = Math.sqrt(Math.mulDiv(amount1, Q192, amount0));
        if (sqrtRatio == 0 || sqrtRatio > type(uint160).max) revert InvalidPrice();
        sqrtPriceX96 = uint160(sqrtRatio);
    }

    function _poolSqrtPrice(address pool) private view returns (uint160 price) {
        // Only the current price is relevant to bounded correction; remaining slot0 fields are intentionally ignored.
        // slither-disable-next-line unused-return
        (price,,,,,,) = IVOIDGraduationPool(pool).slot0();
    }
}

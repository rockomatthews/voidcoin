// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IVOIDUniswapV3PositionManager, IVOIDWETH9} from "../src/VOIDUniswapV3Migration.sol";

/// @dev Shared Uniswap v3 constants for the model.
library UniMath {
    uint256 internal constant Q96 = 1 << 96;

    function sqrtRatioAtTick(int24 tick) internal pure returns (uint160) {
        if (tick == -887_200) return 4_310_618_291;
        if (tick == 887_200) return 1_456_195_216_263_841_500_379_307_683_214_498_614_686_540_680_047;
        revert("model: unsupported tick");
    }

    function amount0Delta(uint160 sqrtA, uint160 sqrtB, uint128 liquidity) internal pure returns (uint256) {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        if (sqrtA == 0) return 0;
        uint256 n1 = uint256(liquidity) << 96;
        uint256 n2 = uint256(sqrtB) - uint256(sqrtA);
        return Math.mulDiv(Math.mulDiv(n1, n2, uint256(sqrtB)), 1, uint256(sqrtA));
    }

    function amount1Delta(uint160 sqrtA, uint160 sqrtB, uint128 liquidity) internal pure returns (uint256) {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        return Math.mulDiv(uint256(liquidity), uint256(sqrtB) - uint256(sqrtA), Q96);
    }

    function liqForAmount0(uint160 sqrtA, uint160 sqrtB, uint256 amount0) internal pure returns (uint128) {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        uint256 intermediate = Math.mulDiv(uint256(sqrtA), uint256(sqrtB), Q96);
        return uint128(Math.mulDiv(amount0, intermediate, uint256(sqrtB) - uint256(sqrtA)));
    }

    function liqForAmount1(uint160 sqrtA, uint160 sqrtB, uint256 amount1) internal pure returns (uint128) {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        return uint128(Math.mulDiv(amount1, Q96, uint256(sqrtB) - uint256(sqrtA)));
    }

    function liquidityForAmounts(uint160 sqrtP, uint160 sqrtA, uint160 sqrtB, uint256 amount0, uint256 amount1)
        internal
        pure
        returns (uint128 liquidity)
    {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        if (sqrtP <= sqrtA) {
            liquidity = liqForAmount0(sqrtA, sqrtB, amount0);
        } else if (sqrtP < sqrtB) {
            uint128 l0 = liqForAmount0(sqrtP, sqrtB, amount0);
            uint128 l1 = liqForAmount1(sqrtA, sqrtP, amount1);
            liquidity = l0 < l1 ? l0 : l1;
        } else {
            liquidity = liqForAmount1(sqrtA, sqrtB, amount1);
        }
    }

    function amountsForLiquidity(uint160 sqrtP, uint160 sqrtA, uint160 sqrtB, uint128 liquidity)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        if (sqrtA > sqrtB) (sqrtA, sqrtB) = (sqrtB, sqrtA);
        if (sqrtP <= sqrtA) {
            amount0 = amount0Delta(sqrtA, sqrtB, liquidity);
        } else if (sqrtP < sqrtB) {
            amount0 = amount0Delta(sqrtP, sqrtB, liquidity);
            amount1 = amount1Delta(sqrtA, sqrtP, liquidity);
        } else {
            amount1 = amount1Delta(sqrtA, sqrtB, liquidity);
        }
    }

    /// @dev SqrtPriceMath.getNextSqrtPriceFromAmount0RoundingUp (add = true, zeroForOne).
    function nextPriceFromAmount0(uint160 sqrtP, uint128 liquidity, uint256 amount0)
        internal
        pure
        returns (uint160)
    {
        if (amount0 == 0) return sqrtP;
        uint256 numerator = uint256(liquidity) << 96;
        uint256 product = amount0 * uint256(sqrtP);
        uint256 denominator = numerator + product;
        return uint160(Math.mulDiv(numerator, uint256(sqrtP), denominator));
    }

    /// @dev SqrtPriceMath.getNextSqrtPriceFromAmount1RoundingDown (add = true, oneForZero).
    function nextPriceFromAmount1(uint160 sqrtP, uint128 liquidity, uint256 amount1)
        internal
        pure
        returns (uint160)
    {
        return uint160(uint256(sqrtP) + Math.mulDiv(amount1, Q96, uint256(liquidity)));
    }
}

/// @notice A single full-range-position Uniswap v3 pool with real swap mechanics:
///         constant-product within the range, a 1e6-denominated input fee, and
///         exact-limit termination (slot0 lands EXACTLY on sqrtPriceLimitX96
///         when the limit binds, matching UniswapV3Pool).
contract ModelPool {
    using SafeERC20 for IERC20;

    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    uint160 public sqrtPriceX96;
    uint128 public liquidity;

    constructor(address token0_, address token1_, uint24 fee_) {
        token0 = token0_;
        token1 = token1_;
        fee = fee_;
    }

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (sqrtPriceX96, int24(0), uint16(0), uint16(0), uint16(0), uint8(0), true);
    }

    function initialize(uint160 price) external {
        require(sqrtPriceX96 == 0, "already initialised");
        sqrtPriceX96 = price;
    }

    function addLiquidity(uint128 delta) external {
        liquidity += delta;
    }

    /// @dev Exact-input swap. Returns (amountInUsed, amountOut). Tokens must already
    ///      be transferred in by the caller for amountInUsed; the caller settles.
    function quoteSwap(bool zeroForOne, uint256 amountIn, uint160 limit)
        public
        view
        returns (uint256 amountInUsed, uint256 amountOut, uint160 sqrtNext)
    {
        require(sqrtPriceX96 != 0, "uninitialised");
        require(liquidity > 0, "no liquidity");
        uint160 sqrtLower = UniMath.sqrtRatioAtTick(-887_200);
        uint160 sqrtUpper = UniMath.sqrtRatioAtTick(887_200);
        uint160 bound = zeroForOne ? sqrtLower : sqrtUpper;
        if (zeroForOne) {
            require(limit < sqrtPriceX96 && limit >= bound, "bad limit");
        } else {
            require(limit > sqrtPriceX96 && limit <= bound, "bad limit");
        }

        uint256 amountInLessFee = amountIn - Math.mulDiv(amountIn, fee, 1_000_000, Math.Rounding.Ceil);
        uint256 amountToReachLimit = zeroForOne
            ? UniMath.amount0Delta(limit, sqrtPriceX96, liquidity)
            : UniMath.amount1Delta(sqrtPriceX96, limit, liquidity);

        if (amountInLessFee >= amountToReachLimit) {
            sqrtNext = limit;
            uint256 netIn = amountToReachLimit;
            amountInUsed = netIn + Math.mulDiv(netIn, fee, 1_000_000 - fee, Math.Rounding.Ceil);
            if (amountInUsed > amountIn) amountInUsed = amountIn;
        } else {
            sqrtNext = zeroForOne
                ? UniMath.nextPriceFromAmount0(sqrtPriceX96, liquidity, amountInLessFee)
                : UniMath.nextPriceFromAmount1(sqrtPriceX96, liquidity, amountInLessFee);
            amountInUsed = amountIn;
        }
        amountOut = zeroForOne
            ? UniMath.amount1Delta(sqrtNext, sqrtPriceX96, liquidity)
            : UniMath.amount0Delta(sqrtNext, sqrtPriceX96, liquidity);
    }

    /// @dev Settles a quoted swap. The ROUTER moves `amountInUsed` into the pool
    ///      first, exactly as the real swap callback does, so the executor only
    ///      ever needs an allowance to the router.
    function settleSwap(bool zeroForOne, uint160 sqrtNext, uint256 amountOut, address recipient) external {
        sqrtPriceX96 = sqrtNext;
        address tokenOut = zeroForOne ? token1 : token0;
        if (amountOut > 0) IERC20(tokenOut).safeTransfer(recipient, amountOut);
    }
}

/// @notice Position manager + factory. Mirrors createAndInitializePoolIfNecessary
///         semantics: an already-initialised pool ignores the supplied price.
contract ModelPositionManager is ERC721, IVOIDUniswapV3PositionManager {
    using SafeERC20 for IERC20;

    address public immutable override WETH9;

    mapping(bytes32 key => address pool) private _pools;
    uint256 public nextTokenId = 1;

    constructor(address weth) ERC721("Uniswap V3 Positions", "UNI-V3-POS") {
        WETH9 = weth;
    }

    function factory() external view override returns (address) {
        return address(this);
    }

    function _key(address a, address b, uint24 f) private pure returns (bytes32) {
        (address x, address y) = a < b ? (a, b) : (b, a);
        return keccak256(abi.encode(x, y, f));
    }

    function getPool(address a, address b, uint24 f) external view returns (address) {
        return _pools[_key(a, b, f)];
    }

    function createAndInitializePoolIfNecessary(address token0, address token1, uint24 f, uint160 sqrtPriceX96)
        external
        payable
        override
        returns (address pool)
    {
        bytes32 key = _key(token0, token1, f);
        pool = _pools[key];
        if (pool == address(0)) {
            pool = address(new ModelPool(token0 < token1 ? token0 : token1, token0 < token1 ? token1 : token0, f));
            _pools[key] = pool;
        }
        if (ModelPool(pool).sqrtPriceX96() == 0) ModelPool(pool).initialize(sqrtPriceX96);
        return pool;
    }

    function mint(MintParams calldata params)
        external
        payable
        override
        returns (uint256 tokenId, uint128 liq, uint256 amount0, uint256 amount1)
    {
        address pool = _pools[_key(params.token0, params.token1, params.fee)];
        require(pool != address(0), "no pool");
        uint160 sqrtP = ModelPool(pool).sqrtPriceX96();
        require(sqrtP != 0, "uninitialised");

        uint160 sqrtA = UniMath.sqrtRatioAtTick(params.tickLower);
        uint160 sqrtB = UniMath.sqrtRatioAtTick(params.tickUpper);
        liq = UniMath.liquidityForAmounts(sqrtP, sqrtA, sqrtB, params.amount0Desired, params.amount1Desired);
        (amount0, amount1) = UniMath.amountsForLiquidity(sqrtP, sqrtA, sqrtB, liq);

        require(amount0 >= params.amount0Min, "Price slippage check");
        require(amount1 >= params.amount1Min, "Price slippage check");

        if (amount0 > 0) IERC20(params.token0).safeTransferFrom(msg.sender, pool, amount0);
        if (amount1 > 0) IERC20(params.token1).safeTransferFrom(msg.sender, pool, amount1);
        ModelPool(pool).addLiquidity(liq);

        tokenId = nextTokenId++;
        _safeMint(params.recipient, tokenId);
    }
}

/// @notice SwapRouter02 model. Pulls ONLY the amount the pool actually consumed,
///         exactly as the real router does through the swap callback.
contract ModelSwapRouter02 {
    using SafeERC20 for IERC20;

    ModelPositionManager public immutable manager;

    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    constructor(ModelPositionManager manager_) {
        manager = manager_;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
        address pool = manager.getPool(params.tokenIn, params.tokenOut, params.fee);
        require(pool != address(0), "no pool");
        bool zeroForOne = params.tokenIn == ModelPool(pool).token0();
        (uint256 amountInUsed, uint256 out, uint160 next) =
            ModelPool(pool).quoteSwap(zeroForOne, params.amountIn, params.sqrtPriceLimitX96);
        // Pull ONLY what the pool consumed, from the original caller, via the
        // caller's allowance to this router. This is what the real callback does.
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, pool, amountInUsed);
        ModelPool(pool).settleSwap(zeroForOne, next, out, params.recipient);
        amountOut = out;
        require(amountOut >= params.amountOutMinimum, "Too little received");
    }
}

/// @notice Base predeploy WETH9. `withdraw` uses `transfer`, i.e. a 2300-gas stipend.
contract BaseWETH9 is ERC20, IVOIDWETH9 {
    constructor() ERC20("Wrapped Ether", "WETH") {}

    receive() external payable {
        deposit();
    }

    function deposit() public payable override {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external override {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount); // 2300 gas stipend, as on Base
    }
}

/// @notice WETH9 variant that forwards all gas, for isolating stipend effects.
contract GenerousWETH9 is ERC20, IVOIDWETH9 {
    constructor() ERC20("Wrapped Ether", "WETH") {}

    receive() external payable {
        deposit();
    }

    function deposit() public payable override {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external override {
        _burn(msg.sender, amount);
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        require(ok, "withdraw failed");
    }
}

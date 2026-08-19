// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IVOIDV2WETH is IERC20 {
    function deposit() external payable;
}

interface IVOIDV2SwapRouter {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}

/// @title VOIDV2BuyRouter
/// @notice Converts any nonzero Base ETH amount into VOID through WETH/USDC and the visible VOID/USDC pool.
contract VOIDV2BuyRouter is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IVOIDV2WETH public immutable weth;
    IERC20 public immutable usdc;
    IERC20 public immutable token;
    IVOIDV2SwapRouter public immutable swapRouter;
    uint24 public immutable wethUsdcFee;
    uint24 public immutable voidUsdcFee;

    error ZeroAddress();
    error InvalidContract();
    error ZeroInput();
    error UnexpectedBalance();

    event TokensPurchased(address indexed buyer, uint256 ethIn, uint256 tokensOut);

    constructor(
        IVOIDV2WETH weth_,
        IERC20 usdc_,
        IERC20 token_,
        IVOIDV2SwapRouter swapRouter_,
        uint24 wethUsdcFee_,
        uint24 voidUsdcFee_
    ) {
        if (
            address(weth_) == address(0) || address(usdc_) == address(0) || address(token_) == address(0)
                || address(swapRouter_) == address(0)
        ) revert ZeroAddress();
        if (
            address(weth_).code.length == 0 || address(usdc_).code.length == 0 || address(token_).code.length == 0
                || address(swapRouter_).code.length == 0
        ) revert InvalidContract();
        weth = weth_;
        usdc = usdc_;
        token = token_;
        swapRouter = swapRouter_;
        wethUsdcFee = wethUsdcFee_;
        voidUsdcFee = voidUsdcFee_;
    }

    // The immutable WETH and router calls are wrapped by nonReentrant. Baseline reads are post-condition accounting,
    // never authorization state, and ensure the stateless router cannot retain either routed asset.
    // slither-disable-start reentrancy-balance
    function buyWithETH(uint256 minimumTokensOut) external payable nonReentrant returns (uint256 tokensOut) {
        if (msg.value == 0 || minimumTokensOut == 0) revert ZeroInput();
        uint256 ethBefore = address(this).balance - msg.value;
        uint256 wethBefore = weth.balanceOf(address(this));
        uint256 usdcBefore = usdc.balanceOf(address(this));
        uint256 tokenBefore = token.balanceOf(address(this));

        weth.deposit{value: msg.value}();
        IERC20(address(weth)).forceApprove(address(swapRouter), msg.value);
        tokensOut = swapRouter.exactInput(
            IVOIDV2SwapRouter.ExactInputParams({
                path: abi.encodePacked(address(weth), wethUsdcFee, address(usdc), voidUsdcFee, address(token)),
                recipient: msg.sender,
                amountIn: msg.value,
                amountOutMinimum: minimumTokensOut
            })
        );
        IERC20(address(weth)).forceApprove(address(swapRouter), 0);

        if (
            address(this).balance != ethBefore || weth.balanceOf(address(this)) != wethBefore
                || usdc.balanceOf(address(this)) != usdcBefore || token.balanceOf(address(this)) != tokenBefore
        ) revert UnexpectedBalance();
        emit TokensPurchased(msg.sender, msg.value, tokensOut);
    }
    // slither-disable-end reentrancy-balance
}

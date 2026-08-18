// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VOIDV2BuyRouter, IVOIDV2WETH, IVOIDV2SwapRouter} from "../src/VOIDV2BuyRouter.sol";

contract RouterMockToken is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }
}

contract RouterMockWETH is RouterMockToken, IVOIDV2WETH {
    constructor() RouterMockToken("Wrapped Ether", "WETH") {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }
}

contract RouterMockSwap is IVOIDV2SwapRouter {
    using SafeERC20 for IERC20;

    IERC20 public immutable weth;
    RouterMockToken public immutable token;
    bytes public lastPath;

    constructor(IERC20 weth_, RouterMockToken token_) {
        weth = weth_;
        token = token_;
    }

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut) {
        lastPath = params.path;
        weth.safeTransferFrom(msg.sender, address(this), params.amountIn);
        amountOut = params.amountIn * 1_000_000;
        require(amountOut >= params.amountOutMinimum, "slippage");
        token.mint(params.recipient, amountOut);
    }
}

contract VOIDV2BuyRouterTest is Test {
    RouterMockWETH internal weth;
    RouterMockToken internal usdc;
    RouterMockToken internal token;
    RouterMockSwap internal swap;
    VOIDV2BuyRouter internal buyRouter;
    address internal buyer = makeAddr("buyer");

    function setUp() public {
        weth = new RouterMockWETH();
        usdc = new RouterMockToken("USD Coin", "USDC");
        token = new RouterMockToken("VOIDCOIN", "VOID");
        swap = new RouterMockSwap(weth, token);
        buyRouter = new VOIDV2BuyRouter(weth, usdc, token, swap, 500, 10_000);
        vm.deal(buyer, 10 ether);
    }

    function testAnyNonzeroEthAmountCanBuy() public {
        vm.prank(buyer);
        uint256 output = buyRouter.buyWithETH{value: 1 wei}(1);
        assertEq(output, 1_000_000);
        assertEq(token.balanceOf(buyer), output);
        assertEq(weth.balanceOf(address(buyRouter)), 0);
        assertEq(usdc.balanceOf(address(buyRouter)), 0);
        assertEq(token.balanceOf(address(buyRouter)), 0);
    }

    function testPathRoutesWethThroughUsdcIntoVoid() public {
        vm.prank(buyer);
        buyRouter.buyWithETH{value: 0.01 ether}(1);
        assertEq(
            swap.lastPath(), abi.encodePacked(address(weth), uint24(500), address(usdc), uint24(10_000), address(token))
        );
    }

    function testSlippageRevertIsAtomic() public {
        uint256 beforeBalance = buyer.balance;
        vm.expectRevert(bytes("slippage"));
        vm.prank(buyer);
        buyRouter.buyWithETH{value: 0.01 ether}(type(uint256).max);
        assertEq(buyer.balance, beforeBalance);
    }
}

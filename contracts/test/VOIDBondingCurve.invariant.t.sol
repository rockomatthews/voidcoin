// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VOIDBondingCurve} from "../src/VOIDBondingCurve.sol";
import {VOIDCoin} from "../src/VOIDCoin.sol";

contract InvariantMigrationTarget {
    function migrate(address token, uint256 tokenAmount, address) external payable returns (bytes32) {
        IERC20(token).transferFrom(msg.sender, address(this), tokenAmount);
        return keccak256(abi.encode(token, tokenAmount, msg.value));
    }
}

contract CurveHandler is Test {
    VOIDBondingCurve internal immutable curve;
    VOIDCoin internal immutable token;

    constructor(VOIDBondingCurve curve_, VOIDCoin token_) {
        curve = curve_;
        token = token_;
        token.approve(address(curve), type(uint256).max);
    }

    receive() external payable {}

    function buy(uint96 rawEth) external {
        uint256 amount = bound(uint256(rawEth), 1 gwei, 5 ether);
        if (address(this).balance < amount) return;
        uint256 quote = curve.quoteBuy(amount);
        if (quote == 0) return;
        try curve.buy{value: amount}(quote, block.timestamp) {} catch {}
    }

    function sell(uint96 rawTokens) external {
        uint256 balance = token.balanceOf(address(this));
        uint256 maximum = curve.maxSellable();
        if (balance == 0 || maximum == 0) return;
        uint256 amount = bound(uint256(rawTokens), 1, balance < maximum ? balance : maximum);
        uint256 quote;
        try curve.quoteSell(amount) returns (uint256 value) {
            quote = value;
        } catch {
            return;
        }
        if (quote == 0) return;
        try curve.sell(amount, quote, block.timestamp) {} catch {}
    }
}

contract VOIDBondingCurveInvariantTest is StdInvariant, Test {
    VOIDCoin internal token;
    VOIDBondingCurve internal curve;
    CurveHandler internal handler;
    uint256 internal initialInvariant;

    function setUp() public {
        InvariantMigrationTarget target = new InvariantMigrationTarget();
        token = new VOIDCoin(address(this), address(this), address(0xBEEF), "ipfs://genesis");
        curve = new VOIDBondingCurve(
            token, address(this), address(this), address(target), address(0xCAFE), 1 ether, 12 ether
        );
        token.transfer(address(curve), token.LAUNCH_ALLOCATION());
        curve.initializeTokenReserve();
        handler = new CurveHandler(curve, token);
        vm.deal(address(handler), 10_000 ether);
        initialInvariant = curve.virtualEthReserve() * curve.tokenReserve();
        targetContract(address(handler));
    }

    function invariantAccountedReservesAreFullyBacked() public view {
        assertGe(address(curve).balance, curve.ethReserve());
        assertGe(token.balanceOf(address(curve)), curve.tokenReserve());
    }

    function invariantTradingNeverReducesPoolInvariant() public view {
        uint256 currentInvariant = (curve.virtualEthReserve() + curve.ethReserve()) * curve.tokenReserve();
        assertGe(currentInvariant, initialInvariant);
    }

    function invariantCurveCannotCreateTokenSupply() public view {
        assertEq(token.totalSupply(), token.ORIGINAL_SUPPLY());
    }
}

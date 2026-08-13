// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VOIDCoin} from "../src/VOIDCoin.sol";
import {VOIDLaunch} from "../src/VOIDLaunch.sol";
import {Distribution} from "../src/interfaces/ILiquidityLauncher.sol";

contract MockPermit2 {
    mapping(address owner => mapping(address token => mapping(address spender => uint160 amount))) public allowance;

    function approve(address token, address spender, uint160 amount, uint48) external {
        allowance[msg.sender][token][spender] = amount;
    }

    function transferFrom(address from, address to, uint160 amount, address token) external {
        uint160 approved = allowance[from][token][msg.sender];
        require(approved >= amount, "permit2 allowance");
        allowance[from][token][msg.sender] = approved - amount;
        IERC20(token).transferFrom(from, to, amount);
    }
}

contract MockLauncher {
    MockPermit2 public immutable permit2;
    address public depositedToken;
    address public distributedStrategy;
    uint256 public distributedAmount;

    constructor(MockPermit2 permit2_) {
        permit2 = permit2_;
    }

    function multicall(bytes[] calldata calls) external returns (bytes[] memory results) {
        results = new bytes[](calls.length);
        for (uint256 i; i < calls.length; ++i) {
            (bool success, bytes memory result) = address(this).delegatecall(calls[i]);
            require(success, "multicall failed");
            results[i] = result;
        }
    }

    function depositToken(address token, uint160 amount) external {
        depositedToken = token;
        permit2.transferFrom(msg.sender, address(this), amount, token);
    }

    function distributeToken(address token, Distribution memory distribution, bytes32) external {
        distributedStrategy = distribution.strategy;
        distributedAmount = distribution.amount;
        IERC20(token).transfer(distribution.strategy, distribution.amount);
    }
}

contract VOIDLaunchTest is Test {
    function testLaunchAllocationMovesAtomicallyIntoBondingCurveStrategy() public {
        address safe = makeAddr("safe");
        address strategy = makeAddr("lbpStrategy");
        MockPermit2 permit2 = new MockPermit2();
        MockLauncher launcher = new MockLauncher(permit2);

        VOIDLaunch launch = new VOIDLaunch(
            safe, address(launcher), strategy, address(permit2), "ipfs://genesis", hex"1234", keccak256("salt")
        );
        VOIDCoin token = launch.token();

        assertEq(token.balanceOf(strategy), 900_000_000 ether);
        assertEq(token.balanceOf(address(launch)), 0);
        assertEq(token.balanceOf(address(launch.vestingWallet())), 100_000_000 ether);
        assertEq(token.pendingOwner(), safe);
        assertEq(token.owner(), address(launch));
        assertEq(launcher.distributedStrategy(), strategy);
        assertEq(launcher.distributedAmount(), 900_000_000 ether);
    }
}

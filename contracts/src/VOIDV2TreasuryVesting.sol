// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title VOIDV2TreasuryVesting
/// @notice Immutable, non-transferable 2% creator vesting with a 30-day cliff and one-year total schedule.
contract VOIDV2TreasuryVesting {
    using SafeERC20 for IERC20;

    uint64 public constant CLIFF = 30 days;
    uint64 public constant DURATION = 365 days;

    address public immutable beneficiary;
    address public immutable initializer;
    uint64 public immutable startsAt;
    IERC20 public token;
    uint256 public released;
    bool public initialized;

    error ZeroAddress();
    error OnlyInitializer();
    error AlreadyInitialized();
    error CliffPending();
    error NothingToRelease();

    event Initialized(address indexed token);
    event Released(address indexed beneficiary, uint256 amount);

    constructor(address beneficiary_) {
        if (beneficiary_ == address(0)) revert ZeroAddress();
        beneficiary = beneficiary_;
        initializer = msg.sender;
        startsAt = uint64(block.timestamp);
    }

    function initialize(IERC20 token_) external {
        if (msg.sender != initializer) revert OnlyInitializer();
        if (initialized) revert AlreadyInitialized();
        if (address(token_) == address(0) || address(token_).code.length == 0) revert ZeroAddress();
        token = token_;
        initialized = true;
        emit Initialized(address(token_));
    }

    function vestedAmount(uint64 timestamp) public view returns (uint256) {
        if (!initialized || timestamp < startsAt + CLIFF) return 0;
        uint256 allocation = token.balanceOf(address(this)) + released;
        if (timestamp >= startsAt + DURATION) return allocation;
        return allocation * (timestamp - startsAt) / DURATION;
    }

    function releasable() public view returns (uint256) {
        return vestedAmount(uint64(block.timestamp)) - released;
    }

    function release() external returns (uint256 amount) {
        if (block.timestamp < startsAt + CLIFF) revert CliffPending();
        amount = releasable();
        if (amount < 1) revert NothingToRelease();
        released += amount;
        token.safeTransfer(beneficiary, amount);
        emit Released(beneficiary, amount);
    }
}

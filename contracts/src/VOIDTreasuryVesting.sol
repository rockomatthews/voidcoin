// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IVOIDGraduationGate {
    function graduatedAt() external view returns (uint64);
}

/// @title VOIDTreasuryVesting
/// @notice Non-transferable creator allocation that begins vesting only after successful graduation.
contract VOIDTreasuryVesting {
    using SafeERC20 for IERC20;

    uint64 public constant DURATION = 365 days;
    address public immutable beneficiary;
    address public immutable initializer;
    IERC20 public token;
    IVOIDGraduationGate public graduationGate;
    uint256 public released;
    bool public initialized;

    error ZeroAddress();
    error OnlyInitializer();
    error AlreadyInitialized();
    error GraduationPending();
    error NothingToRelease();

    event Initialized(address indexed token, address indexed graduationGate);
    event Released(address indexed beneficiary, uint256 amount);

    constructor(address beneficiary_) {
        if (beneficiary_ == address(0)) revert ZeroAddress();
        beneficiary = beneficiary_;
        initializer = msg.sender;
    }

    function initialize(IERC20 token_, IVOIDGraduationGate gate_) external {
        if (msg.sender != initializer) revert OnlyInitializer();
        if (initialized) revert AlreadyInitialized();
        if (address(token_) == address(0) || address(gate_) == address(0)) revert ZeroAddress();
        token = token_;
        graduationGate = gate_;
        initialized = true;
        emit Initialized(address(token_), address(gate_));
    }

    function vestedAmount(uint64 timestamp) public view returns (uint256) {
        uint64 start = graduationGate.graduatedAt();
        if (start == 0 || timestamp <= start) return 0;
        uint256 allocation = token.balanceOf(address(this)) + released;
        if (timestamp >= start + DURATION) return allocation;
        return allocation * (timestamp - start) / DURATION;
    }

    function releasable() public view returns (uint256) {
        return vestedAmount(uint64(block.timestamp)) - released;
    }

    function release() external returns (uint256 amount) {
        if (graduationGate.graduatedAt() == 0) revert GraduationPending();
        amount = releasable();
        if (amount < 1) revert NothingToRelease();
        released += amount;
        token.safeTransfer(beneficiary, amount);
        emit Released(beneficiary, amount);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {VOIDBondingCurve} from "./VOIDBondingCurve.sol";
import {VOIDCoin} from "./VOIDCoin.sol";

/// @title VOIDLaunch
/// @notice Deploys VOIDCOIN, its continuous curve, and the 12-month Safe vesting allocation.
contract VOIDLaunch {
    using SafeERC20 for IERC20;

    VOIDCoin public immutable token;
    VOIDBondingCurve public immutable bondingCurve;
    VestingWallet public immutable vestingWallet;

    error ZeroAddress();
    error LaunchAllocationNotConsumed();

    constructor(
        address safe,
        address migrationTarget,
        uint256 virtualEthReserve,
        uint256 graduationThreshold,
        string memory initialTokenURI
    ) {
        if (safe == address(0) || migrationTarget == address(0)) revert ZeroAddress();

        VestingWallet vesting = new VestingWallet(safe, uint64(block.timestamp), uint64(365 days));
        VOIDCoin coin = new VOIDCoin(address(this), address(this), address(vesting), initialTokenURI);
        VOIDBondingCurve curve =
            new VOIDBondingCurve(IERC20(address(coin)), safe, migrationTarget, virtualEthReserve, graduationThreshold);
        IERC20(address(coin)).safeTransfer(address(curve), coin.LAUNCH_ALLOCATION());
        if (coin.balanceOf(address(this)) != 0) revert LaunchAllocationNotConsumed();
        coin.transferOwnership(safe);

        token = coin;
        bondingCurve = curve;
        vestingWallet = vesting;
    }
}

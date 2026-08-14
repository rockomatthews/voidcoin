// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VOIDBondingCurve, IVOIDReserveBurner} from "./VOIDBondingCurve.sol";
import {VOIDCoin} from "./VOIDCoin.sol";
import {VOIDTreasuryVesting, IVOIDGraduationGate} from "./VOIDTreasuryVesting.sol";

/// @title VOIDLaunch
/// @notice Deploys VOIDCOIN, its continuous curve, and the post-graduation creator vesting allocation.
contract VOIDLaunch is IVOIDReserveBurner {
    using SafeERC20 for IERC20;

    VOIDCoin public immutable token;
    VOIDBondingCurve public immutable bondingCurve;
    VOIDTreasuryVesting public immutable vestingWallet;

    error ZeroAddress();
    error InvalidContract();
    error LaunchAllocationNotConsumed();
    error OnlyBondingCurve();

    constructor(
        address safe,
        address migrationTarget,
        address positionRecipient,
        uint256 virtualEthReserve,
        uint256 graduationThreshold,
        string memory initialTokenURI
    ) {
        if (safe == address(0) || migrationTarget == address(0) || positionRecipient == address(0)) {
            revert ZeroAddress();
        }
        if (safe.code.length == 0 || migrationTarget.code.length == 0) revert InvalidContract();

        VOIDTreasuryVesting vesting = new VOIDTreasuryVesting(safe);
        VOIDCoin coin = new VOIDCoin(safe, address(this), address(vesting), initialTokenURI);
        VOIDBondingCurve curve = new VOIDBondingCurve(
            IERC20(address(coin)),
            safe,
            address(this),
            migrationTarget,
            positionRecipient,
            virtualEthReserve,
            graduationThreshold
        );
        IERC20(address(coin)).safeTransfer(address(curve), coin.LAUNCH_ALLOCATION());
        curve.initializeTokenReserve();
        vesting.initialize(IERC20(address(coin)), IVOIDGraduationGate(address(curve)));
        if (coin.balanceOf(address(this)) != 0) revert LaunchAllocationNotConsumed();

        token = coin;
        bondingCurve = curve;
        vestingWallet = vesting;
    }

    /// @notice Completes the curve's atomic graduation burn without giving any account a reusable burn authority.
    function burnCurveExcess(uint256 amount) external override {
        if (msg.sender != address(bondingCurve)) revert OnlyBondingCurve();
        token.burnLaunchReserve(amount);
    }
}

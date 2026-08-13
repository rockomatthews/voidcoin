// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {VOIDCoin} from "./VOIDCoin.sol";
import {Distribution, ILiquidityLauncher, IPermit2AllowanceTransfer} from "./interfaces/ILiquidityLauncher.sol";

/// @title VOIDLaunch
/// @notice One-transaction bootstrap into a Uniswap Liquidity Launcher bonding-curve distribution.
contract VOIDLaunch {
    VOIDCoin public immutable token;
    VestingWallet public immutable vestingWallet;

    error ZeroAddress();
    error LaunchAllocationNotConsumed();
    error Permit2ApprovalFailed();
    error LauncherMulticallFailed();

    constructor(
        address safe,
        address launcher,
        address lbpStrategy,
        address permit2,
        string memory initialTokenURI,
        bytes memory lbpConfigData,
        bytes32 launchSalt
    ) {
        if (safe == address(0) || launcher == address(0) || lbpStrategy == address(0) || permit2 == address(0)) {
            revert ZeroAddress();
        }

        VestingWallet vesting = new VestingWallet(safe, uint64(block.timestamp), uint64(365 days));
        VOIDCoin coin = new VOIDCoin(address(this), address(this), address(vesting), initialTokenURI);
        uint256 launchAmount = coin.LAUNCH_ALLOCATION();

        if (!coin.approve(permit2, launchAmount)) revert Permit2ApprovalFailed();
        IPermit2AllowanceTransfer(permit2).approve(address(coin), launcher, uint160(launchAmount), type(uint48).max);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(ILiquidityLauncher.depositToken, (address(coin), uint160(launchAmount)));
        Distribution memory distribution =
            Distribution({strategy: lbpStrategy, amount: uint128(launchAmount), configData: lbpConfigData});
        calls[1] = abi.encodeCall(ILiquidityLauncher.distributeToken, (address(coin), distribution, launchSalt));
        bytes[] memory results = ILiquidityLauncher(launcher).multicall(calls);
        if (results.length != 2) revert LauncherMulticallFailed();

        if (coin.balanceOf(address(this)) != 0) revert LaunchAllocationNotConsumed();
        coin.transferOwnership(safe);

        token = coin;
        vestingWallet = vesting;
    }
}

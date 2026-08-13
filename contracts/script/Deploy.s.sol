// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {VOIDCoin} from "../src/VOIDCoin.sol";
import {VOIDLaunch} from "../src/VOIDLaunch.sol";

contract DeployVOIDCoin is Script {
    function run() external returns (VOIDCoin token, VestingWallet vestingWallet) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address safe = vm.envAddress("SAFE_ADDRESS");
        address launcherAddress = vm.envAddress("UNISWAP_LIQUIDITY_LAUNCHER");
        address lbpStrategy = vm.envAddress("UNISWAP_LBP_STRATEGY");
        address permit2Address = vm.envAddress("PERMIT2_ADDRESS");
        bytes memory lbpConfigData = vm.envBytes("LBP_CONFIG_DATA");
        bytes32 launchSalt = vm.envBytes32("LAUNCH_SALT");
        string memory initialTokenURI = vm.envOr("INITIAL_TOKEN_URI", string(""));

        vm.startBroadcast(deployerKey);
        VOIDLaunch launch = new VOIDLaunch(
            safe, launcherAddress, lbpStrategy, permit2Address, initialTokenURI, lbpConfigData, launchSalt
        );
        vm.stopBroadcast();

        token = launch.token();
        vestingWallet = launch.vestingWallet();

        console2.log("VOIDCoin:", address(token));
        console2.log("Treasury vesting wallet:", address(vestingWallet));
        console2.log("Uniswap Liquidity Launcher:", launcherAddress);
        console2.log("Uniswap LBP strategy:", lbpStrategy);
        console2.log("Pending Safe owner:", safe);
        console2.log("Rename slots paused:", token.renamePaused());
    }
}

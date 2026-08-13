// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {VOIDCoin} from "../src/VOIDCoin.sol";
import {VOIDLaunch} from "../src/VOIDLaunch.sol";
import {VOIDBondingCurve} from "../src/VOIDBondingCurve.sol";

contract DeployVOIDCoin is Script {
    function run() external returns (VOIDCoin token, VestingWallet vestingWallet) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address safe = vm.envAddress("SAFE_ADDRESS");
        address migrationTarget = vm.envAddress("MIGRATION_TARGET");
        uint256 virtualEthReserve = vm.envUint("VIRTUAL_ETH_RESERVE");
        uint256 graduationThreshold = vm.envUint("GRADUATION_THRESHOLD");
        string memory initialTokenURI = vm.envOr("INITIAL_TOKEN_URI", string(""));

        require(safe.code.length > 0, "SAFE_ADDRESS must be a deployed Base Mainnet contract");
        require(migrationTarget.code.length > 0, "MIGRATION_TARGET must be a deployed Base Mainnet contract");
        require(virtualEthReserve > 0, "VIRTUAL_ETH_RESERVE must be nonzero");
        require(graduationThreshold > 0, "GRADUATION_THRESHOLD must be nonzero");
        require(bytes(initialTokenURI).length > 0, "INITIAL_TOKEN_URI must be permanent metadata");

        vm.startBroadcast(deployerKey);
        VOIDLaunch launch =
            new VOIDLaunch(safe, migrationTarget, virtualEthReserve, graduationThreshold, initialTokenURI);
        vm.stopBroadcast();

        token = launch.token();
        vestingWallet = launch.vestingWallet();

        console2.log("VOIDCoin:", address(token));
        console2.log("Treasury vesting wallet:", address(vestingWallet));
        VOIDBondingCurve curve = launch.bondingCurve();
        console2.log("Continuous bonding curve:", address(curve));
        console2.log("Migration target:", migrationTarget);
        console2.log("Virtual ETH reserve:", virtualEthReserve);
        console2.log("Graduation threshold:", graduationThreshold);
        console2.log("Pending Safe owner:", safe);
        console2.log("Competitive renaming paused:", token.renamePaused());
    }
}

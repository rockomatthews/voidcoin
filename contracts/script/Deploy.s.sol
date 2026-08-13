// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {VOIDCoin} from "../src/VOIDCoin.sol";

contract DeployVOIDCoin is Script {
    function run() external returns (VOIDCoin token, VestingWallet vestingWallet) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address safe = vm.envAddress("SAFE_ADDRESS");
        address liquidityReceiver = vm.envAddress("LIQUIDITY_RECEIVER");
        string memory initialTokenURI = vm.envOr("INITIAL_TOKEN_URI", string(""));

        vm.startBroadcast(deployerKey);
        vestingWallet = new VestingWallet(safe, uint64(block.timestamp), uint64(365 days));
        token = new VOIDCoin(deployer, liquidityReceiver, address(vestingWallet), initialTokenURI);
        token.transferOwnership(safe);
        vm.stopBroadcast();

        console2.log("VOIDCoin:", address(token));
        console2.log("Treasury vesting wallet:", address(vestingWallet));
        console2.log("Pending Safe owner:", safe);
        console2.log("Rename slots paused:", token.renamePaused());
    }
}

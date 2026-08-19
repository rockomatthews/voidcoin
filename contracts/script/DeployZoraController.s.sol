// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {VOIDZoraSkinController, IZoraContentCoin} from "../src/VOIDZoraSkinController.sol";

contract DeployZoraController is Script {
    function run() external returns (VOIDZoraSkinController controller) {
        address safe = vm.envAddress("SAFE_ADDRESS");
        address tokenAddress = vm.envAddress("ZORA_VOID_ADDRESS");
        IZoraContentCoin token = IZoraContentCoin(tokenAddress);

        require(block.chainid == 8453, "Base Mainnet only");
        require(safe.code.length > 0, "SAFE_ADDRESS must be a deployed contract");
        require(tokenAddress.code.length > 0, "ZORA_VOID_ADDRESS must be deployed");
        require(token.totalSupply() == 1_000_000_000 ether, "Zora coin must be untouched 1B Content Coin");

        vm.startBroadcast();
        controller = new VOIDZoraSkinController(safe, token);
        vm.stopBroadcast();

        console2.log("Zora VOID token:", tokenAddress);
        console2.log("VOID skin controller:", address(controller));
        console2.log("Controller owner Safe:", controller.owner());
        console2.log("Renaming paused:", controller.renamePaused());
        console2.log("Safe must call token.addOwner(controller):");
        console2.logBytes(abi.encodeWithSignature("addOwner(address)", address(controller)));
        console2.log("Then Safe must call controller.setRenamePaused(false):");
        console2.logBytes(abi.encodeWithSignature("setRenamePaused(bool)", false));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {StdPrecompiles} from "base-std/StdPrecompiles.sol";
import {VOIDB20Bootstrapper} from "../src/VOIDB20Bootstrapper.sol";
import {VOIDB20SkinController} from "../src/VOIDB20SkinController.sol";

/// @notice Deploys the native B20 and paused controller only. It does not create
///         an auction, approve a venue, transfer Safe funds, or unpause renaming.
contract DeployB20V4 is Script {
    address internal constant PRODUCTION_SAFE = 0x30cA25b5de6d9d8eD6Df5a2392211d1F10b266b9;
    string internal constant INITIAL_NAME = "VOIDCOIN";
    string internal constant INITIAL_SYMBOL = "VOID";

    function run() external returns (VOIDB20Bootstrapper bootstrapper) {
        address safe = vm.envAddress("SAFE_ADDRESS");
        bytes32 salt = vm.envBytes32("VOID_B20_SALT");
        string memory contractURI = vm.envString("VOID_B20_CONTRACT_URI");

        require(block.chainid == 8453, "Base Mainnet only");
        require(safe == PRODUCTION_SAFE, "Unexpected production Safe");
        require(safe.code.length > 0, "SAFE_ADDRESS must be a deployed contract");
        require(salt != bytes32(0), "VOID_B20_SALT must be nonzero");
        require(bytes(contractURI).length > 0, "VOID_B20_CONTRACT_URI required");

        vm.startBroadcast();
        bootstrapper =
            new VOIDB20Bootstrapper(safe, StdPrecompiles.B20_FACTORY, salt, INITIAL_NAME, INITIAL_SYMBOL, contractURI);
        vm.stopBroadcast();

        address token = bootstrapper.token();
        VOIDB20SkinController controller = bootstrapper.controller();
        console2.log("VOID B20 token:", token);
        console2.log("VOID B20 bootstrapper:", address(bootstrapper));
        console2.log("VOID B20 skin controller:", address(controller));
        console2.log("Controller owner Safe:", controller.owner());
        console2.log("Controller ready:", controller.controllerReady());
        console2.log("Rename contest paused:", controller.renamePaused());
        console2.log("Supply in Safe:", controller.token().balanceOf(safe));
        console2.log("No auction was created and no Safe transaction was executed.");
    }
}

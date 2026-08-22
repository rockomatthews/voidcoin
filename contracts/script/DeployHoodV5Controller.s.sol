// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IHoodToken, IHoodTokenOwnerRegistry, VOIDHoodSkinController} from "../src/VOIDHoodSkinController.sol";

contract DeployHoodV5Controller is Script {
    uint256 internal constant ROBINHOOD_CHAIN_ID = 4663;
    address internal constant HOOD_OWNER_REGISTRY = 0xEBbf66e306cE0Df652898A4894f6aBAF09F8Cd58;
    address internal constant PRODUCTION_SAFE = 0x30cA25b5de6d9d8eD6Df5a2392211d1F10b266b9;

    function run() external returns (VOIDHoodSkinController controller) {
        require(block.chainid == ROBINHOOD_CHAIN_ID, "Robinhood Chain only");

        address tokenAddress = vm.envAddress("VOID_HOOD_TOKEN");
        IHoodToken token = IHoodToken(tokenAddress);
        IHoodTokenOwnerRegistry registry = IHoodTokenOwnerRegistry(HOOD_OWNER_REGISTRY);

        require(PRODUCTION_SAFE.code.length != 0, "Safe has no code");
        require(tokenAddress.code.length != 0, "Hood token has no code");
        require(registry.ownerOf(tokenAddress) == PRODUCTION_SAFE, "Safe is not Hood token owner");
        require(token.tokenOwner() == PRODUCTION_SAFE, "tokenOwner mismatch");
        uint256 supply = token.totalSupply();
        require(supply <= 1_000_000_000 ether, "supply exceeds nominal launch");
        require(supply + 1_000_000 >= 1_000_000_000 ether, "unexpected launch dust");
        require(keccak256(bytes(token.name())) == keccak256("VOIDCOIN"), "unexpected token name");
        require(keccak256(bytes(token.symbol())) == keccak256("VOID"), "unexpected token symbol");

        vm.startBroadcast();
        controller = new VOIDHoodSkinController(PRODUCTION_SAFE, token, registry);
        vm.stopBroadcast();

        require(controller.owner() == PRODUCTION_SAFE, "controller owner mismatch");
        require(controller.renamePaused(), "controller must start paused");
        require(!controller.controllerReady(), "handoff must remain a separate Safe gate");

        console2.log("VOID Hood token:", tokenAddress);
        console2.log("VOID Hood controller:", address(controller));
        console2.log("Controller owner:", PRODUCTION_SAFE);
        console2.log("Hood ownership registry:", HOOD_OWNER_REGISTRY);
        console2.log("Rename contest paused:", controller.renamePaused());
        console2.log("NEXT SAFE CALL: transferTokenOwnership(token, controller)");
    }
}

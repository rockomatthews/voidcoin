// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IB20} from "base-std/interfaces/IB20.sol";
import {IB20Asset} from "base-std/interfaces/IB20Asset.sol";
import {IB20Factory} from "base-std/interfaces/IB20Factory.sol";
import {B20Constants} from "base-std/lib/B20Constants.sol";
import {B20FactoryLib} from "base-std/lib/B20FactoryLib.sol";
import {VOIDB20SkinController} from "./VOIDB20SkinController.sol";

/// @title VOIDB20Bootstrapper
/// @notice Atomically creates the adminless VOID B20 and its paused rename controller.
/// @dev This contract retains no roles, tokens, ownership, or callable launch surface.
contract VOIDB20Bootstrapper {
    uint256 public constant ORIGINAL_SUPPLY = 1_000_000_000 ether;

    address public immutable token;
    VOIDB20SkinController public immutable controller;

    error InvalidConfiguration();
    error UnexpectedToken();
    error BootstrapInvariantFailed();

    event VOIDB20Created(address indexed token, address indexed controller, address indexed safe, bytes32 salt);

    constructor(
        address safe,
        IB20Factory factory,
        bytes32 salt,
        string memory initialName,
        string memory initialSymbol,
        string memory initialContractURI
    ) {
        if (
            safe == address(0) || safe.code.length == 0 || address(factory) == address(0)
                || bytes(initialName).length == 0 || bytes(initialSymbol).length == 0
                || bytes(initialContractURI).length == 0
        ) revert InvalidConfiguration();

        address predictedToken = factory.getB20Address(IB20Factory.B20Variant.ASSET, address(this), salt);
        VOIDB20SkinController deployedController = new VOIDB20SkinController(safe, IB20(predictedToken));

        bytes[] memory initCalls = new bytes[](5);
        initCalls[0] = B20FactoryLib.encodeUpdateSupplyCap(ORIGINAL_SUPPLY);

        address[] memory recipients = new address[](1);
        recipients[0] = safe;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = ORIGINAL_SUPPLY;
        initCalls[1] = B20FactoryLib.encodeBatchMint(recipients, amounts);
        initCalls[2] = B20FactoryLib.encodeUpdateContractURI(initialContractURI);
        initCalls[3] = B20FactoryLib.encodeGrantRole(B20Constants.BURN_ROLE, address(deployedController));
        initCalls[4] = B20FactoryLib.encodeGrantRole(B20Constants.METADATA_ROLE, address(deployedController));

        bytes memory params = B20FactoryLib.encodeAssetCreateParams(initialName, initialSymbol, address(0), 18);
        address createdToken = factory.createB20(IB20Factory.B20Variant.ASSET, salt, params, initCalls);
        if (createdToken != predictedToken) revert UnexpectedToken();

        _verifyDeployment(safe, factory, createdToken, deployedController);

        token = createdToken;
        controller = deployedController;
        emit VOIDB20Created(createdToken, address(deployedController), safe, salt);
    }

    function _verifyDeployment(
        address safe,
        IB20Factory factory,
        address createdToken,
        VOIDB20SkinController deployedController
    ) private view {
        IB20 b20 = IB20(createdToken);
        if (!factory.isB20(createdToken) || !factory.isB20Initialized(createdToken)) {
            revert BootstrapInvariantFailed();
        }
        if (
            b20.totalSupply() != ORIGINAL_SUPPLY || b20.supplyCap() != ORIGINAL_SUPPLY
                || b20.balanceOf(safe) != ORIGINAL_SUPPLY
        ) revert BootstrapInvariantFailed();
        if (
            !deployedController.controllerReady() || !deployedController.renamePaused()
                || deployedController.owner() != safe
        ) revert BootstrapInvariantFailed();
        if (
            b20.hasRole(B20Constants.DEFAULT_ADMIN_ROLE, safe)
                || b20.hasRole(B20Constants.DEFAULT_ADMIN_ROLE, address(this))
                || b20.hasRole(B20Constants.DEFAULT_ADMIN_ROLE, address(deployedController))
        ) revert BootstrapInvariantFailed();
        if (
            b20.hasRole(B20Constants.MINT_ROLE, safe) || b20.hasRole(B20Constants.MINT_ROLE, address(this))
                || b20.hasRole(B20Constants.MINT_ROLE, address(deployedController))
        ) revert BootstrapInvariantFailed();
        if (
            b20.hasRole(B20Constants.PAUSE_ROLE, safe) || b20.hasRole(B20Constants.UNPAUSE_ROLE, safe)
                || b20.hasRole(B20Constants.BURN_BLOCKED_ROLE, safe) || b20.hasRole(B20Constants.SEIZE_ROLE, safe)
                || IB20Asset(createdToken).hasRole(B20Constants.OPERATOR_ROLE, safe)
        ) revert BootstrapInvariantFailed();
    }
}

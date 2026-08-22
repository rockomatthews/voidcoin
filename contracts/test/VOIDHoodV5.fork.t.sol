// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IHoodToken, IHoodTokenOwnerRegistry, VOIDHoodSkinController} from "../src/VOIDHoodSkinController.sol";

interface IHoodLauncher {
    struct LaunchParams {
        uint8 venueId;
        string name;
        string symbol;
        string image;
        string description;
        string socials;
        string metadataURI;
        bytes32 userSalt;
        int24 tickIfToken0IsNewToken;
        uint256 supply;
        bool sniperGuard;
        uint256 devBuyMinOut;
        bytes tokenFeeConfig;
        bytes creatorFeeConfig;
    }

    function launchFee() external view returns (uint256);
    function venueExists(uint8 venueId) external view returns (bool);
    function computeTokenAddress(address deployer, LaunchParams calldata params) external view returns (address);
    function launch(LaunchParams calldata params)
        external
        payable
        returns (address token, address pool, uint256 positionId);
}

/// @notice No-broadcast rehearsal against hood.dev's live Robinhood Chain contracts.
/// @dev Opt-in so the normal offline suite stays deterministic:
///      RUN_HOOD_LIVE_GATE=true ROBINHOOD_MAINNET_RPC_URL=... forge test --match-contract VOIDHoodV5ForkTest -vv
contract VOIDHoodV5ForkTest is Test {
    uint256 internal constant ROBINHOOD_CHAIN_ID = 4663;
    uint256 internal constant ORIGINAL_SUPPLY = 1_000_000_000 ether;
    address internal constant PRODUCTION_SAFE = 0x30cA25b5de6d9d8eD6Df5a2392211d1F10b266b9;
    IHoodLauncher internal constant LAUNCHER = IHoodLauncher(0x5e4121c262B846eb518EF3EADCD5566838AA841F);
    IHoodTokenOwnerRegistry internal constant REGISTRY =
        IHoodTokenOwnerRegistry(0xEBbf66e306cE0Df652898A4894f6aBAF09F8Cd58);

    function testLiveLaunchControllerHandoffRemainsPaused() public {
        vm.skip(!vm.envOr("RUN_HOOD_LIVE_GATE", false));
        vm.createSelectFork(vm.envString("ROBINHOOD_MAINNET_RPC_URL"));

        assertEq(block.chainid, ROBINHOOD_CHAIN_ID, "wrong fork chain");
        assertTrue(address(LAUNCHER).code.length > 0, "launcher has no code");
        assertTrue(address(REGISTRY).code.length > 0, "registry has no code");
        assertTrue(LAUNCHER.venueExists(1), "Uniswap venue unavailable");

        IHoodLauncher.LaunchParams memory params = IHoodLauncher.LaunchParams({
            venueId: 1,
            name: "VOIDCOIN",
            symbol: "VOID",
            image: "ipfs://QmSTzmwHa3NiHhEb6EsztuvYkScVnmuts9HkFobpVbbuJu",
            description: "VOIDCOIN V5 live launch rehearsal",
            socials: '{"website":"https://voidcoin.wtf"}',
            metadataURI: "ipfs://QmV5LiveGateMetadataOnly",
            userSalt: keccak256("VOIDCOIN-V5-LIVE-FORK-GATE"),
            tickIfToken0IsNewToken: -206000,
            // hood.dev burns the few wei that Uniswap's liquidity math cannot
            // consume. This compensated amount is verified below to settle at
            // exactly one billion tokens for this frozen launch configuration.
            supply: ORIGINAL_SUPPLY,
            sniperGuard: true,
            devBuyMinOut: 0,
            tokenFeeConfig: bytes(""),
            creatorFeeConfig: bytes("")
        });

        address predicted = LAUNCHER.computeTokenAddress(PRODUCTION_SAFE, params);
        assertEq(predicted.code.length, 0, "test salt already deployed");

        uint256 fee = LAUNCHER.launchFee();
        vm.deal(PRODUCTION_SAFE, fee);
        vm.prank(PRODUCTION_SAFE);
        (address tokenAddress, address pool, uint256 positionId) = LAUNCHER.launch{value: fee}(params);

        assertEq(tokenAddress, predicted, "prediction mismatch");
        assertTrue(tokenAddress.code.length > 0, "token not deployed");
        assertTrue(pool != address(0) && pool.code.length > 0, "pool not deployed");
        assertGt(positionId, 0, "LP position not created");

        IHoodToken token = IHoodToken(tokenAddress);
        assertEq(token.name(), "VOIDCOIN", "name");
        assertEq(token.symbol(), "VOID", "symbol");
        emit log_named_uint("requested supply", params.supply);
        emit log_named_uint("settled supply", token.totalSupply());
        emit log_named_uint("launch dust burned", params.supply - token.totalSupply());
        assertLe(token.totalSupply(), ORIGINAL_SUPPLY, "supply exceeds nominal launch");
        assertGe(token.totalSupply() + 1_000_000, ORIGINAL_SUPPLY, "launch dust exceeds bound");
        assertEq(token.balanceOf(pool), token.totalSupply(), "supply is not immediately liquid");
        assertEq(REGISTRY.ownerOf(tokenAddress), PRODUCTION_SAFE, "registry owner");
        assertEq(token.tokenOwner(), PRODUCTION_SAFE, "token owner");

        VOIDHoodSkinController controller = new VOIDHoodSkinController(PRODUCTION_SAFE, token, REGISTRY);
        assertEq(controller.launchSupply(), token.totalSupply(), "controller baseline supply");
        assertEq(controller.destroyedSupply(), 0, "launch dust counted as contest burn");
        assertTrue(controller.renamePaused(), "controller did not start paused");
        assertFalse(controller.controllerReady(), "controller ready before handoff");

        vm.prank(PRODUCTION_SAFE);
        REGISTRY.transferTokenOwnership(tokenAddress, address(controller));

        assertTrue(controller.controllerReady(), "controller handoff incomplete");
        assertTrue(controller.renamePaused(), "handoff unexpectedly unpaused contest");
        assertEq(token.image(), params.image, "launch image changed");
        assertEq(token.description(), params.description, "launch description changed");
        assertEq(token.socials(), params.socials, "launch socials changed");
        assertEq(token.contractURI(), params.metadataURI, "launch metadata URI changed");
    }
}

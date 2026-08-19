// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {VOIDZoraSkinController, IZoraContentCoin} from "../src/VOIDZoraSkinController.sol";

interface ILiveZoraContentCoin is IZoraContentCoin {
    function addOwner(address account) external;
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function tokenURI() external view returns (string memory);
}

contract VOIDZoraSkinControllerForkTest is Test {
    address internal constant SAFE = 0x30cA25b5de6d9d8eD6Df5a2392211d1F10b266b9;
    ILiveZoraContentCoin internal constant TOKEN = ILiveZoraContentCoin(0x4A64F213558Fb0188e3FC48918948EC590A66733);

    address internal burner = makeAddr("forkBurner");
    VOIDZoraSkinController internal controller;

    function setUp() public {
        string memory rpcURL = vm.envOr("BASE_MAINNET_RPC_URL", string(""));
        if (bytes(rpcURL).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpcURL);
        controller = new VOIDZoraSkinController(SAFE, TOKEN);

        vm.prank(SAFE);
        TOKEN.addOwner(address(controller));
        vm.prank(SAFE);
        TOKEN.transfer(burner, 1_000_000 ether);
        vm.prank(SAFE);
        controller.setRenamePaused(false);
    }

    function testLiveZoraCoinBurnAndIdentityMutationAreAtomic() public {
        uint256 supplyBefore = TOKEN.totalSupply();
        string memory newName = "FORK VOID";
        string memory newSymbol = "FORK";
        string memory metadataURI = "ipfs://fork-approved";
        bytes32 imageHash = keccak256("fork-image");
        bytes32 salt = keccak256("fork-salt");
        uint256 burnAmount = controller.INITIAL_BURN();
        bytes32 commitment = controller.proposalCommitment(
            1, burner, burnAmount, newName, newSymbol, imageHash, keccak256(bytes(metadataURI)), salt
        );

        vm.startPrank(burner);
        TOKEN.approve(address(controller), burnAmount);
        controller.burnForRename(burnAmount, commitment);
        vm.stopPrank();

        assertEq(TOKEN.totalSupply(), supplyBefore - burnAmount);
        assertEq(TOKEN.balanceOf(address(controller)), 0);

        vm.prank(SAFE);
        controller.approveRename(1, newName, newSymbol, metadataURI, imageHash, salt);

        assertEq(TOKEN.name(), newName);
        assertEq(TOKEN.symbol(), newSymbol);
        assertEq(TOKEN.tokenURI(), metadataURI);
        assertEq(controller.activeSlot().burner, address(0));
    }
}

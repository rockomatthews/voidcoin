// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {VOIDUniswapV3Migration, IVOIDUniswapV3PositionManager} from "../src/VOIDUniswapV3Migration.sol";
import {VOIDPositionLocker} from "../src/VOIDPositionLocker.sol";

interface IVOIDPositionOwner {
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract ForkLaunchToken is ERC20 {
    constructor() ERC20("VOID Fork Rehearsal", "VFORK") {
        _mint(msg.sender, 980_000_000 ether);
    }
}

/// @dev Run explicitly with `forge test --root contracts --fork-url <BASE_MAINNET_RPC> --match-contract VOIDUniswapV3MigrationForkTest`.
contract VOIDUniswapV3MigrationForkTest is Test {
    address internal constant POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;

    receive() external payable {}

    function testBaseMainnetPositionManagerCreatesAndTransfersFullRangePosition() public {
        if (block.chainid != 8453) return;

        address beneficiary = makeAddr("fork-safe");
        ForkLaunchToken token = new ForkLaunchToken();
        VOIDUniswapV3Migration adapter =
            new VOIDUniswapV3Migration(IVOIDUniswapV3PositionManager(POSITION_MANAGER), address(this));
        VOIDPositionLocker locker = new VOIDPositionLocker(IERC721(POSITION_MANAGER), address(adapter), beneficiary);
        uint256 tokenAmount = 900_000_000 ether;
        uint256 ethAmount = 2 ether;
        vm.deal(address(this), ethAmount);
        IERC20(address(token)).approve(address(adapter), tokenAmount);

        vm.recordLogs();
        bytes32 outcome = adapter.migrate{value: ethAmount}(address(token), tokenAmount, address(locker));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertNotEq(outcome, bytes32(0));
        assertEq(token.balanceOf(address(adapter)), 0);
        assertEq(address(adapter).balance, 0);

        bytes32 signature =
            keccak256("PositionCreated(address,address,address,uint256,uint128,uint256,uint256,uint256,uint256)");
        uint256 tokenId;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(adapter) && logs[i].topics[0] == signature) {
                (tokenId,,,,,) = abi.decode(logs[i].data, (uint256, uint128, uint256, uint256, uint256, uint256));
                break;
            }
        }
        assertGt(tokenId, 0);
        assertEq(IVOIDPositionOwner(POSITION_MANAGER).ownerOf(tokenId), address(locker));
        assertEq(locker.unlockAt(tokenId), uint64(block.timestamp + locker.LOCK_DURATION()));
    }
}

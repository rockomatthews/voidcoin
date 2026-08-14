// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title VOIDPositionLocker
/// @notice Immutable custody for VOIDCOIN's Uniswap v3 position, locked for 12 months from graduation.
contract VOIDPositionLocker is IERC721Receiver, ReentrancyGuard {
    uint64 public constant LOCK_DURATION = 365 days;
    IERC721 public immutable positionManager;
    address public immutable migrationAdapter;
    address public immutable beneficiary;
    mapping(uint256 tokenId => uint64 unlockAt) public unlockAt;

    error ZeroAddress();
    error InvalidContract();
    error OnlyMigrationAdapter();
    error UnsupportedNFT();
    error PositionNotHeld();
    error AlreadyRegistered();
    error PositionLocked();

    event PositionRegistered(uint256 indexed tokenId, uint64 unlockAt);
    event PositionReleased(uint256 indexed tokenId, address indexed beneficiary);

    constructor(IERC721 positionManager_, address migrationAdapter_, address beneficiary_) {
        if (address(positionManager_) == address(0) || migrationAdapter_ == address(0) || beneficiary_ == address(0)) {
            revert ZeroAddress();
        }
        if (address(positionManager_).code.length == 0 || migrationAdapter_.code.length == 0) {
            revert InvalidContract();
        }
        positionManager = positionManager_;
        migrationAdapter = migrationAdapter_;
        beneficiary = beneficiary_;
    }

    function registerPosition(uint256 tokenId) external {
        if (msg.sender != migrationAdapter) revert OnlyMigrationAdapter();
        if (positionManager.ownerOf(tokenId) != address(this)) revert PositionNotHeld();
        if (unlockAt[tokenId] != 0) revert AlreadyRegistered();
        // block.timestamp cannot approach uint64 overflow on any realistic EVM deployment horizon.
        uint64 releaseAt = uint64(block.timestamp + LOCK_DURATION);
        unlockAt[tokenId] = releaseAt;
        emit PositionRegistered(tokenId, releaseAt);
    }

    function release(uint256 tokenId) external nonReentrant {
        uint64 releaseAt = unlockAt[tokenId];
        if (releaseAt == 0 || block.timestamp < releaseAt) revert PositionLocked();
        if (positionManager.ownerOf(tokenId) != address(this)) revert PositionNotHeld();
        delete unlockAt[tokenId];
        positionManager.transferFrom(address(this), beneficiary, tokenId);
        emit PositionReleased(tokenId, beneficiary);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender != address(positionManager)) revert UnsupportedNFT();
        return IERC721Receiver.onERC721Received.selector;
    }
}

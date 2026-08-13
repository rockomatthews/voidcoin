// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title VOIDCoin
/// @notice Fixed-supply ERC-20 whose public identity changes only after an exact burn and Safe approval.
contract VOIDCoin is ERC20, Ownable2Step {
    uint256 public constant ORIGINAL_SUPPLY = 1_000_000_000 ether;
    uint256 public constant BURN_AMOUNT = 1_000_000 ether;
    uint256 public constant SLOT_DURATION = 72 hours;
    uint256 public constant RENAME_COOLDOWN = 2 minutes;
    uint256 public constant LIQUIDITY_ALLOCATION = 900_000_000 ether;
    uint256 public constant TREASURY_ALLOCATION = 100_000_000 ether;

    struct RenameSlot {
        uint256 burnId;
        address burner;
        bytes32 commitment;
        uint64 openedAt;
        uint64 expiresAt;
    }

    string private _currentName;
    string private _currentSymbol;
    string private _currentTokenURI;
    uint256 public currentBurnId;
    uint64 public lastSkinChangeAt;
    bool public renamePaused;
    RenameSlot private _activeSlot;

    error RenamePaused();
    error SlotAlreadyActive();
    error NoActiveSlot();
    error SlotExpired();
    error SlotNotExpired();
    error CooldownActive();
    error NotActiveBurner();
    error ZeroCommitment();
    error InvalidName();
    error InvalidSymbol();
    error InvalidMetadataURI();
    error CommitmentMismatch();
    error InvalidAllocationAddress();

    event RenameBurned(
        uint256 indexed burnId, address indexed burner, bytes32 indexed commitment, uint256 amount, uint256 expiresAt
    );
    event CommitmentReplaced(uint256 indexed burnId, address indexed burner, bytes32 indexed commitment);
    event SkinChanged(
        uint256 indexed burnId,
        address indexed burner,
        string name,
        string symbol,
        string metadataURI,
        bytes32 imageHash
    );
    event RenameSlotExpired(uint256 indexed burnId, address indexed burner);
    event RenamePauseChanged(bool paused);

    constructor(
        address initialOwner,
        address liquidityReceiver,
        address treasuryVestingWallet,
        string memory initialTokenURI
    ) ERC20("VOIDCOIN", "VOID") Ownable(initialOwner) {
        if (liquidityReceiver == address(0) || treasuryVestingWallet == address(0)) {
            revert InvalidAllocationAddress();
        }

        _currentName = "VOIDCOIN";
        _currentSymbol = "VOID";
        _currentTokenURI = initialTokenURI;
        renamePaused = true;

        _mint(liquidityReceiver, LIQUIDITY_ALLOCATION);
        _mint(treasuryVestingWallet, TREASURY_ALLOCATION);
    }

    function name() public view override returns (string memory) {
        return _currentName;
    }

    function symbol() public view override returns (string memory) {
        return _currentSymbol;
    }

    function tokenURI() external view returns (string memory) {
        return _currentTokenURI;
    }

    function activeSlot() external view returns (RenameSlot memory) {
        return _activeSlot;
    }

    function destroyedSupply() external view returns (uint256) {
        return ORIGINAL_SUPPLY - totalSupply();
    }

    function nextBurnId() external view returns (uint256) {
        return currentBurnId + 1;
    }

    function cooldownEndsAt() public view returns (uint256) {
        return lastSkinChangeAt > 0 ? uint256(lastSkinChangeAt) + RENAME_COOLDOWN : 0;
    }

    function proposalCommitment(
        uint256 burnId,
        address burner,
        string calldata proposedName,
        string calldata proposedSymbol,
        bytes32 imageHash,
        bytes32 salt
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(block.chainid, address(this), burnId, burner, proposedName, proposedSymbol, imageHash, salt)
        );
    }

    function burnForRename(bytes32 commitment) external {
        if (renamePaused) revert RenamePaused();
        if (_activeSlot.burner != address(0)) revert SlotAlreadyActive();
        if (commitment == bytes32(0)) revert ZeroCommitment();
        if (lastSkinChangeAt > 0 && block.timestamp < cooldownEndsAt()) revert CooldownActive();

        uint256 burnId = ++currentBurnId;
        uint64 openedAt = uint64(block.timestamp);
        uint64 expiresAt = uint64(block.timestamp + SLOT_DURATION);

        _burn(msg.sender, BURN_AMOUNT);
        _activeSlot = RenameSlot(burnId, msg.sender, commitment, openedAt, expiresAt);

        emit RenameBurned(burnId, msg.sender, commitment, BURN_AMOUNT, expiresAt);
    }

    function replaceCommitment(bytes32 newCommitment) external {
        RenameSlot memory slot = _activeSlot;
        if (slot.burner == address(0)) revert NoActiveSlot();
        if (block.timestamp >= slot.expiresAt) revert SlotExpired();
        if (msg.sender != slot.burner) revert NotActiveBurner();
        if (newCommitment == bytes32(0)) revert ZeroCommitment();

        _activeSlot.commitment = newCommitment;
        emit CommitmentReplaced(slot.burnId, slot.burner, newCommitment);
    }

    function approveRename(
        uint256 burnId,
        string calldata proposedName,
        string calldata proposedSymbol,
        string calldata metadataURI,
        bytes32 imageHash,
        bytes32 salt
    ) external onlyOwner {
        RenameSlot memory slot = _activeSlot;
        if (slot.burner == address(0)) revert NoActiveSlot();
        if (block.timestamp >= slot.expiresAt) revert SlotExpired();
        if (slot.burnId != burnId) revert CommitmentMismatch();
        if (!_validName(bytes(proposedName))) revert InvalidName();
        if (!_validSymbol(bytes(proposedSymbol))) revert InvalidSymbol();
        if (bytes(metadataURI).length == 0 || bytes(metadataURI).length > 512) revert InvalidMetadataURI();

        bytes32 expected = proposalCommitment(burnId, slot.burner, proposedName, proposedSymbol, imageHash, salt);
        if (expected != slot.commitment) revert CommitmentMismatch();

        _currentName = proposedName;
        _currentSymbol = proposedSymbol;
        _currentTokenURI = metadataURI;
        lastSkinChangeAt = uint64(block.timestamp);
        delete _activeSlot;

        emit SkinChanged(burnId, slot.burner, proposedName, proposedSymbol, metadataURI, imageHash);
    }

    function expireSlot() external {
        RenameSlot memory slot = _activeSlot;
        if (slot.burner == address(0)) revert NoActiveSlot();
        if (block.timestamp < slot.expiresAt) revert SlotNotExpired();

        delete _activeSlot;
        emit RenameSlotExpired(slot.burnId, slot.burner);
    }

    function setRenamePaused(bool paused) external onlyOwner {
        renamePaused = paused;
        emit RenamePauseChanged(paused);
    }

    function _validName(bytes memory value) private pure returns (bool) {
        if (value.length == 0 || value.length > 15 || value[0] == 0x20 || value[value.length - 1] == 0x20) {
            return false;
        }

        bool previousSpace = false;
        for (uint256 i; i < value.length; ++i) {
            bytes1 char = value[i];
            bool alphanumeric =
                (char >= 0x30 && char <= 0x39) || (char >= 0x41 && char <= 0x5A) || (char >= 0x61 && char <= 0x7A);
            bool isSpace = char == 0x20;
            if (!alphanumeric && !isSpace) return false;
            if (isSpace && previousSpace) return false;
            previousSpace = isSpace;
        }
        return true;
    }

    function _validSymbol(bytes memory value) private pure returns (bool) {
        if (value.length == 0 || value.length > 10) return false;
        for (uint256 i; i < value.length; ++i) {
            bytes1 char = value[i];
            bool alphanumeric =
                (char >= 0x30 && char <= 0x39) || (char >= 0x41 && char <= 0x5A) || (char >= 0x61 && char <= 0x7A);
            if (!alphanumeric) return false;
        }
        return true;
    }
}

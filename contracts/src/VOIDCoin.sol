// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title VOIDCoin
/// @notice Fixed-supply ERC-20 whose public identity is controlled by an escalating burn record and Safe approval.
contract VOIDCoin is ERC20, Ownable2Step {
    uint256 public constant ORIGINAL_SUPPLY = 1_000_000_000 ether;
    uint256 public constant INITIAL_BURN = 1_000_000 ether;
    uint256 public constant TAKEOVER_INCREMENT = 250_000 ether;
    uint256 public constant MAX_STRATEGIC_PREMIUM = 2_000_000 ether;
    uint256 public constant LAUNCH_ALLOCATION = 980_000_000 ether;
    uint256 public constant TREASURY_ALLOCATION = 20_000_000 ether;
    uint64 public constant SLOT_TTL = 72 hours;
    uint64 public constant APPROVAL_LOCK_DURATION = 6 hours;

    struct RenameSlot {
        uint256 burnId;
        address burner;
        uint256 burnAmount;
        bytes32 commitment;
        uint64 openedAt;
        uint64 lockedUntil;
    }

    string private _currentName;
    string private _currentSymbol;
    string private _currentTokenURI;
    uint256 public currentBurnId;
    uint256 public recordBurn;
    address public recordBurner;
    bool public renamePaused;
    RenameSlot private _activeSlot;

    error RenamePaused();
    error NoActiveSlot();
    error NotActiveBurner();
    error ZeroCommitment();
    error BurnBelowRequirement();
    error BurnAboveMaximum();
    error InvalidName();
    error InvalidSymbol();
    error InvalidMetadataURI();
    error CommitmentMismatch();
    error InvalidAllocationAddress();
    error SlotLocked();
    error SlotExpired();
    error SlotNotExpired();
    error AlreadyLocked();
    error RenouncingDisabled();

    event RenameBurned(
        uint256 indexed burnId,
        address indexed burner,
        bytes32 indexed commitment,
        uint256 amount,
        uint256 previousRecord
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
    event RenamePauseChanged(bool paused);
    event RenameSlotLocked(uint256 indexed burnId, uint64 lockedUntil);
    event RenameSlotExpired(uint256 indexed burnId, address indexed burner);

    constructor(
        address initialOwner,
        address launchReceiver,
        address treasuryVestingWallet,
        string memory initialTokenURI
    ) ERC20("VOIDCOIN", "VOID") Ownable(initialOwner) {
        if (launchReceiver == address(0) || treasuryVestingWallet == address(0)) {
            revert InvalidAllocationAddress();
        }

        _currentName = "VOIDCOIN";
        _currentSymbol = "VOID";
        _currentTokenURI = initialTokenURI;
        renamePaused = true;

        _mint(launchReceiver, LAUNCH_ALLOCATION);
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

    function nextBurnRequirement() public view returns (uint256) {
        return recordBurn == 0 ? INITIAL_BURN : recordBurn + TAKEOVER_INCREMENT;
    }

    function maximumBurnAmount() public view returns (uint256) {
        return nextBurnRequirement() + MAX_STRATEGIC_PREMIUM;
    }

    function proposalCommitment(
        uint256 burnId,
        address burner,
        uint256 burnAmount,
        string calldata proposedName,
        string calldata proposedSymbol,
        bytes32 imageHash,
        bytes32 metadataURIHash,
        bytes32 salt
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                block.chainid,
                address(this),
                burnId,
                burner,
                burnAmount,
                proposedName,
                proposedSymbol,
                imageHash,
                metadataURIHash,
                salt
            )
        );
    }

    function burnForRename(uint256 burnAmount, bytes32 commitment) external {
        if (renamePaused) revert RenamePaused();
        if (commitment == bytes32(0)) revert ZeroCommitment();
        if (_activeSlot.lockedUntil != 0 && block.timestamp <= _activeSlot.lockedUntil) revert SlotLocked();

        uint256 minimumAmount = nextBurnRequirement();
        if (burnAmount < minimumAmount) revert BurnBelowRequirement();
        if (burnAmount > minimumAmount + MAX_STRATEGIC_PREMIUM) revert BurnAboveMaximum();
        uint256 previousRecord = recordBurn;
        uint256 burnId = ++currentBurnId;
        uint64 openedAt = uint64(block.timestamp);

        _burn(msg.sender, burnAmount);
        recordBurn = burnAmount;
        recordBurner = msg.sender;
        _activeSlot = RenameSlot(burnId, msg.sender, burnAmount, commitment, openedAt, 0);

        emit RenameBurned(burnId, msg.sender, commitment, burnAmount, previousRecord);
    }

    function replaceCommitment(bytes32 newCommitment) external {
        RenameSlot memory slot = _activeSlot;
        if (slot.burner == address(0)) revert NoActiveSlot();
        if (msg.sender != slot.burner) revert NotActiveBurner();
        if (newCommitment == bytes32(0)) revert ZeroCommitment();
        if (slot.lockedUntil != 0 && block.timestamp <= slot.lockedUntil) revert SlotLocked();
        if (block.timestamp > slot.openedAt + SLOT_TTL) revert SlotExpired();

        _activeSlot.commitment = newCommitment;
        emit CommitmentReplaced(slot.burnId, slot.burner, newCommitment);
    }

    function lockRenameSlot(uint256 burnId) external onlyOwner {
        RenameSlot memory slot = _activeSlot;
        if (slot.burner == address(0)) revert NoActiveSlot();
        if (slot.burnId != burnId) revert CommitmentMismatch();
        if (block.timestamp > slot.openedAt + SLOT_TTL) revert SlotExpired();
        if (slot.lockedUntil != 0 && block.timestamp <= slot.lockedUntil) revert AlreadyLocked();
        uint64 lockedUntil = uint64(block.timestamp + APPROVAL_LOCK_DURATION);
        _activeSlot.lockedUntil = lockedUntil;
        emit RenameSlotLocked(burnId, lockedUntil);
    }

    function expireSlot() external {
        RenameSlot memory slot = _activeSlot;
        if (slot.burner == address(0)) revert NoActiveSlot();
        uint256 expiry = uint256(slot.openedAt) + SLOT_TTL;
        if (slot.lockedUntil > expiry) expiry = slot.lockedUntil;
        if (block.timestamp <= expiry) revert SlotNotExpired();
        delete _activeSlot;
        emit RenameSlotExpired(slot.burnId, slot.burner);
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
        if (slot.burnId != burnId) revert CommitmentMismatch();
        if (block.timestamp > slot.openedAt + SLOT_TTL && block.timestamp > slot.lockedUntil) revert SlotExpired();
        if (!_validName(bytes(proposedName))) revert InvalidName();
        if (!_validSymbol(bytes(proposedSymbol))) revert InvalidSymbol();
        if (bytes(metadataURI).length == 0 || bytes(metadataURI).length > 512) revert InvalidMetadataURI();

        bytes32 expected = proposalCommitment(
            burnId,
            slot.burner,
            slot.burnAmount,
            proposedName,
            proposedSymbol,
            imageHash,
            keccak256(bytes(metadataURI)),
            salt
        );
        if (expected != slot.commitment) revert CommitmentMismatch();

        _currentName = proposedName;
        _currentSymbol = proposedSymbol;
        _currentTokenURI = metadataURI;
        delete _activeSlot;

        emit SkinChanged(burnId, slot.burner, proposedName, proposedSymbol, metadataURI, imageHash);
    }

    function setRenamePaused(bool paused) external onlyOwner {
        renamePaused = paused;
        emit RenamePauseChanged(paused);
    }

    function renounceOwnership() public pure override(Ownable) {
        revert RenouncingDisabled();
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

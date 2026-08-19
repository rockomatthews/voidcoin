// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IZoraContentCoin is IERC20 {
    function burn(uint256 amount) external;
    function setNameAndSymbol(string calldata newName, string calldata newSymbol) external;
    function setContractURI(string calldata newURI) external;
    function isOwner(address account) external view returns (bool);
}

/// @title VOIDZoraSkinController
/// @notice Competitive burn-to-transform controller for a Zora Content Coin on Base.
/// @dev This contract must be added as an owner of the immutable Zora coin. Its only metadata
///      path is an approved, commitment-bound active burn; the Safe cannot bypass the contest.
contract VOIDZoraSkinController is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant ORIGINAL_SUPPLY = 1_000_000_000 ether;
    uint256 public constant INITIAL_BURN = 1_000_000 ether;
    uint256 public constant TAKEOVER_INCREMENT = 250_000 ether;
    uint256 public constant TAKEOVER_INCREASE_BPS = 1_000; // 10%
    uint256 public constant MAX_STRATEGIC_PREMIUM = 2_000_000 ether;
    uint256 public constant BPS = 10_000;
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

    IZoraContentCoin public immutable token;
    uint256 public currentBurnId;
    uint256 public recordBurn;
    uint256 public contestBurned;
    address public recordBurner;
    bool public renamePaused;
    RenameSlot private _activeSlot;

    error InvalidToken();
    error ControllerNotTokenOwner();
    error RenamePaused();
    error NoActiveSlot();
    error NotActiveBurner();
    error ZeroCommitment();
    error UnexpectedBurnId();
    error BurnBelowRequirement();
    error BurnAboveMaximum();
    error BurnDidNotReduceSupply();
    error InvalidName();
    error InvalidSymbol();
    error InvalidMetadataURI();
    error CommitmentMismatch();
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

    constructor(address initialOwner, IZoraContentCoin zoraToken) Ownable(initialOwner) {
        if (address(zoraToken) == address(0) || address(zoraToken).code.length == 0) revert InvalidToken();
        token = zoraToken;
        renamePaused = true;
    }

    function activeSlot() external view returns (RenameSlot memory) {
        return _activeSlot;
    }

    /// @notice All Zora coin burns, including contest burns and any direct holder burns.
    function destroyedSupply() external view returns (uint256) {
        uint256 supply = token.totalSupply();
        return supply >= ORIGINAL_SUPPLY ? 0 : ORIGINAL_SUPPLY - supply;
    }

    function nextBurnId() external view returns (uint256) {
        return currentBurnId + 1;
    }

    function nextBurnRequirement() public view returns (uint256) {
        uint256 previous = recordBurn;
        if (previous == 0) return INITIAL_BURN;

        uint256 fixedIncrease = previous + TAKEOVER_INCREMENT;
        uint256 percentageIncrease = Math.mulDiv(previous, BPS + TAKEOVER_INCREASE_BPS, BPS, Math.Rounding.Ceil);
        return fixedIncrease > percentageIncrease ? fixedIncrease : percentageIncrease;
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

    /// @notice Pulls the approved Zora coin amount and burns it atomically in the Zora token.
    function burnForRename(uint256 expectedBurnId, uint256 burnAmount, bytes32 commitment) external nonReentrant {
        if (renamePaused) revert RenamePaused();
        if (!token.isOwner(address(this))) revert ControllerNotTokenOwner();
        if (commitment == bytes32(0)) revert ZeroCommitment();
        if (_activeSlot.lockedUntil != 0 && block.timestamp <= _activeSlot.lockedUntil) revert SlotLocked();
        if (expectedBurnId != currentBurnId + 1) revert UnexpectedBurnId();

        uint256 minimumAmount = nextBurnRequirement();
        if (burnAmount < minimumAmount) revert BurnBelowRequirement();
        if (burnAmount > minimumAmount + MAX_STRATEGIC_PREMIUM) revert BurnAboveMaximum();

        uint256 supplyBefore = token.totalSupply();
        uint256 previousRecord = recordBurn;
        currentBurnId = expectedBurnId;
        uint64 openedAt = uint64(block.timestamp);
        recordBurn = burnAmount;
        contestBurned += burnAmount;
        recordBurner = msg.sender;
        _activeSlot = RenameSlot(expectedBurnId, msg.sender, burnAmount, commitment, openedAt, 0);

        IERC20(address(token)).safeTransferFrom(msg.sender, address(this), burnAmount);
        token.burn(burnAmount);
        if (token.totalSupply() + burnAmount != supplyBefore) revert BurnDidNotReduceSupply();

        emit RenameBurned(expectedBurnId, msg.sender, commitment, burnAmount, previousRecord);
    }

    function replaceCommitment(uint256 expectedBurnId, bytes32 newCommitment) external {
        RenameSlot memory slot = _activeSlot;
        if (slot.burner == address(0)) revert NoActiveSlot();
        if (msg.sender != slot.burner) revert NotActiveBurner();
        if (slot.burnId != expectedBurnId) revert UnexpectedBurnId();
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
    ) external onlyOwner nonReentrant {
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
        if (!token.isOwner(address(this))) revert ControllerNotTokenOwner();

        delete _activeSlot;
        token.setNameAndSymbol(proposedName, proposedSymbol);
        token.setContractURI(metadataURI);

        emit SkinChanged(burnId, slot.burner, proposedName, proposedSymbol, metadataURI, imageHash);
    }

    function setRenamePaused(bool paused) external onlyOwner {
        if (!paused && !token.isOwner(address(this))) revert ControllerNotTokenOwner();
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

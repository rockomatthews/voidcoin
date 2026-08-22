// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IHoodToken is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function burn(uint256 amount) external;
    function tokenOwner() external view returns (address);
    function image() external view returns (string memory);
    function description() external view returns (string memory);
    function socials() external view returns (string memory);
    function contractURI() external view returns (string memory);
    function setImage(string calldata nextImage) external;
    function setDescription(string calldata nextDescription) external;
    function setSocials(string calldata nextSocials) external;
    function setContractURI(string calldata nextContractURI) external;
}

interface IHoodTokenOwnerRegistry {
    function ownerOf(address token) external view returns (address);
    function transferTokenOwnership(address token, address newOwner) external;
}

/// @title VOIDHoodSkinController
/// @notice Competitive burn-to-transform controller for a hood.dev token on Robinhood Chain.
/// @dev HoodToken name and symbol are immutable. Approved winners update the display identity kept
///      here and the token's mutable image, description, socials, and ERC-7572 contract URI.
contract VOIDHoodSkinController is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant ORIGINAL_SUPPLY = 1_000_000_000 ether;
    /// @dev hood.dev burns the sub-token remainder that Uniswap V3 liquidity
    ///      math cannot place. This bound is deliberately far below one token.
    uint256 public constant MAX_LAUNCH_DUST = 1_000_000;
    uint256 public constant INITIAL_BURN = 1_000_000 ether;
    uint256 public constant TAKEOVER_INCREMENT = 250_000 ether;
    uint256 public constant TAKEOVER_INCREASE_BPS = 1_000;
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

    struct SkinProposal {
        string displayName;
        string displaySymbol;
        string image;
        string description;
        string socials;
        string metadataURI;
    }

    IHoodToken public immutable token;
    IHoodTokenOwnerRegistry public immutable ownerRegistry;
    uint256 public immutable launchSupply;
    string public displayName;
    string public displaySymbol;
    uint256 public currentBurnId;
    uint256 public recordBurn;
    uint256 public contestBurned;
    address public recordBurner;
    bool public renamePaused;
    RenameSlot private _activeSlot;

    error InvalidConfiguration();
    error ControllerNotReady();
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
    error InvalidImage();
    error InvalidDescription();
    error InvalidSocials();
    error InvalidMetadataURI();
    error CommitmentMismatch();
    error SlotLocked();
    error SlotExpired();
    error SlotNotExpired();
    error AlreadyLocked();
    error ActiveSlotExists();
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
        string displayName,
        string displaySymbol,
        string metadataURI,
        bytes32 skinHash
    );
    event RenamePauseChanged(bool paused);
    event RenameSlotLocked(uint256 indexed burnId, uint64 lockedUntil);
    event RenameSlotExpired(uint256 indexed burnId, address indexed burner);
    event TokenControlTransferred(address indexed nextOwner);

    constructor(address initialOwner, IHoodToken hoodToken, IHoodTokenOwnerRegistry registry) Ownable(initialOwner) {
        if (
            initialOwner == address(0) || address(hoodToken) == address(0) || address(registry) == address(0)
                || address(hoodToken).code.length == 0 || address(registry).code.length == 0
        ) revert InvalidConfiguration();

        token = hoodToken;
        ownerRegistry = registry;
        uint256 supply = hoodToken.totalSupply();
        if (supply > ORIGINAL_SUPPLY || supply + MAX_LAUNCH_DUST < ORIGINAL_SUPPLY) {
            revert InvalidConfiguration();
        }
        launchSupply = supply;
        displayName = hoodToken.name();
        displaySymbol = hoodToken.symbol();
        renamePaused = true;
    }

    function activeSlot() external view returns (RenameSlot memory) {
        return _activeSlot;
    }

    function controllerReady() public view returns (bool) {
        return ownerRegistry.ownerOf(address(token)) == address(this) && token.tokenOwner() == address(this);
    }

    function destroyedSupply() external view returns (uint256) {
        uint256 supply = token.totalSupply();
        return supply >= launchSupply ? 0 : launchSupply - supply;
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

    function skinHash(SkinProposal calldata proposal) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                proposal.displayName,
                proposal.displaySymbol,
                keccak256(bytes(proposal.image)),
                keccak256(bytes(proposal.description)),
                keccak256(bytes(proposal.socials)),
                keccak256(bytes(proposal.metadataURI))
            )
        );
    }

    function proposalCommitment(
        uint256 burnId,
        address burner,
        uint256 burnAmount,
        bytes32 proposedSkinHash,
        bytes32 salt
    ) public view returns (bytes32) {
        return keccak256(abi.encode(block.chainid, address(this), burnId, burner, burnAmount, proposedSkinHash, salt));
    }

    function burnForRename(uint256 expectedBurnId, uint256 burnAmount, bytes32 commitment) external nonReentrant {
        if (renamePaused) revert RenamePaused();
        if (!controllerReady()) revert ControllerNotReady();
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

    function approveRename(uint256 burnId, SkinProposal calldata proposal, bytes32 salt)
        external
        onlyOwner
        nonReentrant
    {
        RenameSlot memory slot = _activeSlot;
        if (slot.burner == address(0)) revert NoActiveSlot();
        if (slot.burnId != burnId) revert CommitmentMismatch();
        if (block.timestamp > slot.openedAt + SLOT_TTL && block.timestamp > slot.lockedUntil) revert SlotExpired();
        _validateProposal(proposal);

        bytes32 proposedSkinHash = skinHash(proposal);
        bytes32 expected = proposalCommitment(burnId, slot.burner, slot.burnAmount, proposedSkinHash, salt);
        if (expected != slot.commitment) revert CommitmentMismatch();
        if (!controllerReady()) revert ControllerNotReady();

        delete _activeSlot;
        _applyProposal(proposal);

        emit SkinChanged(
            burnId, slot.burner, proposal.displayName, proposal.displaySymbol, proposal.metadataURI, proposedSkinHash
        );
    }

    function _validateProposal(SkinProposal calldata proposal) private pure {
        if (!_validName(bytes(proposal.displayName))) revert InvalidName();
        if (!_validSymbol(bytes(proposal.displaySymbol))) revert InvalidSymbol();
        if (bytes(proposal.image).length == 0 || bytes(proposal.image).length > 512) revert InvalidImage();
        if (bytes(proposal.description).length == 0 || bytes(proposal.description).length > 2_048) {
            revert InvalidDescription();
        }
        if (bytes(proposal.socials).length == 0 || bytes(proposal.socials).length > 1_024) revert InvalidSocials();
        if (bytes(proposal.metadataURI).length == 0 || bytes(proposal.metadataURI).length > 512) {
            revert InvalidMetadataURI();
        }
    }

    function _applyProposal(SkinProposal calldata proposal) private {
        displayName = proposal.displayName;
        displaySymbol = proposal.displaySymbol;
        token.setImage(proposal.image);
        token.setDescription(proposal.description);
        token.setSocials(proposal.socials);
        token.setContractURI(proposal.metadataURI);
    }

    function setRenamePaused(bool paused) external onlyOwner {
        if (!paused && !controllerReady()) revert ControllerNotReady();
        renamePaused = paused;
        emit RenamePauseChanged(paused);
    }

    /// @notice Paused emergency handoff of every Hood creator power to a replacement owner.
    function transferTokenControl(address nextOwner) external onlyOwner {
        if (!renamePaused || nextOwner == address(0)) revert InvalidConfiguration();
        if (_activeSlot.burner != address(0)) revert ActiveSlotExists();
        if (!controllerReady()) revert ControllerNotReady();
        emit TokenControlTransferred(nextOwner);
        ownerRegistry.transferTokenOwnership(address(token), nextOwner);
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

// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

interface IVOIDMigrationTarget {
    function migrate(address token, uint256 tokenAmount, address positionRecipient)
        external
        payable
        returns (bytes32 outcomeId);
}

/// @title VOIDBondingCurve
/// @notice Buyer-funded constant-product market with internally accounted reserves and recoverable graduation.
contract VOIDBondingCurve is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10_000;
    uint256 public constant TRADE_FEE_BPS = 100;
    uint256 public constant MIGRATION_DELAY = 2 days;

    IERC20 public immutable token;
    address public immutable reserveInitializer;
    address public immutable positionRecipient;
    uint256 public immutable virtualEthReserve;
    uint256 public immutable graduationThreshold;

    address public migrationTarget;
    address public pendingMigrationTarget;
    uint64 public pendingMigrationTargetAt;
    uint256 public ethReserve;
    uint256 public accountedTokenReserve;
    uint64 public graduatedAt;
    bool public reservesInitialized;
    bool public graduated;

    error ZeroAddress();
    error InvalidConfiguration();
    error ZeroInput();
    error SlippageExceeded();
    error InsufficientCurveLiquidity();
    error CurveClosed();
    error GraduationNotReady();
    error MigrationFailed();
    error DirectEthDisabled();
    error DeadlineExpired();
    error OnlyReserveInitializer();
    error AlreadyInitialized();
    error MigrationDelayActive();
    error RenouncingDisabled();
    error NoExcess();

    event TokensPurchased(address indexed buyer, uint256 ethIn, uint256 fee, uint256 tokensOut);
    event TokensSold(address indexed seller, uint256 tokensIn, uint256 feeTokens, uint256 ethOut);
    event GraduationThresholdReached(uint256 ethReserve, uint256 tokenReserve);
    event MigrationTargetProposed(address indexed target, uint64 executableAt);
    event MigrationTargetChanged(address indexed previousTarget, address indexed newTarget);
    event Graduated(
        address indexed migrationTarget,
        address indexed positionRecipient,
        bytes32 indexed outcomeId,
        uint256 ethAmount,
        uint256 tokenAmount
    );
    event ExcessSwept(address indexed recipient, uint256 ethAmount, uint256 tokenAmount);

    constructor(
        IERC20 token_,
        address initialOwner,
        address reserveInitializer_,
        address migrationTarget_,
        address positionRecipient_,
        uint256 virtualEthReserve_,
        uint256 graduationThreshold_
    ) Ownable(initialOwner) {
        if (
            address(token_) == address(0) || initialOwner == address(0) || reserveInitializer_ == address(0)
                || migrationTarget_ == address(0) || positionRecipient_ == address(0)
        ) revert ZeroAddress();
        if (migrationTarget_.code.length == 0) revert InvalidConfiguration();
        if (virtualEthReserve_ == 0 || graduationThreshold_ == 0) revert InvalidConfiguration();
        token = token_;
        reserveInitializer = reserveInitializer_;
        migrationTarget = migrationTarget_;
        positionRecipient = positionRecipient_;
        virtualEthReserve = virtualEthReserve_;
        graduationThreshold = graduationThreshold_;
    }

    receive() external payable {
        revert DirectEthDisabled();
    }

    function initializeTokenReserve() external {
        if (msg.sender != reserveInitializer) revert OnlyReserveInitializer();
        if (reservesInitialized) revert AlreadyInitialized();
        uint256 reserve = token.balanceOf(address(this));
        if (reserve < 1) revert InvalidConfiguration();
        accountedTokenReserve = reserve;
        reservesInitialized = true;
    }

    function tokenReserve() public view returns (uint256) {
        return accountedTokenReserve;
    }

    function graduationReady() public view returns (bool) {
        return !graduated && ethReserve >= graduationThreshold;
    }

    function quoteBuy(uint256 ethIn) public view returns (uint256 tokensOut) {
        if (ethIn == 0 || !reservesInitialized || graduated) return 0;
        uint256 effectiveEthIn = ethIn - Math.mulDiv(ethIn, TRADE_FEE_BPS, BPS, Math.Rounding.Ceil);
        if (effectiveEthIn == 0) return 0;
        uint256 invariant = (virtualEthReserve + ethReserve) * accountedTokenReserve;
        uint256 tokensAfter = Math.ceilDiv(invariant, virtualEthReserve + ethReserve + effectiveEthIn);
        if (tokensAfter >= accountedTokenReserve) return 0;
        tokensOut = accountedTokenReserve - tokensAfter;
    }

    function quoteSell(uint256 tokensIn) public view returns (uint256 ethOut) {
        if (tokensIn == 0 || !reservesInitialized || graduated) return 0;
        uint256 feeTokens = Math.mulDiv(tokensIn, TRADE_FEE_BPS, BPS, Math.Rounding.Ceil);
        if (feeTokens >= tokensIn) return 0;
        uint256 effectiveTokensIn = tokensIn - feeTokens;
        uint256 invariant = (virtualEthReserve + ethReserve) * accountedTokenReserve;
        uint256 ethAfterWithVirtual = Math.ceilDiv(invariant, accountedTokenReserve + effectiveTokensIn);
        uint256 currentEthWithVirtual = virtualEthReserve + ethReserve;
        if (ethAfterWithVirtual >= currentEthWithVirtual) return 0;
        ethOut = currentEthWithVirtual - ethAfterWithVirtual;
        if (ethOut > ethReserve) revert InsufficientCurveLiquidity();
    }

    /// @notice Largest gross token input the accounted ETH reserve can currently redeem.
    /// @dev This is conservative because integer rounding always favors the pool.
    function maxSellable() public view returns (uint256 tokensIn) {
        if (!reservesInitialized || graduated || ethReserve == 0) return 0;
        uint256 invariant = (virtualEthReserve + ethReserve) * accountedTokenReserve;
        uint256 maximumPricedReserve = invariant / virtualEthReserve;
        if (maximumPricedReserve <= accountedTokenReserve) return 0;
        uint256 maximumEffectiveInput = maximumPricedReserve - accountedTokenReserve;
        tokensIn = Math.mulDiv(maximumEffectiveInput, BPS, BPS - TRADE_FEE_BPS);
    }

    function buy(uint256 minimumTokensOut, uint256 deadline) external payable nonReentrant returns (uint256 tokensOut) {
        if (graduated) revert CurveClosed();
        if (!reservesInitialized) revert InvalidConfiguration();
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (msg.value == 0 || minimumTokensOut == 0) revert ZeroInput();

        uint256 fee = Math.mulDiv(msg.value, TRADE_FEE_BPS, BPS, Math.Rounding.Ceil);
        uint256 effectiveEthIn = msg.value - fee;
        if (effectiveEthIn == 0) revert ZeroInput();
        uint256 invariant = (virtualEthReserve + ethReserve) * accountedTokenReserve;
        uint256 tokensAfter = Math.ceilDiv(invariant, virtualEthReserve + ethReserve + effectiveEthIn);
        if (tokensAfter >= accountedTokenReserve) revert InsufficientCurveLiquidity();
        tokensOut = accountedTokenReserve - tokensAfter;
        if (tokensOut < minimumTokensOut) revert SlippageExceeded();

        bool wasReady = graduationReady();
        ethReserve += msg.value;
        accountedTokenReserve = tokensAfter;
        token.safeTransfer(msg.sender, tokensOut);
        emit TokensPurchased(msg.sender, msg.value, fee, tokensOut);
        if (!wasReady && graduationReady()) emit GraduationThresholdReached(ethReserve, accountedTokenReserve);
    }

    function sell(uint256 tokensIn, uint256 minimumEthOut, uint256 deadline)
        external
        nonReentrant
        returns (uint256 ethOut)
    {
        if (graduated) revert CurveClosed();
        if (!reservesInitialized) revert InvalidConfiguration();
        if (block.timestamp > deadline) revert DeadlineExpired();
        if (tokensIn == 0 || minimumEthOut == 0) revert ZeroInput();

        uint256 feeTokens = Math.mulDiv(tokensIn, TRADE_FEE_BPS, BPS, Math.Rounding.Ceil);
        if (feeTokens >= tokensIn) revert ZeroInput();
        uint256 effectiveTokensIn = tokensIn - feeTokens;
        uint256 invariant = (virtualEthReserve + ethReserve) * accountedTokenReserve;
        uint256 newTokenReserveForPrice = accountedTokenReserve + effectiveTokensIn;
        uint256 ethAfterWithVirtual = Math.ceilDiv(invariant, newTokenReserveForPrice);
        uint256 currentEthWithVirtual = virtualEthReserve + ethReserve;
        if (ethAfterWithVirtual >= currentEthWithVirtual) revert InsufficientCurveLiquidity();
        ethOut = currentEthWithVirtual - ethAfterWithVirtual;
        if (ethOut > ethReserve) revert InsufficientCurveLiquidity();
        if (ethOut < minimumEthOut) revert SlippageExceeded();

        token.safeTransferFrom(msg.sender, address(this), tokensIn);
        accountedTokenReserve += tokensIn;
        ethReserve -= ethOut;
        Address.sendValue(payable(msg.sender), ethOut);
        emit TokensSold(msg.sender, tokensIn, feeTokens, ethOut);
    }

    function proposeMigrationTarget(address newTarget) external onlyOwner {
        if (newTarget == address(0) || newTarget.code.length == 0) revert InvalidConfiguration();
        pendingMigrationTarget = newTarget;
        pendingMigrationTargetAt = uint64(block.timestamp + MIGRATION_DELAY);
        emit MigrationTargetProposed(newTarget, pendingMigrationTargetAt);
    }

    function acceptMigrationTarget() external onlyOwner {
        address nextTarget = pendingMigrationTarget;
        if (nextTarget == address(0) || block.timestamp < pendingMigrationTargetAt) revert MigrationDelayActive();
        address previous = migrationTarget;
        migrationTarget = nextTarget;
        delete pendingMigrationTarget;
        delete pendingMigrationTargetAt;
        emit MigrationTargetChanged(previous, nextTarget);
    }

    function graduate() external onlyOwner nonReentrant {
        if (!graduationReady()) revert GraduationNotReady();
        address target = migrationTarget;
        if (target.code.length == 0) revert MigrationFailed();
        uint256 tokens = accountedTokenReserve;
        uint256 eth = ethReserve;
        uint256 tokenBalanceBefore = token.balanceOf(address(this));
        uint256 ethBalanceBefore = address(this).balance;

        // Effects are applied before the adapter call. Any failed call or post-condition reverts them atomically.
        accountedTokenReserve = 0;
        ethReserve = 0;
        graduated = true;
        graduatedAt = uint64(block.timestamp);
        token.forceApprove(target, tokens);
        bytes32 outcomeId = bytes32(0);
        try IVOIDMigrationTarget(target).migrate{value: eth}(address(token), tokens, positionRecipient) returns (
            bytes32 result
        ) {
            outcomeId = result;
        } catch {
            revert MigrationFailed();
        }
        if (outcomeId == bytes32(0)) revert MigrationFailed();
        // nonReentrant blocks state-changing callbacks; this balance delta is the adapter success post-condition.
        // slither-disable-next-line reentrancy-balance
        if (token.balanceOf(address(this)) != tokenBalanceBefore - tokens) revert MigrationFailed();
        if (address(this).balance != ethBalanceBefore - eth) revert MigrationFailed();

        emit Graduated(target, positionRecipient, outcomeId, eth, tokens);
    }

    function sweepExcess(address payable recipient) external onlyOwner nonReentrant {
        if (recipient == address(0)) revert ZeroAddress();
        uint256 excessEth = address(this).balance - ethReserve;
        uint256 excessTokens = token.balanceOf(address(this)) - accountedTokenReserve;
        if ((excessEth | excessTokens) < 1) revert NoExcess();
        if (excessTokens > 0) token.safeTransfer(recipient, excessTokens);
        if (excessEth > 0) Address.sendValue(recipient, excessEth);
        emit ExcessSwept(recipient, excessEth, excessTokens);
    }

    function renounceOwnership() public pure override(Ownable) {
        revert RenouncingDisabled();
    }
}

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
        returns (bytes32 outcomeId, uint256 tokenId);

    function seed(address token, uint256 tokenAmount, address positionRecipient)
        external
        payable
        returns (bytes32 outcomeId, uint256 tokenId, uint256 tokenUsed, uint256 ethUsed);
}

interface IVOIDPositionCustody {
    function isRegisteredPosition(uint256 tokenId, address registrar) external view returns (bool);
}

interface IVOIDReserveBurner {
    function burnCurveExcess(uint256 amount) external;
}

/// @title VOIDBondingCurve
/// @notice Buyer-funded constant-product market with internally accounted reserves and recoverable graduation.
contract VOIDBondingCurve is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10_000;
    uint256 public constant TRADE_FEE_BPS = 100;
    uint256 public constant MAX_BUY_BPS_OF_VIRTUAL_RESERVE = 100;
    uint256 public constant POOL_SEED_BPS = 10;
    uint256 public constant MIGRATION_DELAY = 2 days;
    uint256 public constant MIGRATION_PROPOSAL_WINDOW = 7 days;

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
    uint256 public seededTokenLiquidity;
    uint256 public seededEthLiquidity;
    address public seededMigrationTarget;
    uint64 public graduatedAt;
    uint64 public thresholdReachedAt;
    bool public reservesInitialized;
    bool public poolSeeded;
    bool public graduated;

    error ZeroAddress();
    error InvalidConfiguration();
    error ZeroInput();
    error BuyTooLarge();
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
    error MigrationProposalExpired();
    error NoMigrationProposal();
    error RenouncingDisabled();
    error NoExcess();
    error PoolAlreadySeeded();
    error PoolNotSeeded();
    error MigrationChangePending();

    event TokensPurchased(address indexed buyer, uint256 ethIn, uint256 fee, uint256 tokensOut);
    event TokensSold(address indexed seller, uint256 tokensIn, uint256 feeTokens, uint256 ethOut);
    event GraduationThresholdReached(uint256 ethReserve, uint256 tokenReserve);
    event MigrationTargetProposed(address indexed target, uint64 executableAt);
    event MigrationTargetChanged(address indexed previousTarget, address indexed newTarget);
    event MigrationTargetProposalCancelled(address indexed target);
    event MigrationPoolSeeded(
        address indexed migrationTarget,
        address indexed positionRecipient,
        bytes32 indexed outcomeId,
        uint256 positionTokenId,
        uint256 ethAmount,
        uint256 tokenAmount
    );
    event GraduationExcessBurned(uint256 tokenAmount, uint256 remainingSupply);
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
        if (migrationTarget_.code.length == 0 || positionRecipient_.code.length == 0) revert InvalidConfiguration();
        if (virtualEthReserve_ == 0 || graduationThreshold_ == 0) revert InvalidConfiguration();
        token = token_;
        reserveInitializer = reserveInitializer_;
        migrationTarget = migrationTarget_;
        positionRecipient = positionRecipient_;
        virtualEthReserve = virtualEthReserve_;
        graduationThreshold = graduationThreshold_;
    }

    receive() external payable {
        if (msg.sender != migrationTarget) revert DirectEthDisabled();
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
        return !graduated && thresholdReachedAt != 0;
    }

    function quoteBuy(uint256 ethIn) public view returns (uint256 tokensOut) {
        if (ethIn == 0 || ethIn > maxBuyAmount() || !reservesInitialized || graduated) return 0;
        uint256 effectiveEthIn = ethIn - Math.mulDiv(ethIn, TRADE_FEE_BPS, BPS, Math.Rounding.Ceil);
        if (effectiveEthIn == 0) return 0;
        uint256 invariant = (virtualEthReserve + ethReserve) * accountedTokenReserve;
        uint256 tokensAfter = Math.ceilDiv(invariant, virtualEthReserve + ethReserve + effectiveEthIn);
        if (tokensAfter >= accountedTokenReserve) return 0;
        tokensOut = accountedTokenReserve - tokensAfter;
    }

    function maxBuyAmount() public view returns (uint256) {
        return Math.mulDiv(virtualEthReserve, MAX_BUY_BPS_OF_VIRTUAL_RESERVE, BPS);
    }

    function graduationLiquidityQuote() public view returns (uint256 tokensForLiquidity, uint256 tokensToBurn) {
        // Exact zero is the intentional boundary for a usable graduation quote.
        // slither-disable-next-line incorrect-equality
        if (ethReserve == 0 || accountedTokenReserve == 0) return (0, accountedTokenReserve);
        tokensForLiquidity = Math.mulDiv(ethReserve, accountedTokenReserve, virtualEthReserve + ethReserve);
        tokensToBurn = accountedTokenReserve - tokensForLiquidity;
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
        // Exact zero is the intentional no-redeemable-liquidity boundary.
        // slither-disable-next-line incorrect-equality
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
        if (msg.value > maxBuyAmount()) revert BuyTooLarge();

        uint256 fee = Math.mulDiv(msg.value, TRADE_FEE_BPS, BPS, Math.Rounding.Ceil);
        uint256 effectiveEthIn = msg.value - fee;
        if (effectiveEthIn == 0) revert ZeroInput();
        uint256 invariant = (virtualEthReserve + ethReserve) * accountedTokenReserve;
        uint256 tokensAfter = Math.ceilDiv(invariant, virtualEthReserve + ethReserve + effectiveEthIn);
        if (tokensAfter >= accountedTokenReserve) revert InsufficientCurveLiquidity();
        tokensOut = accountedTokenReserve - tokensAfter;
        if (tokensOut < minimumTokensOut) revert SlippageExceeded();

        ethReserve += msg.value;
        accountedTokenReserve = tokensAfter;
        token.safeTransfer(msg.sender, tokensOut);
        emit TokensPurchased(msg.sender, msg.value, fee, tokensOut);
        if (thresholdReachedAt == 0 && ethReserve >= graduationThreshold) {
            thresholdReachedAt = uint64(block.timestamp);
            emit GraduationThresholdReached(ethReserve, accountedTokenReserve);
        }
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
        if (nextTarget == address(0)) revert NoMigrationProposal();
        if (block.timestamp < pendingMigrationTargetAt) revert MigrationDelayActive();
        if (block.timestamp > uint256(pendingMigrationTargetAt) + MIGRATION_PROPOSAL_WINDOW) {
            revert MigrationProposalExpired();
        }
        if (nextTarget.code.length == 0) revert InvalidConfiguration();
        address previous = migrationTarget;
        migrationTarget = nextTarget;
        delete pendingMigrationTarget;
        delete pendingMigrationTargetAt;
        emit MigrationTargetChanged(previous, nextTarget);
    }

    function cancelMigrationTarget() external onlyOwner {
        address cancelled = pendingMigrationTarget;
        if (cancelled == address(0)) revert NoMigrationProposal();
        delete pendingMigrationTarget;
        delete pendingMigrationTargetAt;
        emit MigrationTargetProposalCancelled(cancelled);
    }

    /// @notice Commits at most 0.1% of graduation liquidity to make hostile pool pricing economically movable.
    /// @dev The adapter returns all unused assets. This does not close trading or start treasury vesting.
    // The function is nonReentrant. Reads after the adapter call are deliberate exact-balance post-conditions, and
    // reserve writes use the verified returned usage. View-only callbacks can observe the pre-seed accounted state but
    // cannot authorize or mutate anything. The explicit checks account for the reported values and custody result.
    // Exact zero values below are intentional invalid adapter/result boundaries.
    // slither-disable-start reentrancy-balance,reentrancy-eth,reentrancy-benign,cyclomatic-complexity,incorrect-equality
    function seedMigrationPool() external onlyOwner nonReentrant {
        if (!graduationReady()) revert GraduationNotReady();
        address target = migrationTarget;
        if (poolSeeded && seededMigrationTarget == target) revert PoolAlreadySeeded();
        if (target.code.length == 0) revert MigrationFailed();

        (uint256 tokensForLiquidity,) = graduationLiquidityQuote();
        uint256 tokenCap = Math.mulDiv(tokensForLiquidity, POOL_SEED_BPS, BPS);
        uint256 ethCap = Math.mulDiv(ethReserve, POOL_SEED_BPS, BPS);
        if (tokenCap == 0 || ethCap == 0) revert MigrationFailed();
        uint256 tokenBalanceBefore = token.balanceOf(address(this));
        uint256 ethBalanceBefore = address(this).balance;

        poolSeeded = true;
        token.forceApprove(target, tokenCap);
        bytes32 outcomeId = bytes32(0);
        uint256 positionTokenId = 0;
        uint256 tokenUsed = 0;
        uint256 ethUsed = 0;
        try IVOIDMigrationTarget(target).seed{value: ethCap}(address(token), tokenCap, positionRecipient) returns (
            bytes32 result, uint256 tokenId, uint256 usedTokens, uint256 usedEth
        ) {
            outcomeId = result;
            positionTokenId = tokenId;
            tokenUsed = usedTokens;
            ethUsed = usedEth;
        } catch {
            revert MigrationFailed();
        }
        if (
            outcomeId == bytes32(0) || positionTokenId == 0 || (tokenUsed == 0 && ethUsed == 0) || tokenUsed > tokenCap
                || ethUsed > ethCap
        ) revert MigrationFailed();
        try IVOIDPositionCustody(positionRecipient).isRegisteredPosition(positionTokenId, target) returns (bool valid) {
            if (!valid) revert MigrationFailed();
        } catch {
            revert MigrationFailed();
        }
        if (token.balanceOf(address(this)) != tokenBalanceBefore - tokenUsed) revert MigrationFailed();
        if (address(this).balance != ethBalanceBefore - ethUsed) revert MigrationFailed();

        accountedTokenReserve -= tokenUsed;
        ethReserve -= ethUsed;
        seededTokenLiquidity = tokenUsed;
        seededEthLiquidity = ethUsed;
        seededMigrationTarget = target;
        emit MigrationPoolSeeded(target, positionRecipient, outcomeId, positionTokenId, ethUsed, tokenUsed);
    }

    // slither-disable-end reentrancy-balance,reentrancy-eth,reentrancy-benign,cyclomatic-complexity,incorrect-equality

    // slither-disable-start cyclomatic-complexity
    /// @notice Completes migration after the Safe has explicitly seeded the active target.
    /// @dev Permissionless execution lets a caller atomically correct the live pool price and graduate without stale
    /// Safe calldata. The Safe retains the gate because only it can seed or propose a different migration target.
    function graduate() external nonReentrant {
        if (!graduationReady()) revert GraduationNotReady();
        if (pendingMigrationTarget != address(0)) revert MigrationChangePending();
        address target = migrationTarget;
        if (!poolSeeded || seededMigrationTarget != target) revert PoolNotSeeded();
        if (target.code.length == 0) revert MigrationFailed();
        uint256 reserveTokens = accountedTokenReserve;
        uint256 eth = ethReserve;
        (uint256 tokens, uint256 tokensToBurn) = graduationLiquidityQuote();
        // Both legs must be nonzero; exact zero is the intentional graduation boundary.
        // slither-disable-next-line incorrect-equality
        if (tokens == 0 || tokensToBurn == 0) revert MigrationFailed();
        uint256 tokenBalanceBefore = token.balanceOf(address(this));
        uint256 supplyBefore = token.totalSupply();
        uint256 ethBalanceBefore = address(this).balance;

        // Effects are applied before the adapter call. Any failed call or post-condition reverts them atomically.
        accountedTokenReserve = 0;
        ethReserve = 0;
        graduated = true;
        graduatedAt = uint64(block.timestamp);
        token.safeTransfer(reserveInitializer, tokensToBurn);
        try IVOIDReserveBurner(reserveInitializer).burnCurveExcess(tokensToBurn) {}
        catch {
            revert MigrationFailed();
        }
        if (token.totalSupply() != supplyBefore - tokensToBurn) revert MigrationFailed();
        emit GraduationExcessBurned(tokensToBurn, token.totalSupply());
        token.forceApprove(target, tokens);
        bytes32 outcomeId = bytes32(0);
        uint256 positionTokenId = 0;
        try IVOIDMigrationTarget(target).migrate{value: eth}(address(token), tokens, positionRecipient) returns (
            bytes32 result, uint256 tokenId
        ) {
            outcomeId = result;
            positionTokenId = tokenId;
        } catch {
            revert MigrationFailed();
        }
        // Zero values are reserved adapter failure sentinels.
        // slither-disable-next-line incorrect-equality
        if (outcomeId == bytes32(0) || positionTokenId == 0) revert MigrationFailed();
        try IVOIDPositionCustody(positionRecipient).isRegisteredPosition(positionTokenId, target) returns (bool valid) {
            if (!valid) revert MigrationFailed();
        } catch {
            revert MigrationFailed();
        }
        // nonReentrant blocks state-changing callbacks; this balance delta is the adapter success post-condition.
        // slither-disable-next-line reentrancy-balance
        if (token.balanceOf(address(this)) != tokenBalanceBefore - reserveTokens) revert MigrationFailed();
        if (address(this).balance != ethBalanceBefore - eth) revert MigrationFailed();

        emit Graduated(target, positionRecipient, outcomeId, eth, tokens);
    }
    // slither-disable-end cyclomatic-complexity

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

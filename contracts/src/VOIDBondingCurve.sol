// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IVOIDMigrationTarget {
    function migrate(address token, uint256 tokenAmount) external payable;
}

/// @title VOIDBondingCurve
/// @notice Continuous, buyer-funded constant-product market that stays open until its ETH target is reached.
contract VOIDBondingCurve is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    address public immutable migrationTarget;
    uint256 public immutable virtualEthReserve;
    uint256 public immutable graduationThreshold;
    bool public graduationReady;
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

    event TokensPurchased(address indexed buyer, uint256 ethIn, uint256 tokensOut);
    event TokensSold(address indexed seller, uint256 tokensIn, uint256 ethOut);
    event GraduationReady(uint256 ethReserve, uint256 tokenReserve);
    event Graduated(address indexed migrationTarget, uint256 ethAmount, uint256 tokenAmount);

    constructor(
        IERC20 token_,
        address initialOwner,
        address migrationTarget_,
        uint256 virtualEthReserve_,
        uint256 graduationThreshold_
    ) Ownable(initialOwner) {
        if (address(token_) == address(0) || initialOwner == address(0) || migrationTarget_ == address(0)) {
            revert ZeroAddress();
        }
        if (virtualEthReserve_ == 0 || graduationThreshold_ == 0) revert InvalidConfiguration();
        token = token_;
        migrationTarget = migrationTarget_;
        virtualEthReserve = virtualEthReserve_;
        graduationThreshold = graduationThreshold_;
    }

    receive() external payable {
        revert DirectEthDisabled();
    }

    function tokenReserve() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function quoteBuy(uint256 ethIn) public view returns (uint256 tokensOut) {
        if (ethIn == 0) return 0;
        uint256 tokensBefore = tokenReserve();
        uint256 ethBefore = address(this).balance;
        uint256 invariant = (virtualEthReserve + ethBefore) * tokensBefore;
        uint256 tokensAfter = invariant / (virtualEthReserve + ethBefore + ethIn);
        tokensOut = tokensBefore - tokensAfter;
    }

    function quoteSell(uint256 tokensIn) public view returns (uint256 ethOut) {
        if (tokensIn == 0) return 0;
        uint256 tokensBefore = tokenReserve();
        uint256 ethBefore = address(this).balance;
        uint256 invariant = (virtualEthReserve + ethBefore) * tokensBefore;
        uint256 ethAfterWithVirtual = invariant / (tokensBefore + tokensIn);
        ethOut = virtualEthReserve + ethBefore - ethAfterWithVirtual;
        if (ethOut > ethBefore) return 0;
    }

    function buy(uint256 minimumTokensOut) external payable nonReentrant returns (uint256 tokensOut) {
        if (graduationReady || graduated) revert CurveClosed();
        if (msg.value == 0) revert ZeroInput();

        uint256 tokensBefore = tokenReserve();
        uint256 ethBefore = address(this).balance - msg.value;
        uint256 invariant = (virtualEthReserve + ethBefore) * tokensBefore;
        uint256 tokensAfter = invariant / (virtualEthReserve + ethBefore + msg.value);
        tokensOut = tokensBefore - tokensAfter;
        if (tokensOut == 0 || tokensOut > tokensBefore) revert InsufficientCurveLiquidity();
        if (tokensOut < minimumTokensOut) revert SlippageExceeded();

        token.safeTransfer(msg.sender, tokensOut);
        emit TokensPurchased(msg.sender, msg.value, tokensOut);
        _checkGraduation();
    }

    function sell(uint256 tokensIn, uint256 minimumEthOut) external nonReentrant returns (uint256 ethOut) {
        if (graduationReady || graduated) revert CurveClosed();
        if (tokensIn == 0) revert ZeroInput();

        uint256 tokensBefore = tokenReserve();
        uint256 ethBefore = address(this).balance;
        uint256 invariant = (virtualEthReserve + ethBefore) * tokensBefore;
        uint256 ethAfterWithVirtual = invariant / (tokensBefore + tokensIn);
        ethOut = virtualEthReserve + ethBefore - ethAfterWithVirtual;
        if (ethOut == 0 || ethOut > ethBefore) revert InsufficientCurveLiquidity();
        if (ethOut < minimumEthOut) revert SlippageExceeded();

        token.safeTransferFrom(msg.sender, address(this), tokensIn);
        (bool sent,) = payable(msg.sender).call{value: ethOut}("");
        if (!sent) revert MigrationFailed();
        emit TokensSold(msg.sender, tokensIn, ethOut);
    }

    function graduate() external onlyOwner nonReentrant {
        if (!graduationReady || graduated) revert GraduationNotReady();
        graduated = true;
        uint256 tokens = tokenReserve();
        uint256 eth = address(this).balance;
        token.forceApprove(migrationTarget, tokens);
        try IVOIDMigrationTarget(migrationTarget).migrate{value: eth}(address(token), tokens) {
            if (tokenReserve() != 0 || address(this).balance != 0) revert MigrationFailed();
        } catch {
            revert MigrationFailed();
        }
        emit Graduated(migrationTarget, eth, tokens);
    }

    function _checkGraduation() private {
        if (address(this).balance >= graduationThreshold) {
            graduationReady = true;
            emit GraduationReady(address(this).balance, tokenReserve());
        }
    }
}

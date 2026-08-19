// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {VOIDCoin} from "./VOIDCoin.sol";

/// @title VOIDCoinV2
/// @notice VOIDCOIN identity token with fixed-number and percentage takeover escalation.
contract VOIDCoinV2 is VOIDCoin {
    uint256 public constant TAKEOVER_INCREASE_BPS = 1_000; // 10%
    uint256 public constant BPS = 10_000;

    constructor(
        address initialOwner,
        address launchReceiver,
        address treasuryVestingWallet,
        string memory initialTokenURI
    ) VOIDCoin(initialOwner, launchReceiver, treasuryVestingWallet, initialTokenURI) {}

    /// @notice The next record must clear both a 250,000-token step and a 10% step.
    function nextBurnRequirement() public view override returns (uint256) {
        uint256 previous = recordBurn;
        if (previous == 0) return INITIAL_BURN;

        uint256 fixedIncrease = previous + TAKEOVER_INCREMENT;
        uint256 percentageIncrease = Math.mulDiv(previous, BPS + TAKEOVER_INCREASE_BPS, BPS, Math.Rounding.Ceil);
        return fixedIncrease > percentageIncrease ? fixedIncrease : percentageIncrease;
    }
}

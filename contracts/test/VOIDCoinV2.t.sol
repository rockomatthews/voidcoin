// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {VOIDCoin} from "../src/VOIDCoin.sol";
import {VOIDCoinV2} from "../src/VOIDCoinV2.sol";

contract VOIDCoinV2Test is Test {
    VOIDCoinV2 internal token;
    address internal safe = makeAddr("safe");
    address internal launch = makeAddr("launch");
    address internal vesting = makeAddr("vesting");
    address internal first = makeAddr("first");
    address internal second = makeAddr("second");

    function setUp() public {
        token = new VOIDCoinV2(safe, launch, vesting, "ipfs://genesis");
        vm.startPrank(launch);
        token.transfer(first, 50_000_000 ether);
        token.transfer(second, 50_000_000 ether);
        vm.stopPrank();
        vm.prank(safe);
        token.setRenamePaused(false);
    }

    function testFirstTakeoverRequiresOneMillion() public view {
        assertEq(token.nextBurnRequirement(), 1_000_000 ether);
        assertEq(token.maximumBurnAmount(), 3_000_000 ether);
    }

    function testFixedIncrementWinsAtLowRecords() public {
        vm.prank(first);
        token.burnForRename(1_000_000 ether, keccak256("first"));
        assertEq(token.nextBurnRequirement(), 1_250_000 ether);
    }

    function testPercentageIncrementWinsAtHigherRecords() public {
        vm.prank(first);
        token.burnForRename(3_000_000 ether, keccak256("first"));
        assertEq(token.nextBurnRequirement(), 3_300_000 ether);

        vm.prank(second);
        token.burnForRename(3_300_000 ether, keccak256("second"));
        assertEq(token.nextBurnRequirement(), 3_630_000 ether);
    }

    function testStrategicOverburnStillCannotExceedTwoMillionAboveLiveFloor() public {
        uint256 maximum = token.maximumBurnAmount();
        vm.prank(first);
        token.burnForRename(maximum, keccak256("maximum"));

        uint256 nextMaximum = token.maximumBurnAmount();
        vm.expectRevert(VOIDCoin.BurnAboveMaximum.selector);
        vm.prank(second);
        token.burnForRename(nextMaximum + 1, keccak256("too-high"));
    }

    function testRequirementIsMaximumOfFixedAndPercentageRules(uint96 rawRecord) public {
        uint256 record = bound(uint256(rawRecord), 1_000_000 ether, 40_000_000 ether);
        uint256 initialMaximum = token.maximumBurnAmount();
        if (record > initialMaximum) record = initialMaximum;
        vm.prank(first);
        token.burnForRename(record, keccak256("record"));

        uint256 fixedRule = record + token.TAKEOVER_INCREMENT();
        uint256 percentageRule = (record * 11_000 + 9_999) / 10_000;
        uint256 expected = fixedRule > percentageRule ? fixedRule : percentageRule;
        assertEq(token.nextBurnRequirement(), expected);
    }
}

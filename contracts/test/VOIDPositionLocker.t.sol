// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {VOIDPositionLocker} from "../src/VOIDPositionLocker.sol";

contract MockPositionNFT is ERC721 {
    uint256 public nextTokenId = 1;

    constructor() ERC721("Mock Position", "MPOS") {}

    function mint(address recipient) external returns (uint256 tokenId) {
        tokenId = nextTokenId++;
        _mint(recipient, tokenId);
    }

    function safeMint(address recipient) external returns (uint256 tokenId) {
        tokenId = nextTokenId++;
        _safeMint(recipient, tokenId);
    }
}

contract MockLockerAdapter {
    function register(VOIDPositionLocker locker, uint256 tokenId) external {
        locker.registerPosition(tokenId);
    }
}

contract VOIDPositionLockerTest is Test {
    MockPositionNFT internal manager;
    MockPositionNFT internal unrelatedNFT;
    MockLockerAdapter internal adapter;
    VOIDPositionLocker internal locker;
    address internal beneficiary = makeAddr("safe");

    function setUp() public {
        manager = new MockPositionNFT();
        unrelatedNFT = new MockPositionNFT();
        adapter = new MockLockerAdapter();
        locker = new VOIDPositionLocker(manager, address(adapter), beneficiary);
    }

    function testRegistersAtGraduationAndReleasesPermissionlesslyAfterTwelveMonths() public {
        uint256 tokenId = manager.mint(address(locker));
        uint256 registeredAt = block.timestamp;
        adapter.register(locker, tokenId);
        assertEq(locker.unlockAt(tokenId), registeredAt + locker.LOCK_DURATION());

        vm.expectRevert(VOIDPositionLocker.PositionLocked.selector);
        locker.release(tokenId);

        vm.warp(registeredAt + locker.LOCK_DURATION());
        vm.prank(makeAddr("keeper"));
        locker.release(tokenId);
        assertEq(manager.ownerOf(tokenId), beneficiary);
        assertEq(locker.unlockAt(tokenId), 0);
    }

    function testOnlyMigrationAdapterCanRegisterPosition() public {
        uint256 tokenId = manager.mint(address(locker));
        vm.expectRevert(VOIDPositionLocker.OnlyMigrationAdapter.selector);
        locker.registerPosition(tokenId);
    }

    function testCannotRegisterPositionTheLockerDoesNotOwn() public {
        uint256 tokenId = manager.mint(address(this));
        vm.expectRevert(VOIDPositionLocker.PositionNotHeld.selector);
        adapter.register(locker, tokenId);
    }

    function testRejectsUnrelatedSafeNftTransfers() public {
        uint256 tokenId = unrelatedNFT.mint(address(this));
        vm.expectRevert(VOIDPositionLocker.UnsupportedNFT.selector);
        unrelatedNFT.safeTransferFrom(address(this), address(locker), tokenId);
    }
}

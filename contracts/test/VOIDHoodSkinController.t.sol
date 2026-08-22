// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IHoodToken, IHoodTokenOwnerRegistry, VOIDHoodSkinController} from "../src/VOIDHoodSkinController.sol";

contract MockHoodOwnerRegistry is IHoodTokenOwnerRegistry {
    mapping(address token => address owner) internal _owners;

    function register(address token, address owner) external {
        require(_owners[token] == address(0));
        _owners[token] = owner;
    }

    function ownerOf(address token) external view returns (address) {
        return _owners[token];
    }

    function transferTokenOwnership(address token, address newOwner) external {
        require(msg.sender == _owners[token], "ONLY_TOKEN_OWNER");
        _owners[token] = newOwner;
    }
}

contract MockHoodToken is ERC20, IHoodToken {
    MockHoodOwnerRegistry internal immutable _registry;
    string public image = "ipfs://genesis-image";
    string public description = "genesis description";
    string public socials = '{"website":"https://voidcoin.fun"}';
    string public contractURI = "ipfs://genesis-metadata";

    modifier onlyTokenOwner() {
        require(_registry.ownerOf(address(this)) == msg.sender, "ONLY_TOKEN_OWNER");
        _;
    }

    constructor(address holder, MockHoodOwnerRegistry registry_) ERC20("VOIDCOIN", "VOID") {
        _registry = registry_;
        _mint(holder, 1_000_000_000 ether);
    }

    function name() public view override(ERC20, IHoodToken) returns (string memory) {
        return super.name();
    }

    function symbol() public view override(ERC20, IHoodToken) returns (string memory) {
        return super.symbol();
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function tokenOwner() external view returns (address) {
        return _registry.ownerOf(address(this));
    }

    function setImage(string calldata nextImage) external onlyTokenOwner {
        image = nextImage;
    }

    function setDescription(string calldata nextDescription) external onlyTokenOwner {
        description = nextDescription;
    }

    function setSocials(string calldata nextSocials) external onlyTokenOwner {
        socials = nextSocials;
    }

    function setContractURI(string calldata nextContractURI) external onlyTokenOwner {
        contractURI = nextContractURI;
    }
}

contract VOIDHoodSkinControllerTest is Test {
    address internal safe = makeAddr("safe");
    address internal first = makeAddr("first");
    address internal second = makeAddr("second");
    MockHoodOwnerRegistry internal registry;
    MockHoodToken internal token;
    VOIDHoodSkinController internal controller;

    string internal constant NEXT_NAME = "NEON VOID";
    string internal constant NEXT_SYMBOL = "NEON";
    string internal constant NEXT_IMAGE = "ipfs://next-image";
    string internal constant NEXT_DESCRIPTION = "The approved VOIDCOIN community skin.";
    string internal constant NEXT_SOCIALS = '{"website":"https://voidcoin.fun","x":"https://x.com/voidcoin"}';
    string internal constant NEXT_URI = "ipfs://next-metadata";

    function setUp() public {
        registry = new MockHoodOwnerRegistry();
        token = new MockHoodToken(first, registry);
        registry.register(address(token), safe);
        controller = new VOIDHoodSkinController(safe, IHoodToken(address(token)), registry);

        vm.prank(safe);
        registry.transferTokenOwnership(address(token), address(controller));
        vm.prank(first);
        token.transfer(second, 100_000_000 ether);
        vm.prank(safe);
        controller.setRenamePaused(false);
    }

    function testControllerStartsPausedBeforeHandoff() public {
        MockHoodToken otherToken = new MockHoodToken(first, registry);
        registry.register(address(otherToken), safe);
        VOIDHoodSkinController other = new VOIDHoodSkinController(safe, IHoodToken(address(otherToken)), registry);

        assertTrue(other.renamePaused());
        assertFalse(other.controllerReady());
        vm.prank(safe);
        vm.expectRevert(VOIDHoodSkinController.ControllerNotReady.selector);
        other.setRenamePaused(false);
    }

    function testLaunchDustBecomesBaselineNotContestBurn() public {
        MockHoodToken otherToken = new MockHoodToken(first, registry);
        registry.register(address(otherToken), safe);
        vm.prank(first);
        otherToken.burn(1_865);

        VOIDHoodSkinController other = new VOIDHoodSkinController(safe, IHoodToken(address(otherToken)), registry);

        assertEq(other.launchSupply(), 1_000_000_000 ether - 1_865);
        assertEq(other.destroyedSupply(), 0);
    }

    function testRejectsTokenOutsideLaunchDustBound() public {
        MockHoodToken otherToken = new MockHoodToken(first, registry);
        registry.register(address(otherToken), safe);
        vm.prank(first);
        otherToken.burn(1_000_001);

        vm.expectRevert(VOIDHoodSkinController.InvalidConfiguration.selector);
        new VOIDHoodSkinController(safe, IHoodToken(address(otherToken)), registry);
    }

    function testBurnActuallyReducesHoodTokenSupply() public {
        uint256 amount = controller.INITIAL_BURN();
        _burn(first, amount, keccak256("proposal"));

        assertEq(token.totalSupply(), controller.ORIGINAL_SUPPLY() - amount);
        assertEq(token.balanceOf(address(controller)), 0);
        assertEq(controller.contestBurned(), amount);
        assertEq(controller.destroyedSupply(), amount);
        assertEq(controller.recordBurner(), first);
    }

    function testApprovalUpdatesEveryMutableHoodMetadataSurfaceAtomically() public {
        (uint256 burnId, uint256 amount, bytes32 salt, bytes32 commitment) = _proposal(first);
        _burn(first, amount, commitment);

        vm.prank(safe);
        controller.approveRename(burnId, _skin(), salt);

        assertEq(controller.displayName(), NEXT_NAME);
        assertEq(controller.displaySymbol(), NEXT_SYMBOL);
        assertEq(token.image(), NEXT_IMAGE);
        assertEq(token.description(), NEXT_DESCRIPTION);
        assertEq(token.socials(), NEXT_SOCIALS);
        assertEq(token.contractURI(), NEXT_URI);
        assertEq(controller.activeSlot().burner, address(0));
    }

    function testUnderlyingHoodNameAndTickerRemainImmutable() public {
        (uint256 burnId, uint256 amount, bytes32 salt, bytes32 commitment) = _proposal(first);
        _burn(first, amount, commitment);
        vm.prank(safe);
        controller.approveRename(burnId, _skin(), salt);

        assertEq(token.name(), "VOIDCOIN");
        assertEq(token.symbol(), "VOID");
        assertEq(controller.displayName(), "NEON VOID");
        assertEq(controller.displaySymbol(), "NEON");
    }

    function testCommitmentBindsEveryPublishedField() public {
        (uint256 burnId, uint256 amount, bytes32 salt, bytes32 commitment) = _proposal(first);
        _burn(first, amount, commitment);

        vm.prank(safe);
        vm.expectRevert(VOIDHoodSkinController.CommitmentMismatch.selector);
        VOIDHoodSkinController.SkinProposal memory changed = _skin();
        changed.image = "ipfs://different-image";
        controller.approveRename(burnId, changed, salt);

        assertEq(token.image(), "ipfs://genesis-image");
        assertEq(controller.activeSlot().burner, first);
    }

    function testHigherBurnCanTakeTheActiveSlot() public {
        _burn(first, 1_000_000 ether, keccak256("first"));
        _burn(second, 1_250_000 ether, keccak256("second"));

        assertEq(controller.activeSlot().burner, second);
        assertEq(controller.recordBurn(), 1_250_000 ether);
        assertEq(controller.nextBurnRequirement(), 1_500_000 ether);
    }

    function testStaleBurnIdRevertsBeforeTokensMove() public {
        uint256 staleId = controller.nextBurnId();
        uint256 secondBalance = token.balanceOf(second);
        _burn(first, 1_000_000 ether, keccak256("first"));

        vm.startPrank(second);
        token.approve(address(controller), 3_000_000 ether);
        vm.expectRevert(VOIDHoodSkinController.UnexpectedBurnId.selector);
        controller.burnForRename(staleId, 3_000_000 ether, keccak256("stale"));
        vm.stopPrank();

        assertEq(token.balanceOf(second), secondBalance);
        assertEq(token.allowance(second, address(controller)), 3_000_000 ether);
        assertEq(controller.currentBurnId(), 1);
    }

    function testSafeCanRecoverTokenControlOnlyWhilePausedAndWithoutActiveSlot() public {
        vm.prank(safe);
        vm.expectRevert(VOIDHoodSkinController.InvalidConfiguration.selector);
        controller.transferTokenControl(safe);

        vm.prank(safe);
        controller.setRenamePaused(true);
        vm.prank(safe);
        controller.transferTokenControl(safe);

        assertEq(registry.ownerOf(address(token)), safe);
        assertFalse(controller.controllerReady());
    }

    function testCannotRecoverTokenControlWithActiveSlot() public {
        _burn(first, 1_000_000 ether, keccak256("proposal"));
        vm.prank(safe);
        controller.setRenamePaused(true);

        vm.prank(safe);
        vm.expectRevert(VOIDHoodSkinController.ActiveSlotExists.selector);
        controller.transferTokenControl(safe);
    }

    function _proposal(address burner)
        internal
        view
        returns (uint256 burnId, uint256 amount, bytes32 salt, bytes32 commitment)
    {
        burnId = controller.currentBurnId() + 1;
        amount = controller.nextBurnRequirement();
        salt = keccak256("salt");
        bytes32 proposedSkinHash = controller.skinHash(_skin());
        commitment = controller.proposalCommitment(burnId, burner, amount, proposedSkinHash, salt);
    }

    function _skin() internal pure returns (VOIDHoodSkinController.SkinProposal memory proposal) {
        proposal = VOIDHoodSkinController.SkinProposal({
            displayName: NEXT_NAME,
            displaySymbol: NEXT_SYMBOL,
            image: NEXT_IMAGE,
            description: NEXT_DESCRIPTION,
            socials: NEXT_SOCIALS,
            metadataURI: NEXT_URI
        });
    }

    function _burn(address burner, uint256 amount, bytes32 commitment) internal {
        vm.startPrank(burner);
        token.approve(address(controller), amount);
        controller.burnForRename(controller.currentBurnId() + 1, amount, commitment);
        vm.stopPrank();
    }
}

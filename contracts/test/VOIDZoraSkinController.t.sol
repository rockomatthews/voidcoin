// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {VOIDZoraSkinController, IZoraContentCoin} from "../src/VOIDZoraSkinController.sol";

contract MockZoraContentCoin is ERC20 {
    mapping(address => bool) public isOwner;
    string public contractURI;
    string private _coinName = "VOIDCOIN";
    string private _coinSymbol = "VOID";

    modifier onlyOwner() {
        require(isOwner[msg.sender], "ONLY_OWNER");
        _;
    }

    constructor(address holder) ERC20("VOIDCOIN", "VOID") {
        isOwner[msg.sender] = true;
        _mint(holder, 1_000_000_000 ether);
    }

    function name() public view override returns (string memory) {
        return _coinName;
    }

    function symbol() public view override returns (string memory) {
        return _coinSymbol;
    }

    function addOwner(address account) external onlyOwner {
        isOwner[account] = true;
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function setNameAndSymbol(string calldata newName, string calldata newSymbol) external onlyOwner {
        _coinName = newName;
        _coinSymbol = newSymbol;
    }

    function setContractURI(string calldata newURI) external onlyOwner {
        contractURI = newURI;
    }
}

contract VOIDZoraSkinControllerTest is Test {
    address internal safe = makeAddr("safe");
    address internal first = makeAddr("first");
    address internal second = makeAddr("second");
    MockZoraContentCoin internal token;
    VOIDZoraSkinController internal controller;

    function setUp() public {
        token = new MockZoraContentCoin(first);
        controller = new VOIDZoraSkinController(safe, IZoraContentCoin(address(token)));
        token.addOwner(address(controller));
        vm.prank(first);
        token.transfer(second, 100_000_000 ether);
        vm.prank(safe);
        controller.setRenamePaused(false);
    }

    function testBurnIsAtomicAndActuallyReducesZoraSupply() public {
        uint256 amount = controller.INITIAL_BURN();
        vm.startPrank(first);
        token.approve(address(controller), amount);
        controller.burnForRename(amount, keccak256("proposal"));
        vm.stopPrank();

        assertEq(token.totalSupply(), controller.ORIGINAL_SUPPLY() - amount);
        assertEq(token.balanceOf(address(controller)), 0);
        assertEq(controller.contestBurned(), amount);
        assertEq(controller.destroyedSupply(), amount);
        assertEq(controller.recordBurner(), first);
    }

    function testApprovalChangesActualZoraNameSymbolAndContractURI() public {
        uint256 burnId = 1;
        uint256 amount = controller.INITIAL_BURN();
        string memory newName = "NEON VOID";
        string memory newSymbol = "NEON";
        string memory uri = "ipfs://approved";
        bytes32 imageHash = keccak256("image");
        bytes32 salt = keccak256("salt");
        bytes32 commitment = controller.proposalCommitment(
            burnId, first, amount, newName, newSymbol, imageHash, keccak256(bytes(uri)), salt
        );

        vm.startPrank(first);
        token.approve(address(controller), amount);
        controller.burnForRename(amount, commitment);
        vm.stopPrank();
        vm.prank(safe);
        controller.approveRename(burnId, newName, newSymbol, uri, imageHash, salt);

        assertEq(token.name(), newName);
        assertEq(token.symbol(), newSymbol);
        assertEq(token.contractURI(), uri);
        assertEq(controller.activeSlot().burner, address(0));
    }

    function testHigherBurnCanTakeActiveControl() public {
        _burn(first, 1_000_000 ether, keccak256("first"));
        _burn(second, 1_250_000 ether, keccak256("second"));

        assertEq(controller.activeSlot().burner, second);
        assertEq(controller.recordBurn(), 1_250_000 ether);
        assertEq(controller.nextBurnRequirement(), 1_500_000 ether);
    }

    function testTenPercentRuleEventuallyWins() public {
        _burn(first, 3_000_000 ether, keccak256("first"));
        assertEq(controller.nextBurnRequirement(), 3_300_000 ether);
    }

    function testCannotOpenContestUntilControllerIsZoraOwner() public {
        MockZoraContentCoin other = new MockZoraContentCoin(first);
        VOIDZoraSkinController unready = new VOIDZoraSkinController(safe, IZoraContentCoin(address(other)));
        vm.prank(safe);
        vm.expectRevert(VOIDZoraSkinController.ControllerNotTokenOwner.selector);
        unready.setRenamePaused(false);
    }

    function testInsufficientAllowanceLeavesTokensAndRecordUntouched() public {
        uint256 supplyBefore = token.totalSupply();
        vm.prank(first);
        vm.expectRevert();
        controller.burnForRename(1_000_000 ether, keccak256("proposal"));
        assertEq(token.totalSupply(), supplyBefore);
        assertEq(controller.recordBurn(), 0);
    }

    function testDirectZoraBurnCountsAsDestroyedButNotContestBurn() public {
        vm.prank(first);
        token.burn(10 ether);
        assertEq(controller.destroyedSupply(), 10 ether);
        assertEq(controller.contestBurned(), 0);
    }

    function testOnlySafeCanApproveMetadata() public {
        uint256 amount = controller.INITIAL_BURN();
        bytes32 imageHash = keccak256("image");
        bytes32 salt = keccak256("salt");
        string memory uri = "ipfs://approved";
        bytes32 commitment = controller.proposalCommitment(
            1, first, amount, "NEON VOID", "NEON", imageHash, keccak256(bytes(uri)), salt
        );
        _burn(first, amount, commitment);

        vm.prank(first);
        vm.expectRevert();
        controller.approveRename(1, "NEON VOID", "NEON", uri, imageHash, salt);
    }

    function _burn(address burner, uint256 amount, bytes32 commitment) internal {
        vm.startPrank(burner);
        token.approve(address(controller), amount);
        controller.burnForRename(amount, commitment);
        vm.stopPrank();
    }
}

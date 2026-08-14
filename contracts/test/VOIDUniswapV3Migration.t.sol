// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VOIDBondingCurve} from "../src/VOIDBondingCurve.sol";
import {VOIDCoin} from "../src/VOIDCoin.sol";
import {VOIDLaunch} from "../src/VOIDLaunch.sol";
import {VOIDUniswapV3Migration, IVOIDUniswapV3PositionManager, IVOIDWETH9} from "../src/VOIDUniswapV3Migration.sol";

contract MockLaunchToken is ERC20 {
    constructor() ERC20("Launch", "LAUNCH") {
        _mint(msg.sender, 1_000_000_000 ether);
    }
}

contract MockDeflationaryToken is ERC20 {
    constructor() ERC20("Deflationary", "FEE") {
        _mint(msg.sender, 1_000_000_000 ether);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0) && value > 1) {
            super._update(from, to, value - 1);
            super._update(from, address(0), 1);
        } else {
            super._update(from, to, value);
        }
    }
}

contract MockWETH9 is ERC20, IVOIDWETH9 {
    constructor() ERC20("Wrapped Ether", "WETH") {}

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }
}

contract MockV3Pool {}

contract MockPositionManager is IVOIDUniswapV3PositionManager {
    using SafeERC20 for IERC20;

    address public immutable override WETH9;
    address public immutable override factory;
    address public immutable pool;
    uint256 public useBps = 9_995;
    uint256 public nextTokenId = 1;
    uint160 public initializedPrice;
    uint24 public lastFee;
    int24 public lastTickLower;
    int24 public lastTickUpper;
    address public lastRecipient;

    constructor(address weth) {
        WETH9 = weth;
        factory = address(this);
        pool = address(new MockV3Pool());
    }

    function setUseBps(uint256 value) external {
        useBps = value;
    }

    function createAndInitializePoolIfNecessary(address, address, uint24, uint160 sqrtPriceX96)
        external
        payable
        returns (address)
    {
        initializedPrice = sqrtPriceX96;
        return pool;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        amount0 = params.amount0Desired * useBps / 10_000;
        amount1 = params.amount1Desired * useBps / 10_000;
        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, "minimums");
        IERC20(params.token0).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(params.token1).safeTransferFrom(msg.sender, address(this), amount1);
        lastFee = params.fee;
        lastTickLower = params.tickLower;
        lastTickUpper = params.tickUpper;
        lastRecipient = params.recipient;
        tokenId = nextTokenId++;
        liquidity = uint128(amount0 < amount1 ? amount0 : amount1);
    }
}

    contract MockMigrationSafe {
        receive() external payable {}
    }

    contract MockPositionRegistration {
        uint256 public tokenId;

        function registerPosition(uint256 tokenId_) external {
            tokenId = tokenId_;
        }
    }

    contract VOIDUniswapV3MigrationTest is Test {
        MockWETH9 internal weth;
        MockPositionManager internal manager;
        VOIDUniswapV3Migration internal adapter;
        MockLaunchToken internal token;
        address internal user = makeAddr("user");
        address internal dustRecipient = makeAddr("safe");
        MockPositionRegistration internal positionLocker;
        address internal positionRecipient;

        function setUp() public {
            weth = new MockWETH9();
            manager = new MockPositionManager(address(weth));
            adapter = new VOIDUniswapV3Migration(manager, dustRecipient);
            positionLocker = new MockPositionRegistration();
            positionRecipient = address(positionLocker);
            token = new MockLaunchToken();
            token.transfer(user, 100_000_000 ether);
            vm.deal(user, 10 ether);
            vm.deal(address(this), 10 ether);
        }

        function testCreatesFullRangePositionAndRoutesOnlyBoundedDust() public {
            uint256 tokenAmount = 100_000_000 ether;
            uint256 ethAmount = 2 ether;
            vm.startPrank(user);
            token.approve(address(adapter), tokenAmount);
            bytes32 outcome = adapter.migrate{value: ethAmount}(address(token), tokenAmount, positionRecipient);
            vm.stopPrank();

            assertNotEq(outcome, bytes32(0));
            assertEq(manager.lastFee(), adapter.POOL_FEE());
            assertEq(manager.lastTickLower(), adapter.TICK_LOWER());
            assertEq(manager.lastTickUpper(), adapter.TICK_UPPER());
            assertEq(manager.lastRecipient(), positionRecipient);
            assertEq(positionLocker.tokenId(), 1);
            assertGt(manager.initializedPrice(), adapter.MIN_SQRT_RATIO());
            assertLt(manager.initializedPrice(), adapter.MAX_SQRT_RATIO());
            assertEq(token.balanceOf(address(adapter)), 0);
            assertEq(weth.balanceOf(address(adapter)), 0);
            assertEq(address(adapter).balance, 0);
            assertEq(token.balanceOf(dustRecipient), tokenAmount * 5 / 10_000);
            assertEq(dustRecipient.balance, ethAmount * 5 / 10_000);
        }

        function testRevertsWhenExistingPoolCannotUseAtLeast999PercentOfBothAssets() public {
            manager.setUseBps(9_989);
            uint256 tokenAmount = 1_000_000 ether;
            vm.startPrank(user);
            token.approve(address(adapter), tokenAmount);
            vm.expectRevert(bytes("minimums"));
            adapter.migrate{value: 1 ether}(address(token), tokenAmount, positionRecipient);
            vm.stopPrank();
        }

        function testRejectsDeflationaryTokens() public {
            MockDeflationaryToken feeToken = new MockDeflationaryToken();
            uint256 amount = 1_000_000 ether;
            feeToken.approve(address(adapter), amount);
            vm.expectRevert(VOIDUniswapV3Migration.DeflationaryTokenUnsupported.selector);
            adapter.migrate{value: 1 ether}(address(feeToken), amount, positionRecipient);
        }

        function testRejectsDirectEth() public {
            vm.expectRevert(VOIDUniswapV3Migration.DirectEthDisabled.selector);
            payable(address(adapter)).transfer(1 wei);
        }

        function testCurveGraduatesIntoPositionOwnedByApprovedRecipient() public {
            MockMigrationSafe safe = new MockMigrationSafe();
            VOIDUniswapV3Migration launchAdapter = new VOIDUniswapV3Migration(manager, address(safe));
            VOIDLaunch launch = new VOIDLaunch(
                address(safe), address(launchAdapter), positionRecipient, 1 ether, 2 ether, "ipfs://genesis"
            );
            VOIDCoin voidToken = launch.token();
            VOIDBondingCurve curve = launch.bondingCurve();
            address buyer = makeAddr("buyer");
            vm.deal(buyer, 3 ether);
            uint256 quote = curve.quoteBuy(2 ether);
            vm.prank(buyer);
            curve.buy{value: 2 ether}(quote, block.timestamp);

            vm.prank(address(safe));
            curve.graduate();

            assertTrue(curve.graduated());
            assertEq(manager.lastRecipient(), positionRecipient);
            assertEq(voidToken.balanceOf(address(curve)), 0);
            assertEq(curve.ethReserve(), 0);
        }
    }

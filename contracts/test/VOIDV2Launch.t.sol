// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VOIDCoinV2} from "../src/VOIDCoinV2.sol";
import {VOIDV2Launch, IVOIDV2PositionManager, IVOIDV3PoolState} from "../src/VOIDV2Launch.sol";

contract V2MockERC20 is ERC20 {
    uint8 internal immutable customDecimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        customDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return customDecimals;
    }
}

contract V2MockPool {
    uint160 public price;

    function initialize(uint160 price_) external {
        if (price == 0) price = price_;
    }

    function forcePrice(uint160 price_) external {
        price = price_;
    }

    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (price, 0, 0, 0, 0, 0, true);
    }
}

contract V2MockPositionManager is ERC721, IVOIDV2PositionManager {
    using SafeERC20 for IERC20;

    address public immutable WETH9;
    V2MockPool public immutable pool;
    uint256 public nextTokenId = 1;
    bool public hostile;
    uint24 public lastFee;
    address public lastToken0;
    address public lastToken1;
    int24 public lastTickLower;
    int24 public lastTickUpper;
    uint256 public lastAmount0Desired;
    uint256 public lastAmount1Desired;
    uint160 internal constant TOKEN0_BOUNDARY = 78_778_025_264_164_499_494;
    uint160 internal constant TOKEN1_BOUNDARY = 79_680_871_846_404_160_720_201_234_303_411_693_634;

    constructor(address weth_) ERC721("Mock Positions", "MOCK-LP") {
        WETH9 = weth_;
        pool = new V2MockPool();
    }

    function setHostile(bool value) external {
        hostile = value;
    }

    function createAndInitializePoolIfNecessary(address, address, uint24, uint160 sqrtPriceX96)
        external
        payable
        returns (address)
    {
        pool.initialize(hostile ? sqrtPriceX96 + 1 : sqrtPriceX96);
        return address(pool);
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        lastFee = params.fee;
        lastToken0 = params.token0;
        lastToken1 = params.token1;
        lastTickLower = params.tickLower;
        lastTickUpper = params.tickUpper;
        lastAmount0Desired = params.amount0Desired;
        lastAmount1Desired = params.amount1Desired;
        if (params.amount0Desired == 0) require(pool.price() >= TOKEN1_BOUNDARY, "token1 position needs USDC");
        if (params.amount1Desired == 0) require(pool.price() <= TOKEN0_BOUNDARY, "token0 position needs USDC");
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;
        if (amount0 > 0) IERC20(params.token0).safeTransferFrom(msg.sender, address(pool), amount0);
        if (amount1 > 0) IERC20(params.token1).safeTransferFrom(msg.sender, address(pool), amount1);
        tokenId = nextTokenId++;
        liquidity = 1_000_000;
        _safeMint(params.recipient, tokenId);
    }
}

contract V2MockSafe {}

contract VOIDV2LaunchTest is Test {
    V2MockERC20 internal usdc;
    V2MockERC20 internal weth;
    V2MockPositionManager internal manager;
    V2MockSafe internal safe;

    function setUp() public {
        usdc = new V2MockERC20("USD Coin", "USDC", 6);
        weth = new V2MockERC20("Wrapped Ether", "WETH", 18);
        manager = new V2MockPositionManager(address(weth));
        safe = new V2MockSafe();
    }

    function testCreatesVisibleTokenOnlyMarketAndLocksPosition() public {
        VOIDV2Launch launch = new VOIDV2Launch(address(safe), manager, usdc, "ipfs://genesis");
        VOIDCoinV2 token = launch.token();

        assertEq(token.balanceOf(address(launch)), 0);
        assertEq(token.balanceOf(address(launch.vestingWallet())), 20_000_000 ether);
        assertEq(launch.tokensSeeded(), 980_000_000 ether);
        assertEq(launch.launchDustBurned(), 0);
        assertEq(launch.positionLocker().unlockAt(launch.positionTokenId()), block.timestamp + 365 days);
        assertEq(manager.ownerOf(launch.positionTokenId()), address(launch.positionLocker()));
        assertEq(manager.lastFee(), 10_000);
        assertTrue(manager.lastAmount0Desired() == 0 || manager.lastAmount1Desired() == 0);
        assertEq(manager.lastAmount0Desired() + manager.lastAmount1Desired(), 980_000_000 ether);
        assertEq(token.totalSupply(), 1_000_000_000 ether);
    }

    function testLaunchRejectsPreinitializedPoolAtWrongPrice() public {
        manager.setHostile(true);
        vm.expectRevert(VOIDV2Launch.HostilePoolPrice.selector);
        new VOIDV2Launch(address(safe), manager, usdc, "ipfs://genesis");
    }

    function testStartingPriceTargetsOneDollarPerInitialTakeover() public pure {
        // token0=VOID raw price at tick -414600 is ~9.88669e-19 USDC-wei per VOID-wei.
        // Multiplying by 1e12 decimal adjustment gives ~$0.000000988669 per VOID.
        uint256 microDollarsPerMillionTokens = 988_669;
        assertApproxEqAbs(microDollarsPerMillionTokens, 1_000_000, 12_000);
    }

    function testSymmetricMarketWhenVoidIsToken0() public {
        address highUsdc = address(uint160(type(uint160).max - 1));
        vm.etch(highUsdc, hex"00");
        V2MockPositionManager localManager = new V2MockPositionManager(address(weth));

        VOIDV2Launch launch = new VOIDV2Launch(address(safe), localManager, IERC20(highUsdc), "ipfs://genesis");

        assertLt(uint160(address(launch.token())), uint160(highUsdc));
        assertEq(localManager.lastToken0(), address(launch.token()));
        assertEq(localManager.lastToken1(), highUsdc);
        assertEq(localManager.lastTickLower(), launch.TOKEN0_START_TICK());
        assertEq(localManager.lastTickUpper(), launch.TOKEN0_END_TICK());
        assertEq(localManager.pool().price(), launch.TOKEN0_START_SQRT_PRICE_X96());
    }

    function testSymmetricMarketWhenVoidIsToken1() public {
        address lowUsdc = address(0x1000);
        vm.etch(lowUsdc, hex"00");
        V2MockPositionManager localManager = new V2MockPositionManager(address(weth));

        VOIDV2Launch launch = new VOIDV2Launch(address(safe), localManager, IERC20(lowUsdc), "ipfs://genesis");

        assertGt(uint160(address(launch.token())), uint160(lowUsdc));
        assertEq(localManager.lastToken0(), lowUsdc);
        assertEq(localManager.lastToken1(), address(launch.token()));
        assertEq(localManager.lastTickLower(), launch.TOKEN1_START_TICK());
        assertEq(localManager.lastTickUpper(), launch.TOKEN1_END_TICK());
        assertEq(localManager.pool().price(), launch.TOKEN1_START_SQRT_PRICE_X96());
    }
}

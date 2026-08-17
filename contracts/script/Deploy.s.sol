// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {VOIDCoin} from "../src/VOIDCoin.sol";
import {VOIDLaunch} from "../src/VOIDLaunch.sol";
import {VOIDBondingCurve} from "../src/VOIDBondingCurve.sol";
import {VOIDTreasuryVesting} from "../src/VOIDTreasuryVesting.sol";
import {VOIDUniswapV3Migration, IVOIDUniswapV3PositionManager} from "../src/VOIDUniswapV3Migration.sol";
import {VOIDPositionLocker} from "../src/VOIDPositionLocker.sol";
import {VOIDGraduationExecutor, IVOIDGraduationCurve, IVOIDGraduationRouter} from "../src/VOIDGraduationExecutor.sol";

contract DeployVOIDCoin is Script {
    address internal constant BASE_UNISWAP_V3_POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    address internal constant BASE_UNISWAP_V3_SWAP_ROUTER_02 = 0x2626664c2603336E57B271c5C0b26F421741e481;
    uint256 internal constant VIRTUAL_ETH_RESERVE = 100 ether;
    uint256 internal constant GRADUATION_THRESHOLD = 25 ether;

    function run() external returns (VOIDCoin token, VOIDTreasuryVesting vestingWallet) {
        address safe = vm.envAddress("SAFE_ADDRESS");
        string memory initialTokenURI = vm.envOr("INITIAL_TOKEN_URI", string(""));

        require(safe.code.length > 0, "SAFE_ADDRESS must be a deployed Base Mainnet contract");
        require(block.chainid == 8453, "Base Mainnet only");
        require(
            BASE_UNISWAP_V3_POSITION_MANAGER.code.length > 0, "Official Base Uniswap v3 position manager is unavailable"
        );
        require(BASE_UNISWAP_V3_SWAP_ROUTER_02.code.length > 0, "Official Base Uniswap v3 router is unavailable");
        (bool acceptsPositions, bytes memory receiverResult) =
            safe.staticcall(abi.encodeCall(IERC721Receiver.onERC721Received, (address(this), address(this), 0, "")));
        require(
            acceptsPositions && receiverResult.length >= 32
                && abi.decode(receiverResult, (bytes4)) == IERC721Receiver.onERC721Received.selector,
            "SAFE_ADDRESS must accept Uniswap v3 position NFTs"
        );
        require(bytes(initialTokenURI).length > 0, "INITIAL_TOKEN_URI must be permanent metadata");

        vm.startBroadcast();
        VOIDUniswapV3Migration migrationTarget =
            new VOIDUniswapV3Migration(IVOIDUniswapV3PositionManager(BASE_UNISWAP_V3_POSITION_MANAGER), safe);
        VOIDPositionLocker positionLocker = new VOIDPositionLocker(IERC721(BASE_UNISWAP_V3_POSITION_MANAGER), safe);
        VOIDLaunch launch = new VOIDLaunch(
            safe,
            address(migrationTarget),
            address(positionLocker),
            VIRTUAL_ETH_RESERVE,
            GRADUATION_THRESHOLD,
            initialTokenURI
        );
        VOIDGraduationExecutor graduationExecutor = new VOIDGraduationExecutor(
            IVOIDGraduationCurve(address(launch.bondingCurve())), IVOIDGraduationRouter(BASE_UNISWAP_V3_SWAP_ROUTER_02)
        );
        vm.stopBroadcast();

        token = launch.token();
        vestingWallet = launch.vestingWallet();

        console2.log("VOIDCoin:", address(token));
        console2.log("Treasury vesting wallet:", address(vestingWallet));
        VOIDBondingCurve curve = launch.bondingCurve();
        console2.log("Continuous bonding curve:", address(curve));
        console2.log("Uniswap v3 migration target:", address(migrationTarget));
        console2.log("Uniswap v3 position manager:", BASE_UNISWAP_V3_POSITION_MANAGER);
        console2.log("Uniswap v3 SwapRouter02:", BASE_UNISWAP_V3_SWAP_ROUTER_02);
        console2.log("Atomic graduation executor:", address(graduationExecutor));
        console2.log("Uniswap v3 pool fee:", migrationTarget.POOL_FEE());
        console2.log("12-month position locker:", address(positionLocker));
        console2.log("Position unlock duration:", positionLocker.LOCK_DURATION());
        console2.log("Virtual ETH reserve:", VIRTUAL_ETH_RESERVE);
        console2.log("Graduation threshold:", GRADUATION_THRESHOLD);
        console2.log("Token owner Safe:", token.owner());
        console2.log("Competitive renaming paused:", token.renamePaused());
    }
}

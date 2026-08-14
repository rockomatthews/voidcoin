// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {VOIDCoin} from "../src/VOIDCoin.sol";
import {VOIDLaunch} from "../src/VOIDLaunch.sol";
import {VOIDBondingCurve} from "../src/VOIDBondingCurve.sol";
import {VOIDTreasuryVesting} from "../src/VOIDTreasuryVesting.sol";
import {VOIDUniswapV3Migration, IVOIDUniswapV3PositionManager} from "../src/VOIDUniswapV3Migration.sol";
import {VOIDPositionLocker} from "../src/VOIDPositionLocker.sol";

contract DeployVOIDCoin is Script {
    address internal constant BASE_UNISWAP_V3_POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;

    function run() external returns (VOIDCoin token, VOIDTreasuryVesting vestingWallet) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address safe = vm.envAddress("SAFE_ADDRESS");
        uint256 virtualEthReserve = vm.envUint("VIRTUAL_ETH_RESERVE");
        uint256 graduationThreshold = vm.envUint("GRADUATION_THRESHOLD");
        string memory initialTokenURI = vm.envOr("INITIAL_TOKEN_URI", string(""));

        require(safe.code.length > 0, "SAFE_ADDRESS must be a deployed Base Mainnet contract");
        require(block.chainid == 8453, "Base Mainnet only");
        require(
            BASE_UNISWAP_V3_POSITION_MANAGER.code.length > 0, "Official Base Uniswap v3 position manager is unavailable"
        );
        require(virtualEthReserve > 0, "VIRTUAL_ETH_RESERVE must be nonzero");
        require(graduationThreshold > 0, "GRADUATION_THRESHOLD must be nonzero");
        require(bytes(initialTokenURI).length > 0, "INITIAL_TOKEN_URI must be permanent metadata");

        vm.startBroadcast(deployerKey);
        VOIDUniswapV3Migration migrationTarget =
            new VOIDUniswapV3Migration(IVOIDUniswapV3PositionManager(BASE_UNISWAP_V3_POSITION_MANAGER), safe);
        VOIDPositionLocker positionLocker =
            new VOIDPositionLocker(IERC721(BASE_UNISWAP_V3_POSITION_MANAGER), address(migrationTarget), safe);
        VOIDLaunch launch = new VOIDLaunch(
            safe,
            address(migrationTarget),
            address(positionLocker),
            virtualEthReserve,
            graduationThreshold,
            initialTokenURI
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
        console2.log("Uniswap v3 pool fee:", migrationTarget.POOL_FEE());
        console2.log("12-month position locker:", address(positionLocker));
        console2.log("Position unlock duration:", positionLocker.LOCK_DURATION());
        console2.log("Virtual ETH reserve:", virtualEthReserve);
        console2.log("Graduation threshold:", graduationThreshold);
        console2.log("Token owner Safe:", token.owner());
        console2.log("Competitive renaming paused:", token.renamePaused());
    }
}

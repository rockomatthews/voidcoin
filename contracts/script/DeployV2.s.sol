// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {VOIDV2Launch, IVOIDV2PositionManager} from "../src/VOIDV2Launch.sol";
import {VOIDV2BuyRouter, IVOIDV2WETH, IVOIDV2SwapRouter} from "../src/VOIDV2BuyRouter.sol";

interface IV2UniswapFactory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

contract DeployVOIDCoinV2 is Script {
    address internal constant POSITION_MANAGER = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    address internal constant SWAP_ROUTER_02 = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address internal constant UNISWAP_V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    uint24 internal constant WETH_USDC_FEE = 500;

    function run() external returns (VOIDV2Launch launch, VOIDV2BuyRouter buyRouter) {
        address safe = vm.envAddress("SAFE_ADDRESS");
        string memory initialTokenURI = vm.envString("INITIAL_TOKEN_URI");

        require(block.chainid == 8453, "Base Mainnet only");
        require(safe.code.length > 0, "SAFE_ADDRESS must be a deployed contract");
        require(bytes(initialTokenURI).length > 0, "INITIAL_TOKEN_URI required");
        (bool acceptsPositions, bytes memory receiverResult) =
            safe.staticcall(abi.encodeCall(IERC721Receiver.onERC721Received, (safe, safe, 0, "")));
        require(
            acceptsPositions && receiverResult.length >= 32
                && abi.decode(receiverResult, (bytes4)) == IERC721Receiver.onERC721Received.selector,
            "SAFE_ADDRESS must accept Uniswap v3 position NFTs"
        );
        require(POSITION_MANAGER.code.length > 0 && SWAP_ROUTER_02.code.length > 0, "Uniswap unavailable");
        require(
            IV2UniswapFactory(UNISWAP_V3_FACTORY).getPool(WETH, USDC, WETH_USDC_FEE) != address(0),
            "WETH/USDC route unavailable"
        );

        vm.startBroadcast();
        launch = new VOIDV2Launch(safe, IVOIDV2PositionManager(POSITION_MANAGER), IERC20(USDC), initialTokenURI);
        buyRouter = new VOIDV2BuyRouter(
            IVOIDV2WETH(WETH),
            IERC20(USDC),
            IERC20(address(launch.token())),
            IVOIDV2SwapRouter(SWAP_ROUTER_02),
            WETH_USDC_FEE,
            launch.POOL_FEE()
        );
        vm.stopBroadcast();

        console2.log("VOIDCoin V2:", address(launch.token()));
        console2.log("Visible Uniswap VOID/USDC pool:", launch.pool());
        console2.log("ETH buy router:", address(buyRouter));
        console2.log("LP position locker:", address(launch.positionLocker()));
        console2.log("LP position token ID:", launch.positionTokenId());
        console2.log("Wide LP position token ID:", launch.widePositionTokenId());
        console2.log("Creator vesting wallet:", address(launch.vestingWallet()));
        console2.log("Token owner Safe:", launch.token().owner());
        console2.log("Renaming paused:", launch.token().renamePaused());
    }
}

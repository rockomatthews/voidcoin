import { createPublicClient, getAddress, getContractAddress, http } from "viem";
import { base } from "viem/chains";

export function predictDeploymentAddresses(deployerAddress, deployerNonce) {
  const deployer = getAddress(deployerAddress);
  const nonce = BigInt(deployerNonce);
  const launch = getContractAddress({ from: deployer, nonce });

  return {
    chainId: base.id,
    deployer,
    deployerNonce: nonce.toString(),
    launch,
    buyRouter: getContractAddress({ from: deployer, nonce: nonce + 1n }),
    positionLocker: getContractAddress({ from: launch, nonce: 1n }),
    vestingWallet: getContractAddress({ from: launch, nonce: 2n }),
    token: getContractAddress({ from: launch, nonce: 3n }),
  };
}

export async function predictionFromEnvironment() {
  const deployer = process.env.DEPLOYER_ADDRESS?.trim();
  const rpcUrl = process.env.BASE_MAINNET_RPC_URL?.trim();
  if (!deployer) throw new Error("DEPLOYER_ADDRESS is required (public address only; never add a private key)");
  if (!rpcUrl) throw new Error("BASE_MAINNET_RPC_URL is required");

  const client = createPublicClient({ chain: base, transport: http(rpcUrl) });
  const chainId = await client.getChainId();
  if (chainId !== base.id) throw new Error(`BASE_MAINNET_RPC_URL returned chain ${chainId}; expected ${base.id}`);
  const address = getAddress(deployer);
  const nonce = await client.getTransactionCount({ address, blockTag: "pending" });
  return predictDeploymentAddresses(address, nonce);
}

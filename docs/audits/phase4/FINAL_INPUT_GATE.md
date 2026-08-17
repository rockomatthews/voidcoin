# Final production-input gate

The phase-four reviewer found no remaining Critical or High issue at commit `870ba4b3eeeed7f929ba5d1018a8baf22994f8f3`. Final Low-severity hardening, active model tests, deterministic tooling, CI RPC configuration, and operations documentation are frozen at `ca92943a93e32a11d9724f13032a4d9f4818d78b`.

Before broadcast, freeze and independently verify:

1. Production Base Safe address, threshold, signers, and key-custody plan.
2. The Safe's current fallback handler and its live ERC-721 receiver response.
3. Permanent genesis IPFS image and JSON URI.
4. Exact constructor arguments and predicted contract addresses.
5. Runtime bytecode reproduced from the final commit with Solidity 0.8.30 and Foundry v1.7.1.
6. Official Base Uniswap v3 position manager, SwapRouter02, and canonical WETH9 addresses.
7. A non-skipped final Base fork rehearsal through the configured private RPC.
8. Deployer gas funding and explicit authorization to broadcast.
9. Legal/name-risk acceptance.

After deployment, record every address and transaction hash, verify source, prove Safe ownership and zero deployer authority, keep rename slots paused, and complete the application/indexer/moderation smoke test before activation.

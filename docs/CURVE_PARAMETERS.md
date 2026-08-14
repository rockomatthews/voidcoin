# Frozen curve parameters

The owner approved these values and the Base Mainnet deployment script hardcodes them:

- Virtual ETH reserve: `100 ether`
- Buyer-funded graduation threshold: `25 ether`
- Curve fee: 1% on buys and 1% on sells
- Maximum purchase: `1 ether` per transaction
- Hostile-pool seed: at most 0.1% of current accounted reserves, once
- Graduation supply treatment: burn excess unsold curve inventory and migrate only the quantity priced continuously against the real ETH reserve
- Initial curve inventory: 980,000,000 VOID

The creator does not contribute the 25 ETH. Buyers supply it through ordinary curve purchases. There is no deadline: if demand never reaches 25 ETH, the curve stays open and holders can continue buying and selling against its real ETH reserve.

## Modeled consequences

Using the contract's exact 1% fee and pool-favoring rounding:

- Acquiring the first 1,000,000 VOID from an untouched curve costs approximately `0.103177 ETH`, excluding gas.
- A buy-only path to 25 ETH distributes approximately 194.4 million VOID and leaves approximately 785.6 million VOID before the capped pool seed.
- Approximately 19.84% of the curve inventory has been distributed to buyers on that path.
- A 1 ETH victim purchase cannot be profitably sandwiched in the tested model even when the attacker splits 40 ETH across forty maximum-size purchases; this is a tested bound, not a universal MEV guarantee.
- Immediately before final migration, the curve calculates `tokensForLiquidity = ethReserve * tokenReserve / (virtualEthReserve + ethReserve)`. It permanently burns the remainder and migrates only `tokensForLiquidity` with all real ETH, preserving the final marginal curve price subject to integer and Uniswap mint rounding.
- In the exact 25-purchase Base fork lifecycle, approximately 628.22 million unsold VOID are burned, approximately 156.90 million VOID enter the final Uniswap position, and total supply falls to approximately 371.78 million VOID before later rename burns.

These figures are model outputs, not promises of demand, value, market capitalization, or trading outcomes. Sells change the reserves and therefore the exact graduation burn. Transaction ordering, trade splitting, gas, MEV, and rounding change realized results. The 1 ETH transaction cap limits a victim transaction but does not prevent an attacker from splitting its own position across transactions.

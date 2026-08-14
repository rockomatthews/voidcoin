# Frozen curve parameters

The owner approved these values and the Base Mainnet deployment script hardcodes them:

- Virtual ETH reserve: `100 ether`
- Buyer-funded graduation threshold: `25 ether`
- Curve fee: 1% on buys and 1% on sells
- Maximum purchase: `1 ether` per transaction
- Hostile-pool seed: at most 0.1% of current accounted reserves, once
- Initial curve inventory: 980,000,000 VOID

The creator does not contribute the 25 ETH. Buyers supply it through ordinary curve purchases. There is no deadline: if demand never reaches 25 ETH, the curve stays open and holders can continue buying and selling against its real ETH reserve.

## Modeled consequences

Using the contract's exact 1% fee and pool-favoring rounding:

- Acquiring the first 1,000,000 VOID from an untouched curve costs approximately `0.103177 ETH`, excluding gas.
- A buy-only path to 25 ETH distributes approximately 194.4 million VOID and leaves approximately 785.6 million VOID before the capped pool seed.
- Approximately 19.84% of the curve inventory has been distributed to buyers on that path.
- A 1 ETH victim purchase cannot be profitably sandwiched in the tested model even when the attacker splits 40 ETH across forty maximum-size purchases; this is a tested bound, not a universal MEV guarantee.
- Because the 100 virtual ETH are not real liquidity, migrating all remaining VOID with 25 real ETH starts the Uniswap pool approximately 80% below the final virtual-reserve marginal curve price. This discontinuity is an explicit consequence of the approved 100 / 25 parameters and must be reviewed again before Mainnet.

These figures are model outputs, not promises of demand, value, market capitalization, or trading outcomes. Sells, transaction ordering, trade splitting, gas, MEV, and rounding change realized results. The 1 ETH transaction cap limits a victim transaction but does not prevent an attacker from splitting its own position across transactions.

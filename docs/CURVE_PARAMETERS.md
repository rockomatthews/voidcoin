# Frozen curve parameters

The owner approved these values and the Base Mainnet deployment script hardcodes them:

- Virtual ETH reserve: `2 ether`
- Buyer-funded graduation threshold: `25 ether`
- Curve fee: 1% on buys and 1% on sells
- Initial curve inventory: 980,000,000 VOID

The creator does not contribute the 25 ETH. Buyers supply it through ordinary curve purchases. There is no deadline: if demand never reaches 25 ETH, the curve stays open and holders can continue buying and selling against its real ETH reserve.

## Modeled consequences

Using the contract's exact 1% fee and pool-favoring rounding:

- Acquiring the first 1,000,000 VOID from an untouched curve costs approximately `0.002064 ETH`, excluding gas.
- A simulation using 0.01 ETH purchases until 25 ETH leaves approximately 74.5 million VOID for migration.
- Approximately 92.39% of the curve inventory has been distributed to buyers in that buy-only simulation.
- The post-graduation Uniswap price is approximately 7.4% below the final virtual-reserve curve spot price because the 2 virtual ETH are not real liquidity.

These figures are model outputs, not promises of demand, value, market capitalization, or trading outcomes. Sells, transaction ordering, trade sizes, gas, MEV, and rounding change realized results.

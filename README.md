# Mumbai in-house testing

The time variables can be set manually for easier front-end testing:

MARKETPLACE
```
setChangeOrderPeriod(uint24 _newPeriod)
setAppealPeriod(uint24 _newPeriod)
```

COURT
```
setDiscoveryPeriod(uint24 _newPeriod)
setJurySelectionPeriod(uint24 _newPeriod)
setVotingPeriod(uint24 _newPeriod)
setRulingPeriod(uint24 _newPeriod)
```

## Deployed contract addresses:
```
{
  "GovernorAddress": "0x7219e2aEF21E0a491052872480F9cADC7923D70d",
  "WhitelistAddress": "0xd70bA6a871AAa1386be3e198a12CB0162D7fD365",
  "JuryPoolAddress": "0xE35f4eDd02282390c903075acB1e5C661BA5A4A3",
  "MarketplaceAddress": "0xa349e80d7a2ee8A059446ffa8402e97063a04Ca5",
  "CourtAddress": "0x04BC87174CBaf4372C305b2fa8C027b7d9D7e45A",
  "TestToken": "0x0a202A113e12096D1745a9baAd8A8aA88267Cf54",
  "EscrowFactoryAddress": "0xB3920D071E7f8D2659e497E3ee94da2C973D0DbE"
}
```

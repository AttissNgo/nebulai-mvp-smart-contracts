
# ABI
The Mediation Service smart contract has a different ABI. Please point UI towards `json_out > MediationServiceBETAAbi.json`. 

# Changes
## Mediator Pool
There are no mediators, so mediator pool is ignored. Mediator Pool contract still exists in order to preserve deployment process, but no contracts call it.
## User flow
User flow when handling disputes is preserved as much as possible. Users still need to pay a (substantially reduced) mediation fee. When both company and talent have paid the mediation fee, the Mediation Service will bypass mediator selection and instead resolve the dispute pseudorandomly. Users may then test the post-dispute flow (reclaiming mediation fees, requesting appeal, etc).
## Smart contract flow
To bypass the entire mediation panel selection and voting process, when both disputants have paid the mediation fees, instead of calling the internal `selectPanel()` function, the smart contract will instead call `_resolveDisputeBETA()` which will instantly deliver a pseudo-random resolution.

Mechanism: `_resolveDisputeBETA()` chooses a random winner, updates Dispute object, and reduces internal mediation fee accounting by half to mimic the fees paid to mediators (winner's mediation fee can be reclaimed by winner by calling `reclaimMediationFee()` as normal).
## Dependencies
Open Zeppelin, Solmate, Chainlink (VRF mock for local testing)

## Access Control

#### Governor smart contract
• multisig used to control certain restricted functions on other Nebulai smart contracts \
• admins can propose transactions, either to make functions calls or send MATIC

#### Whitelist smart contract
• controls key access points in Marketplace via onlyUser() modifier: only whitelisted accounts may create projects or activate projects (meaning that if a user is removed from whitelist, they may still complete projects but cannot start any new ones) \
• users can be whitelisted by an admin after completing off-chain verification and KYC/AML checks

## Marketplace

Abstract: Stores and manages details of an agreement between a company and service provider (Buyer and Provider). The two parties may update the status of the Project, propose changes to the original agreement via Change Order, or initiate mediation in the case of a dispute.

Project \
	- The details of an agreement between a Buyer and a service Provider are stored in a Project object. Escrow will read the details of this object when releasing funds. 

Status   \
	- The current state of the Project, which determines the control flow of user actions:  \
		• Created - Escrow holds project fee, but work has not started  \
		• Cancelled - project is withdrawn by buyer before provider begins work  \
		• Active - provider has staked in Escrow and has begun work  \
		• Discontinued - either party quits and a change order period begins to handle partial payment  \
		• Completed - provider claims project is complete and is awaiting buyer approval  \
		• Approved - buyer is satisfied, escrow will release project fee to provider, Project is closed  \
		• Challenged - buyer is unsatisfied and submits a Change Order - provider has a chance to accept OR go to mediation  \
		• Disputed - Change Order NOT accepted by provider -> Project goes to mediation  \
		• Appealed - the correctness of the mediator panel's decision is challenged -> a new mediation case is opened  \
		• Resolved_ChangeOrder - escrow releases funds according to change order  \
		• Resolved_Mediation - escrow releases funds according to decision in Mediation Service  \
		• Resolved_ReviewOverdue - escrow releases funds according to original agreement  \
		• Resolved_MediationDismissed - escrow releases funds according to original agreement

Change Order  \
	- the details of a proposed change of payment for a Project \
	- Escrow will release funds according to Change Orders which have been approved by both Buyer and Provider \

## Escrow

#### Escrow smart contract

Abstract: A unique Escrow smart contract is deployed for every Project created in Marketplace. The Escrow contract will hold funds until the Project is closed (either by completion, cancellation, Change Order, or mediation), at which time it will release funds to the appropriate parties.

#### Escrow Factory smart contract 
• Called by Marketplace to deploy Escrow contract when a Project is created

## Mediation

Abstract: Although Marketplace encourages an opportunity for Buyer and Provider to resolve disputes without mediation (via Change Order), sometimes mediation will be necessary. Disputes are resolved by a randomly-drawn panel of Nebulai users. 

#### Marketplace smart contract
• Mediation is initiated in Marketplace contract by calling disputeProject(). This creates calls createDispute() in Mediation Service contract. \
• Appeals are also made through Marketplace contract, as they also create a Dispute in the Mediation Service contract \
• Settlement can be proposed (Change Order) during Disclosure phase of a Dispute 

#### Mediation Service smart contract
• Stores the state of all Disputes and handles panel selection \
• If there is a dispute, Escrow smart contracts will reference Mediation Service contract when releasing payments 

Dispute \
	- The details of an mediation case are stored in a Dispute object. This object is created when a user calls disputeProject() in the Marketplace contract.  \
	- The Dispute object contains links to evidence files stored on IPFS. 

Dispute Phase \
	- The Dispute object is governed by the phase of the dispute, which allows certain actions to be performed at certain times. \
	- The Phase enum outlines the following phases: \
		• Disclosure - evidence may be submitted (after paying mediation fee) \
		• PanelSelection - panel is drawn randomly and drawn mediators may accept the case \
		• Voting - mediators commit a hidden vote \
		• Reveal - mediators reveal their votes
		• Decision - all votes have been counted \
		• DefaultJudgement - one party does not pay mediation fee, dispute is ruled in favor of paying party \
		• Dismissed - case is invalid and Marketplace reverts to original project conditions \
		• SettledExternally - case was settled by Change Order in Marketplace and mediation does not progress 

Mediation fees \
	- Mediation fees are collected to pay the mediators. Panel selection begins when both parties have paid the mediation fee. \
	- At the end of the case, the mediation fee of the winning party will be refunded. The losing party's mediation fee is used to pay the mediators who voted in the majority. 

Drawing mediators \
	- Upon receiving mediation fee from the second litigant, panel selection begins. The panel is drawn from the mediator pool using verifiable off-chain random numbers + a weighted drawing algorithm (a mediator who has staked more in the mediator pool is more likely to be drawn). Three times the number of mediators needed are drawn. \
	- Drawn mediators may accept the case. When the final mediator needed has accepted, the hidden voting period begins. 

Mediator incentives \
	- Mediators must deposit a stake equal to the fee they could earn by voting in the majority. If the mediator does not perform, either by failing to cast their hidden vote or failing to reveal their vote within the allotted time, delinquentCommit() or delinquentReveal() can be called in the Mediation Service contract, causing the mediator to be removed from the panel and the mediator's stake to be transferred to the Panel Reserve. \
	- The mediator's stake will be returned upon revealing their hidden voted. \
	- Mediators earn their mediator fee by voting in the majority. If a mediator votes in the minority, they will not receive payment. 

Hidden votes \
	- Mediators vote by writing a 'commit' to the contract, which is the Keccak-256 hash of an ABI encoding of the mediator's vote (true in favor of plaintiff, false in favor of defendant) and a salt (a string). In this way, the mediator's vote is committed, but it cannot be known how the mediator voted. \
	- If mediators fail to commit during the voting period, they can be removed by calling delinquentCommit() in the Mediation Service contract. This will remove the non-committed mediators from the panel, transfer their stakes to the Panel Reserve in the Mediator Pool contract, and restart the voting period so other mediators who were drawn but did not accept the case may accept and commit their votes. 

Revealing votes \
	- After all mediators commit their votes, the Reveal period begins, in which mediators must reveal their votes by calling revealVote() in the Mediation Service contract and providing their vote plus the salt used to encode it. If the reveal matches the commit, the mediator's stake is returned to them and the votes are counted. \
	- If mediators fail to reveal their votes during the reveal period, they can removed by calling delinquentReveal() in the Mediation Service contract. This will remove the non-revealing mediators from the panel and transfer their stakes to the Panel Reserve in the Mediator Pool contract. After removing non-revealing mediator, if there are enough revealed votes to establish a majority, a decision will be rendered and if the removal results in a tie, Nebulai can assign an arbiter to break the tie. 

Rendering Decision \
	- When a majority is reached, the decision is written to the Mediation Service contract. The losing party will have a chance to appeal or simply accept the reveal. \
	- Mediators who voted in the majority will receive the mediator fee. Mediators in the minority will not be compensated. 

Appeal / Resolving via Mediation Service Order \
	- The losing party may appeal the case within the APPEAL_PERIOD. An appeal is meant to challenge the validity of the decision, and as such, new evidence may not be provided. A new and larger panel will be drawn (meaning increased mediation fees) and the mediation process will be restarted. 

#### Mediator Pool smart contract
• Keeps track of whitelisted users who have registered to participate as mediators in mediation cases \
• Mediators are required to stake some MATIC to join the pool. This stake or a portion of it can be withdrawn by the mediator at any time. However, if a mediator's stake falls below the minimum stake (assigned at deployment and can also be set by Governor), the mediator will not be eligible to be drawn for new cases. Mediator drawing is weighted, so mediators who have staked more have a higher chance of being drawn. \
• Mediators may pause their membership, which will make them ineligible for drawing. \
• Governor may suspend mediators for bad conduct (such as failing to commit or reveal a vote), in which case the mediator will be ineligible for drawing and will be unable to withdraw their stake. A suspended mediator can only be reinstated by Governor. \
• A Panel Reserve is funded by the forfeited stake of delinquent Mediators (this is enforced by the Mediation Service contract), but it can also be funded directly. This fund can be accessed by the Governor smart contract to pay additional mediators or arbiters. 

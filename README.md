

## Access Control

#### Governor smart contract
• multisig used to control certain restricted functions on other Nebulai smart contracts \
• admins can propose transactions, either to make functions calls or send MATIC

#### Whitelist smart contract
• controls key access points in Marketplace via onlyUser() modifier: only whitelisted accounts may create projects or activate projects (meaning that if a user is removed from whitelist, they may still complete projects but cannot start any new ones) \
• users can be whitelisted by an admin after completing off-chain verification and KYC/AML checks

## Marketplace

Abstract: Stores and manages details of an agreement between a company and service provider (Buyer and Provider). The two parties may update the status of the Project, propose changes to the original agreement via Change Order, or initiate arbitration in the case of a dispute.

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
		• Challenged - buyer is unsatisfied and submits a Change Order - provider has a chance to accept OR go to aribtration  \
		• Disputed - Change Order NOT accepted by provider -> Project goes to arbitration  \
		• Appealed - the correctness of the court's decision is challenged -> a new arbitration case is opened  \
		• Resolved_ChangeOrder - escrow releases funds according to change order  \
		• Resolved_CourtOrder - escrow releases funds according to court petition  \
		• Resolved_DelinquentPayment - escrow releases funds according to original agreement  \
		• Resolved_ArbitrationDismissed - escrow releases funds according to original agreement

Change Order  \
	- the details of a proposed change of payment for a Project \
	- Escrow will release funds according to Change Orders which have been approved by both Buyer and Provider \

## Escrow

#### Escrow smart contract

Abstract: A unique Escrow smart contract is deployed for every Project created in Marketplace. The Escrow contract will hold funds until the Project is closed (either by completion, cancellation, Change Order, or arbitration), at which time it will release funds to the appropriate parties.

#### Escrow Factory smart contract 
• Called by Marketplace to deploy Escrow contract when a Project is created

# Arbitration

Abstract: Although Marketplace encourages an opportunity for Buyer and Provider to resolve disputes without arbitration (via Change Order), sometimes arbitration will be necessary. Disputes are resolved by a randomly-drawn jury of Nebulai users. 

#### Marketplace smart contract
• Arbitration is initiated in Marketplace contract by calling disputeProject(). This creates calls createPetition() in Court contract. \
• Appeals are also made through Marketplace contract, as they also create a Petition in the Court contract \
• Settlement can be proposed (Change Order) during Discovery phase of a Petition 

#### Court smart contract
• Stores the state of all arbitration cases and handles jury selection \
• If there is a dispute, Escrow smart contracts will reference Court contract when releasing payments 

Petition \
	- The details of an arbitration case are stored in a Petition object. This object is created when a user calls disputeProject() in the Marketplace contract.  \
	- The Petition object contains links to evidence files stored on IPFS. 

Petition Phase \
	- The Petition object is governed by the phase of the petition, which allows certain actions to be performed at certain times. \
	- The Phase enum outlines the following phases: \
		• Discovery - evidence may be submitted (after paying arbitration fee) \
		• JurySelection - jury is drawn randomly and drawn jurors may accept the case \
		• Voting - jurors commit a hidden vote \
		• Ruling - jurors reveal their votes
		• Verdict - all votes have been counted and a ruling is made \
		• DefaultJudgement - one party does not pay arbitration fee, petition is ruled in favor of paying party \
		• Dismissed - case is invalid and Marketplace reverts to original project conditions \
		• SettledExternally - case was settled by Change Order in Marketplace and arbitration does not progress 

Arbitration fees \
	- Arbitration fees are collected to pay the jurors. Jury selection begins when both litigants have paid the arbitration fee. \
	- At the end of the case, the arbitration fee of the winning party will be refunded. The losing party's arbitration fee is used to pay the jurors who voted in the majority. 

Drawing jurors \
	- Upon receiving arbitration fee from the second litigant, jury selection begins. The jury is drawn from the jury pool using verifiable off-chain random numbers + a weighted drawing algorithm (a juror who has staked more in the jury pool is more likely to be drawn). Three times the number of jurors needed are drawn. \
	- Drawn jurors may accept the case. When the final juror needed has accepted, the hidden voting period begins. 

Juror incentives \
	- Jurors must deposit a stake equal to the fee they could earn by voting in the majority. If the juror does not perform, either by failing to cast their hidden vote or failing to reveal their vote within the allotted time, delinquentCommit() or delinquentReveal() can be called in the Court contract, causing the juror to be removed from the jury the juror's stake to be transferred to the Jury Reserve. \
	- The juror's stake will be returned upon revealing their hidden voted. \
	- Jurors earn their juror fee by voting in the majority. If a juror votes in the minority, they will not receive payment. 

Hidden votes \
	- Jurors vote by writing a 'commit' to the contract, which is the Keccak-256 hash of an ABI encoding of the juror's vote (true in favor of plaintiff, false in favor of defendant) and a salt (a string). In this way, the juror's vote is committed, but it cannot be known how the juror voted. \
	- If jurors fail to commit during the voting period, they can be removed by calling delinquentCommit() in the Court contract. This will remove the non-committed jurors from the jury, transfer their stakes to the Jury Reserve in the Jury Pool contract, and restart the voting period so other jurors who were drawn but did not accept the case may accept and commit their votes. 

Revealing votes \
	- After all jurors commit their votes, the Ruling period begins, in which jurors must reveal their votes by calling revealVote() in the Court contract and providing their vote plus the salt used to encode it. If the reveal matches the commit, the juror's stake is returned to them and the votes are counted. \
	- If jurors fail to reveal their votes during the ruling period, they can removed by calling delinquentReveal() in the Court contract. This will remove the non-revealing jurors from the jury and transfer their stakes to the Jury Reserve in the Jury Pool contract. After removing non-revealing juror, if there are enough revealed votes to establish a majority, a verdict will be rendered and if the removal results in a tie, Nebulai can assign an arbiter to break the tie. 

Rendering Verdict \
	- When a majority is reached, the verdict is written to the Court contract. The losing party will have a chance to appeal or simply accept the ruling. \
	- Jurors who voted in the majority will receive the juror fee. Jurors in the minority will not be compensated. 

Appeal / Resolving via Court Order \
	- The losing party may appeal the case within the APPEAL_PERIOD. An appeal is meant to challenge the validity of the verdict, and as such, new evidence may not be provided. A new and larger jury will be drawn (meaning increased arbitration fees) and the arbitration process will be restarted. 

#### Jury Pool smart contract
• Keeps track of whitelisted users who have registered to participate as jurors in arbitration cases \
• Jurors are required to stake some MATIC to join the pool. This stake or a portion of it can be withdrawn by the juror at any time. However, if a juror's stake falls below the minimum stake (assigned at deployment and can also be set by Governor), the juror will not be eligible to be drawn for new cases. Juror drawing is weighted, so jurors who have staked more have a higher chance of being drawn. \
• Jurors may pause their membership, which will make them ineligible for drawing. \
• Governor may suspend jurors for bad conduct (such as failing to commit or reveal a vote), in which case the juror will be ineligible for drawing and will be unable to withdraw their stake. A suspended juror can only be reinstated by Governor. \
• A Jury Reserve is funded by the forfeited stake of delinquent Jurors (this is enforced by the Court contract), but it can also be funded directly. This fund can be accessed by the Governor smart contract to pay additional jurors or arbiters. 

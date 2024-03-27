// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./DataStructuresLibrary.sol";
import "chainlink/VRFCoordinatorV2Interface.sol";
import "chainlink/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./Interfaces/IGovernor.sol";
import "./Interfaces/IMarketplace.sol";
import "./Interfaces/IMediatorPool.sol";

contract MediationService is VRFConsumerBaseV2, DataStructuresLibrary {
    using Counters for Counters.Counter;

    address public immutable GOVERNOR;
    address public immutable MARKETPLACE;
    IMediatorPool public mediatorPool;

    /**
     * @notice the amount that will be paid to mediators who vote in the majority
     * @notice mediators must stake an amount equal to mediatorFlatFee to accept a case
     */
    uint256 public mediatorFlatFee = 20 ether; 

    /**
     * @notice the mediation fees held for a Dispute ID
     */
    mapping(uint256 => uint256) private feesHeld; 

    /**
     * @notice parameters for requesting random words from Chainlink VRF
     */
    VRFCoordinatorV2Interface public immutable VRF_COORDINATOR;
    bytes32 public keyHash;
    uint64 public subscriptionId;
    uint16 public requestConfirmations = 3;
    uint32 public callbackGasLimit = 800000;
    uint32 public numWords = 2; 
    mapping(uint256 => uint256) public vrfRequestToDispute;

    Counters.Counter public disputeIds;
    mapping(uint256 => Dispute) private disputes; // disputeId => Dispute
    mapping(uint256 => Panel) private panels; // disputeId => Panel
    mapping(address => mapping(uint256 => uint256)) private mediatorStakes; // mediator address => disputeId => stake
    mapping(address => mapping(uint256 => bytes32)) private commits; // mediator address => disputeId => commit
    mapping(address => mapping(uint256 => bool)) private votes; // mediator address => disputeId => vote
    mapping(address => mapping(uint256 => bool)) private hasRevealed; 
    mapping(address => uint256) private feesToMediator;
    mapping(uint256 => bool) public votesTied;
    mapping(uint256 => address) public arbiter;

    uint24 public constant DISCLOSURE_PERIOD = 7 days;
    uint24 public constant PANEL_SELECTION_PERIOD = 3 days;
    uint24 public constant VOTING_PERIOD = 4 days;
    uint24 public constant REVEAL_PERIOD = 3 days;

    /**
     * @dev constant for MVP - should be adjustable (via Governor) in production
     */
    uint256 public constant PANEL_SIZE_NORMAL = 3;
    uint256 public constant PANEL_SIZE_APPEAL = 5;
    uint256 public constant PANEL_DRAWING_MULTIPLIER_NORMAL = 3;
    uint256 public constant PANEL_DRAWING_MULTIPLIER_APPEAL = 2;

    event DisputeCreated(uint256 indexed disputeId, uint256 projectId);
    event AppealCreated(uint256 indexed disputeId, uint256 indexed originalDisputeId, uint256 projectId);
    event MediationFeePaid(uint256 indexed disputeId, address indexed user);
    event PanelSelectionInitiated(uint256 indexed disputeId, uint256 requestId);
    event AdditionalMediatorDrawingInitiated(uint256 indexed disputeId, uint256 requestId);
    event AdditionalMediatorsAssigned(uint256 indexed disputeId, address[] assignedMediators);
    event PanelDrawn(uint256 indexed disputeId, bool isRedraw);
    event MediatorConfirmed(uint256 indexed disputeId, address mediatorAddress);
    event VotingInitiated(uint256 indexed disputeId);
    event VoteCommitted(uint256 indexed disputeId, address indexed mediator, bytes32 commit);
    event RevealInitiated(uint256 indexed disputeId);
    event VoteRevealed(uint256 indexed disputeId, address indexed mediator, bool vote);
    event DecisionReached(uint256 indexed disputeId, bool decision, uint256 majorityVotes);
    event MediatorFeesClaimed(address indexed mediator, uint256 amount);
    event MediationFeeReclaimed(uint256 indexed disputeId, address indexed claimedBy, uint256 amount);
    event CaseDismissed(uint256 indexed disputeId);
    event SettledExternally(uint256 indexed disputeId);
    event DefaultDecisionEntered(uint256 indexed disputeId, address indexed claimedBy, bool decision);
    event MediatorRemoved(uint256 indexed disputeId, address indexed mediator);
    event OverdueReveal(uint256 indexed disputeId, bool deadlocked);
    event ArbiterAssigned(uint256 indexed disputeId, address indexed arbiter);
    event ArbiterVote(uint256 indexed disputeId, address indexed arbiter, bool vote);

    error MediationService__TransferFailed();
    // permissions
    error MediationService__OnlyGovernor();
    error MediationService__OnlyAdmin();
    error MediationService__OnlyMarketplace();
    error MediationService__ProjectHasOpenDispute();
    error MediationService__OnlyDisputant();
    // dispute
    error MediationService__MediationFeeAlreadyPaid();
    error MediationService__MediationFeeNotPaid();
    error MediationService__InsufficientAmount();
    error MediationService__EvidenceCanNoLongerBeSubmitted();
    error MediationService__MediationFeeCannotBeReclaimed();
    error MediationService__OnlyPrevailingParty();
    error MediationService__MediationFeeAlreadyReclaimed();
    error MediationService__DisputeDoesNotExist();
    error MediationService__DisputeCannotBeAppealed();
    error MediationService__FeesNotOverdue();
    error MediationService__ProjectIsNotDisputed();
    error MediationService__OnlyDuringDisclosure();
    error MediationService__OnlyDuringPanelSelection();
    error MediationService__InitialSelectionPeriodStillOpen();
    error MediationService__PanelAlreadyRedrawn();
    error MediationService__PanelNotRedrawn();
    error MediationService__VotingPeriodStillActive();
    error MediationService__NoOverdueCommits();
    error MediationService__OnlyDuringReveal();
    error MediationService__RevealPeriodStillActive();
    error MediationService__CaseNotDeadlocked();
    error MediationService__InvalidArbiter();
    // mediator actions
    error MediationService__MediatorSeatsFilled();
    error MediationService__InvalidMediator();
    error MediationService__InsufficientMediatorStake();
    error MediationService__AlreadyConfirmedMediator();
    error MediationService__NotDrawnMediator();
    error MediationService__MediatorHasAlreadyCommmitedVote();
    error MediationService__InvalidCommit();
    error MediationService__CannotRevealBeforeAllVotesCommitted();
    error MediationService__AlreadyRevealed();
    error MediationService__RevealDoesNotMatchCommit();
    error MediationService__VoteHasNotBeenRevealed();
    error MediationService__NoMediatorFeesOwed();

    modifier onlyGovernor() {
        if(msg.sender != GOVERNOR) revert MediationService__OnlyGovernor();
        _;
    }

    modifier onlyMarketplace() {
        if(msg.sender != MARKETPLACE) revert MediationService__OnlyMarketplace();
        _;
    }

    constructor(
        address _governor,
        address _mediatorPool,
        address _vrfCoordinatorV2, 
        bytes32 _keyHash,
        uint64 _subscriptionId,
        address _calculatedMarketplace
    ) 
         VRFConsumerBaseV2(_vrfCoordinatorV2) 
    {
        GOVERNOR = _governor;
        mediatorPool = IMediatorPool(_mediatorPool);
        VRF_COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinatorV2);
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        MARKETPLACE = _calculatedMarketplace;
    }

    /**
     * @notice callback from Chainlink VRF - uses verifiable random numbers to select mediators
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {   
        Dispute storage dispute = disputes[vrfRequestToDispute[requestId]];
        bool isRedraw;   
        if (dispute.selectionStart != 0) isRedraw = true;
        Panel storage panel = panels[dispute.disputeId];
        uint256 numNeeded = mediatorsNeeded(dispute.disputeId) * PANEL_DRAWING_MULTIPLIER_NORMAL; 
        if (isRedraw) numNeeded = mediatorsNeeded(dispute.disputeId) * PANEL_DRAWING_MULTIPLIER_APPEAL;
        address[] memory mediatorsDrawn = new address[](numNeeded);
        uint256 nonce = 0;
        uint256 numSelected = 0;
        uint256 poolSize = mediatorPool.mediatorPoolSize();

        while (numSelected < numNeeded) {
            address mediatorA = mediatorPool.getMediator(uint256(keccak256(abi.encodePacked(randomWords[0], nonce))) % poolSize);
            address mediatorB = mediatorPool.getMediator(uint256(keccak256(abi.encodePacked(randomWords[1], nonce))) % poolSize);
            address drawnMediator = _weightedDrawing(mediatorA, mediatorB, randomWords[0]);
            bool isInvalid = false; 
            if (!mediatorPool.isEligible(drawnMediator)) isInvalid = true;
            if (drawnMediator == dispute.claimant || drawnMediator == dispute.respondent) isInvalid = true;
            for (uint i; i < mediatorsDrawn.length; ++i) {
                if (mediatorsDrawn[i] == drawnMediator) isInvalid = true; 
            }
            if (isRedraw) { 
                for (uint i; i < panel.drawnMediators.length; ++i) {
                    if(panel.drawnMediators[i] == drawnMediator) isInvalid = true;
                }
            }
            if (!isInvalid) {
                mediatorsDrawn[numSelected] = drawnMediator;
                ++numSelected;
            }
            ++nonce; 
        }

        if(!isRedraw) {
            dispute.selectionStart = block.timestamp;
            panel.drawnMediators = mediatorsDrawn;
        } else {
            for (uint i; i < mediatorsDrawn.length; ++i) {
                panel.drawnMediators.push(mediatorsDrawn[i]);
            }
        }
        emit PanelDrawn(dispute.disputeId, isRedraw);   
    }

    /**
     * @dev selects one of two randomly drawn mediators using weighted probability based on stake in mediator pool
     */
    function _weightedDrawing(
        address _mediatorA, 
        address _mediatorB, 
        uint256 _randomWord
    ) 
        internal 
        view 
        returns (address) 
    {
        uint256 stakeA = mediatorPool.getMediatorStake(_mediatorA);
        uint256 stakeB = mediatorPool.getMediatorStake(_mediatorB);
        address drawnMediator = _mediatorA;
        if (stakeA > stakeB) {
            if (_randomWord % 100 >= (stakeA * 100) / (stakeA + stakeB)) drawnMediator = _mediatorB;
        } else if(stakeB > stakeA) {
            if (_randomWord % 100 < (stakeB * 100) / (stakeA + stakeB)) drawnMediator = _mediatorB;
        }
        return drawnMediator;
    }

    function mediatorsNeeded(uint256 disputeId) public view returns (uint256) {
        if (!disputes[disputeId].isAppeal) return PANEL_SIZE_NORMAL;
        else return PANEL_SIZE_APPEAL;
    } 

    function calculateMediationFee(bool isAppeal) public view returns (uint256) {
        if (!isAppeal) return PANEL_SIZE_NORMAL * mediatorFlatFee;
        else return PANEL_SIZE_APPEAL * mediatorFlatFee;
    }

    ////////////////////
    ///   DISPUTE   ///
    ////////////////////

    /**
     * @notice creates a new dispute
     * @dev can only be called from Marketplace disputeProject()
     * @dev dispute ID cannot be zero
     * @return disputeId
     */
    function createDispute(
        uint256 _projectId,
        uint256 _adjustedProjectFee,
        uint256 _providerStakeForfeit,
        address _claimant,
        address _respondent
    )
        external
        onlyMarketplace
        returns (uint256)
    {
        if (IMarketplace(msg.sender).getDisputeId(_projectId) != 0) revert MediationService__ProjectHasOpenDispute();
        disputeIds.increment();
        uint256 disputeId = disputeIds.current();
        Dispute memory dispute;
        dispute.disputeId = disputeId;
        dispute.projectId = _projectId;
        dispute.adjustedProjectFee = _adjustedProjectFee;
        dispute.providerStakeForfeit = _providerStakeForfeit;
        dispute.claimant = _claimant;
        dispute.respondent = _respondent;
        dispute.mediationFee = calculateMediationFee(false);
        dispute.disclosureStart = block.timestamp;
        disputes[disputeId] = dispute;
        emit DisputeCreated(disputeId, _projectId);
        return disputeId;
    }

    /**
     *  @notice creates new 'appeal' dispute with project/dispute information from original dispute 
     *  mediation fee is higher to compensate larger panel
     *  @dev can only be called from Marketplace appealDecision()
     *  @return disputeID of new 'appeal' dispute 
     */
    function appeal(uint256 _projectId) external onlyMarketplace returns (uint256) {
        uint256 originalDisputeId = IMarketplace(msg.sender).getDisputeId(_projectId); 
        if (originalDisputeId == 0) revert MediationService__DisputeDoesNotExist();
        Dispute memory originalDispute = getDispute(originalDisputeId);
        if (originalDispute.isAppeal) revert MediationService__DisputeCannotBeAppealed();
        disputeIds.increment(); 
        uint256 disputeId = disputeIds.current();
        Dispute memory dispute;
        dispute.disputeId = disputeId;
        dispute.projectId = _projectId;
        dispute.adjustedProjectFee = originalDispute.adjustedProjectFee;
        dispute.providerStakeForfeit = originalDispute.providerStakeForfeit;
        dispute.claimant = originalDispute.claimant;
        dispute.respondent = originalDispute.respondent;
        dispute.isAppeal = true;
        dispute.mediationFee = calculateMediationFee(true);
        dispute.disclosureStart = block.timestamp;
        disputes[disputeId] = dispute;
        emit AppealCreated(disputeId, originalDisputeId, _projectId);
        return disputeId;
    }

    /**
     * @notice pay mediation fee and submit evidence
     * @notice when both disputants have paid, random words will be requested and mediator panel will be drawn
     */
    function payMediationFee(uint256 _disputeId, string[] calldata _evidenceURIs) external payable {
        Dispute storage dispute = disputes[_disputeId];
        if (msg.sender != dispute.claimant && msg.sender != dispute.respondent) revert MediationService__OnlyDisputant();
        if (
            (msg.sender == dispute.claimant && dispute.feePaidClaimant) || 
            (msg.sender == dispute.respondent && dispute.feePaidRespondent)
        ) revert MediationService__MediationFeeAlreadyPaid();
        if (msg.value < dispute.mediationFee) revert MediationService__InsufficientAmount();
        (msg.sender == dispute.claimant) ? dispute.feePaidClaimant = true : dispute.feePaidRespondent = true;
        feesHeld[_disputeId] += msg.value;
        for (uint i = 0; i < _evidenceURIs.length; ++i) {
            dispute.evidence.push(_evidenceURIs[i]);
        }
        emit MediationFeePaid(_disputeId, msg.sender);

        if (dispute.feePaidClaimant && dispute.feePaidRespondent) {
            uint256 requestId = _selectPanel(_disputeId);
            dispute.phase = Phase.PanelSelection;
            emit PanelSelectionInitiated(_disputeId, requestId);
        }
    }

    /**
     * @notice allows disputants who have paid mediation fee to submit additional evidence
     * @notice evidence can only be submitted during Disclosure and Panel Selection
     */
    function submitAdditionalEvidence(uint256 _disputeId, string[] calldata _evidenceURIs) external {
        Dispute storage dispute = disputes[_disputeId];
        if (msg.sender != dispute.claimant && msg.sender != dispute.respondent) revert MediationService__OnlyDisputant();
        if (dispute.phase != Phase.Disclosure && dispute.phase != Phase.PanelSelection) {
            revert MediationService__EvidenceCanNoLongerBeSubmitted();
        }
        if (
            (msg.sender == dispute.claimant && !dispute.feePaidClaimant) ||
            (msg.sender == dispute.respondent && !dispute.feePaidRespondent)
        ) revert MediationService__MediationFeeNotPaid();
        for (uint i = 0; i < _evidenceURIs.length; ++i) {
            dispute.evidence.push(_evidenceURIs[i]); 
        }
    }

    /**
     * @notice allows revailing party to reclaim mediation fee after mediation is complete
     */
    function reclaimMediationFee(uint256 _disputeId) external {
        Dispute memory dispute = getDispute(_disputeId);
        if (msg.sender != dispute.claimant && msg.sender != dispute.respondent) revert MediationService__OnlyDisputant();
        if (dispute.phase == Phase.Decision) {
            if (dispute.granted && msg.sender != dispute.claimant) revert MediationService__OnlyPrevailingParty();
            else if (!dispute.granted && msg.sender != dispute.respondent) revert MediationService__OnlyPrevailingParty();
        } else if (dispute.phase == Phase.SettledExternally) {
            if (!dispute.feePaidClaimant && msg.sender == dispute.claimant) revert MediationService__MediationFeeNotPaid();
            else if (!dispute.feePaidRespondent && msg.sender == dispute.respondent) revert MediationService__MediationFeeNotPaid();
        } else revert MediationService__MediationFeeCannotBeReclaimed();
        if (feesHeld[_disputeId] != dispute.mediationFee) revert MediationService__MediationFeeAlreadyReclaimed();
        uint256 reclaimAmount = feesHeld[_disputeId];
        feesHeld[_disputeId] -= reclaimAmount;
        (bool success, ) = msg.sender.call{value: reclaimAmount}("");
        if (!success) revert MediationService__TransferFailed();
        emit MediationFeeReclaimed(_disputeId, msg.sender, reclaimAmount);
    }

    /**
     * @notice closes a Dispute when mediation fees have not been paid within DISCOVER_PERIOD
     * @notice a dismissed case will return to original project fee amount in Marketplace
     */
    function dismissUnpaidCase(uint256 _disputeId) public {
        Dispute storage dispute = disputes[_disputeId];
        if (dispute.disputeId == 0) revert MediationService__DisputeDoesNotExist();
        if (block.timestamp < dispute.disclosureStart + DISCLOSURE_PERIOD) revert MediationService__FeesNotOverdue();
        if (dispute.feePaidClaimant || dispute.feePaidRespondent) revert MediationService__MediationFeeAlreadyPaid();
        dispute.phase = Phase.Dismissed;
        emit CaseDismissed(_disputeId);
    } 

    /**
     * @dev called by Marketplace when a change order (settlement) is approved on a disputed Project
     */
    function settledExternally(uint256 _disputeId) external onlyMarketplace {
        Dispute storage dispute = disputes[_disputeId];
        dispute.phase = Phase.SettledExternally;
        emit SettledExternally(dispute.disputeId);
    }

    /**
     * @notice rules in favor disputant who paid mediation fee when one disputant has not paid within DISCLOSURE_PERIOD
     * @dev if both disputants have paid, phase will have been advanced to PanelSelection and function will revert
     */
    function requestDefaultDecision(uint256 _disputeId) external {
        Dispute storage dispute = disputes[_disputeId];
        if (msg.sender != dispute.claimant && msg.sender != dispute.respondent) revert MediationService__OnlyDisputant();
        if (dispute.phase != Phase.Disclosure) revert MediationService__OnlyDuringDisclosure();
        if (msg.sender == dispute.claimant) {
            if (!dispute.feePaidClaimant) revert MediationService__MediationFeeNotPaid();
        } else {
            if (!dispute.feePaidRespondent) revert MediationService__MediationFeeNotPaid();
        }
        if (block.timestamp < dispute.disclosureStart + DISCLOSURE_PERIOD) revert MediationService__FeesNotOverdue();
        (msg.sender == dispute.claimant) ? dispute.granted = true : dispute.granted = false;
        dispute.phase = Phase.DefaultDecision;
        uint256 reclaimAmount = feesHeld[_disputeId];
        feesHeld[_disputeId] -= reclaimAmount;
        (bool success, ) = msg.sender.call{value: reclaimAmount}("");
        if (!success) revert MediationService__TransferFailed();
        emit DefaultDecisionEntered(_disputeId, msg.sender, dispute.granted);
    }

    /////////////////
    ///   PANEL   ///
    /////////////////

    /**
     * @dev creates a request for random words from Chainlink VRF - called internally when panel selection is needed
     * @return requestID from Chainlink VRF
     */
    function _selectPanel(uint256 _disputeId) private returns (uint256) {
        uint256 requestId = VRF_COORDINATOR.requestRandomWords(
            keyHash, 
            subscriptionId, 
            requestConfirmations, 
            callbackGasLimit, 
            numWords
        );
        vrfRequestToDispute[requestId] = _disputeId;
        return requestId;
    }

    /**
     * @dev called internally when enough mediators have accepted a case
     */
    function _panelAssembled(uint256 _disputeId) private {
        Dispute storage dispute = disputes[_disputeId];
        dispute.phase = Phase.Voting;
        dispute.votingStart = block.timestamp;
        emit VotingInitiated(_disputeId);
    }

    /**
     * @dev called internally when all mediators have committed their hidden votes
     */
    function _allVotesCommitted(uint256 _disputeId) private {
        Dispute storage dispute = disputes[_disputeId];
        dispute.phase = Phase.Reveal;
        dispute.revealStart = block.timestamp;
        emit RevealInitiated(_disputeId);
    }

    /**
     * @dev called internally when a mediator reveals vote or when overdueReveal() is called
     * @return votesFor number of votes in favor of dispute
     * @return votesAgainst number of votes against dispute
     */
    function _countVotes(uint256 _disputeId) private view returns (uint256, uint256) {
        Panel memory panel = getPanel(_disputeId);
        uint256 votesFor;
        uint256 votesAgainst;
        for (uint i; i < panel.confirmedMediators.length; ++i) {
            if (hasRevealedVote(panel.confirmedMediators[i], _disputeId)) {
                (votes[panel.confirmedMediators[i]][_disputeId]) ? ++votesFor : ++votesAgainst;
            }
        }
        return(votesFor, votesAgainst);
    }

    /**
     * @notice mediators who voted in majority may claim mediator fee, mediators in minority will not receive payment
     * @dev called internally when there are enough votes to render a decision
     * @dev in the case of remaining mediation fees, the remainder will be transferred to the Panel Reserve
     */
    function _renderDecision(uint256 _disputeId, uint256 _votesFor, uint256 _votesAgainst) private {
        Dispute storage dispute = disputes[_disputeId];
        dispute.phase = Phase.Decision;
        dispute.granted = (_votesFor > _votesAgainst);
        dispute.decisionRenderedDate = block.timestamp;
        uint256 mediatorFee = dispute.mediationFee / mediatorsNeeded(_disputeId);
        uint256 remainingFees = dispute.mediationFee;
        Panel memory panel = getPanel(_disputeId);
        for (uint i; i < panel.confirmedMediators.length; ++i) {
            if (hasRevealedVote(panel.confirmedMediators[i], _disputeId)) {
                if (dispute.granted && votes[panel.confirmedMediators[i]][_disputeId] == true) {
                    feesToMediator[panel.confirmedMediators[i]] += mediatorFee;
                    remainingFees -= mediatorFee;
                } else if (!dispute.granted && votes[panel.confirmedMediators[i]][_disputeId] == false) {
                    feesToMediator[panel.confirmedMediators[i]] += mediatorFee;
                    remainingFees -= mediatorFee;
                }
            }
        }
        feesHeld[_disputeId] -= dispute.mediationFee;
        if (remainingFees > 0) {
            mediatorPool.fundMediationReserve{value: remainingFees}();
        }
        uint256 majorityVotes;
        (dispute.granted) ? majorityVotes = _votesFor : majorityVotes = _votesAgainst;
        emit DecisionReached(_disputeId, dispute.granted, majorityVotes);
    }

    ////////////////////////////
    ///   MEDIATOR ACTIONS   ///
    ////////////////////////////

    /**
     * @notice drawn mediator may accept a case by staking an amount equal to the mediatorFlatFee
     * @dev calls _panelAssembled() when enough mediators have accepted case
     */
    function acceptCase(uint256 _disputeId) external payable {
        Panel storage panel = panels[_disputeId];
        if (panel.confirmedMediators.length >= mediatorsNeeded(_disputeId)) revert MediationService__MediatorSeatsFilled();
        for (uint i; i < panel.confirmedMediators.length; ++i) {
            if (msg.sender == panel.confirmedMediators[i]) revert MediationService__AlreadyConfirmedMediator();
        }
        if (msg.value < mediatorFlatFee) revert MediationService__InsufficientMediatorStake();
        if (mediatorPool.getMediatorStatus(msg.sender) != IMediatorPool.MediatorStatus.Active) revert MediationService__InvalidMediator();
        bool isDrawnMediator;
        for (uint i; i < panel.drawnMediators.length; ++i) {
            if (msg.sender == panel.drawnMediators[i]) {
                isDrawnMediator = true;
                break;
            }
        }
        if (!isDrawnMediator) revert MediationService__NotDrawnMediator();
        mediatorStakes[msg.sender][_disputeId] = msg.value;
        panel.confirmedMediators.push(msg.sender);
        emit MediatorConfirmed(_disputeId, msg.sender);
        if (panel.confirmedMediators.length == mediatorsNeeded(_disputeId)) {
            _panelAssembled(_disputeId);
        }
    }

    /**
     * @notice mediator commits their hidden vote
     * @dev calls _allVotesCommitted() if call is the last commit needed
     * @param _commit keccak256 hash of packed abi encoding of vote (bool) + mediator's salt
     */
    function commitVote(uint256 _disputeId, bytes32 _commit) external {
        if (uint(getCommit(msg.sender, _disputeId)) != 0) revert MediationService__MediatorHasAlreadyCommmitedVote();
        if (uint(_commit) == 0) revert MediationService__InvalidCommit();
        Panel memory panel = getPanel(_disputeId);
        bool isMediator;
        uint256 voteCount;
        for (uint i; i < panel.confirmedMediators.length; ++i) {
            if (msg.sender == panel.confirmedMediators[i]) isMediator = true;
            if (uint(getCommit(panel.confirmedMediators[i], _disputeId)) != 0) ++voteCount;
        }
        if (!isMediator) revert MediationService__InvalidMediator();
        commits[msg.sender][_disputeId] = _commit;
        emit VoteCommitted(_disputeId, msg.sender, _commit);
        if (voteCount + 1 >= mediatorsNeeded(_disputeId)) {
            _allVotesCommitted(_disputeId);
        }
    }

    /**
     * @notice mediator reveals hidden vote and mediator stake is returned
     * @dev calls _renderDecision() when all mediators have revealed
     * @param _vote bool originally encoded in commit
     * @param _salt string originally encoded in commit
     */
    function revealVote(uint256 _disputeId, bool _vote, string calldata _salt) external {
        if (!isConfirmedMediator(_disputeId, msg.sender)) revert MediationService__InvalidMediator();
        if (getDispute(_disputeId).phase != Phase.Reveal) revert MediationService__CannotRevealBeforeAllVotesCommitted();
        if (hasRevealedVote(msg.sender, _disputeId)) revert MediationService__AlreadyRevealed();
        bytes32 reveal = keccak256(abi.encodePacked(_vote, _salt));
        if (reveal != getCommit(msg.sender, _disputeId)) revert MediationService__RevealDoesNotMatchCommit();
        votes[msg.sender][_disputeId] = _vote;
        hasRevealed[msg.sender][_disputeId] = true;
        uint256 stakeRefund = mediatorStakes[msg.sender][_disputeId];
        mediatorStakes[msg.sender][_disputeId] -= stakeRefund;
        (bool success,) = msg.sender.call{value: stakeRefund}("");
        if (!success) revert MediationService__TransferFailed();
        emit VoteRevealed(_disputeId, msg.sender, _vote);
        (uint256 votesFor, uint256 votesAgainst) = _countVotes(_disputeId);
        if (votesFor + votesAgainst == mediatorsNeeded(_disputeId)) {
            _renderDecision(_disputeId, votesFor, votesAgainst);
        }
    }

    /**
     * @notice withdraw fees earned for serving on panel
     */
    function claimMediatorFees() external {
        uint256 feesOwed = feesToMediator[msg.sender];
        if (feesOwed < 1) revert MediationService__NoMediatorFeesOwed();
        feesToMediator[msg.sender] = 0;
        (bool success,) = msg.sender.call{value: feesOwed}("");
        if (!success) revert MediationService__TransferFailed();
        emit MediatorFeesClaimed(msg.sender, feesOwed);
    }

    ////////////////////////////
    ///   PANEL EXCEPTIONS   ///
    ////////////////////////////

    /**
     * @notice draws additional mediators if not enough mediators have accepted case after PANEL_SELECTION_PERIOD elapses
     * @dev can only be called once per case
     */
    function drawAdditionalMediators(uint256 _disputeId) external {
        Dispute memory dispute = getDispute(_disputeId);
        if (dispute.phase != Phase.PanelSelection) revert MediationService__OnlyDuringPanelSelection();
        if (block.timestamp < dispute.selectionStart + PANEL_SELECTION_PERIOD) {
            revert MediationService__InitialSelectionPeriodStillOpen();
        } 
        Panel memory panel = getPanel(_disputeId);
        if (panel.drawnMediators.length > mediatorsNeeded(_disputeId) * PANEL_DRAWING_MULTIPLIER_NORMAL) {
            revert MediationService__PanelAlreadyRedrawn();
        }
        uint256 requestId = _selectPanel(_disputeId);
        emit AdditionalMediatorDrawingInitiated(dispute.disputeId, requestId);
    }

    /**
     * @notice assigns additional addresses to drawnMediators in Panel
     * @dev can only be called by admin and only after a redraw has been made via drawAdditionalMediators()
     */
    function assignAdditionalMediators(uint256 _disputeId, address[] calldata _additionalMediators) external {
        if (!IGovernor(GOVERNOR).isAdmin(msg.sender)) revert MediationService__OnlyAdmin();
        Dispute memory dispute = getDispute(_disputeId);
        if (dispute.phase != Phase.PanelSelection) revert MediationService__OnlyDuringPanelSelection();
        if (block.timestamp < dispute.selectionStart + PANEL_SELECTION_PERIOD) {
            revert MediationService__InitialSelectionPeriodStillOpen();
        } 
        Panel storage panel = panels[_disputeId];
        if (!(panel.drawnMediators.length > mediatorsNeeded(_disputeId) * 3)) revert MediationService__PanelNotRedrawn();
        for (uint i; i < _additionalMediators.length; ++i) {
            if (isConfirmedMediator(dispute.disputeId, _additionalMediators[i])) revert MediationService__InvalidMediator();
            if (!mediatorPool.isEligible(_additionalMediators[i])) revert MediationService__InvalidMediator();
            if (_additionalMediators[i] == dispute.claimant || _additionalMediators[i] == dispute.respondent) {
                revert MediationService__InvalidMediator();
            }
            panel.drawnMediators.push(_additionalMediators[i]);
        }
        emit AdditionalMediatorsAssigned(dispute.disputeId, _additionalMediators);
    }

    /**
     * @notice removes mediator who does not commit vote within VOTING_PERIOD
     * @notice transfers stake of overdue mediator to Panel Reserve
     * @dev restarts voting period so remaining drawn mediators may accept case and vote
     */
    function overdueCommit(uint256 _disputeId) external {
        Dispute storage dispute = disputes[_disputeId];
        if (dispute.phase != Phase.Voting) revert MediationService__NoOverdueCommits();
        if (block.timestamp < dispute.votingStart + VOTING_PERIOD) revert MediationService__VotingPeriodStillActive();
        Panel memory panel = getPanel(dispute.disputeId);
        for (uint i; i < panel.confirmedMediators.length; ++i) {
            if (uint(getCommit(panel.confirmedMediators[i], dispute.disputeId)) == 0) {
                uint256 stakeForfeit = getMediatorStakeHeld(panel.confirmedMediators[i], dispute.disputeId);
                mediatorStakes[panel.confirmedMediators[i]][dispute.disputeId] -= stakeForfeit;
                mediatorPool.fundMediationReserve{value: stakeForfeit}();
                _removeMediator(dispute.disputeId, panel.confirmedMediators[i]);
            }
        }
        dispute.votingStart = block.timestamp;
    }

    /**
     * @notice removes mediators who fail to reveal hidden vote during REVEAL_PERIOD
     * @notice removed mediator's stake will be forfeitted and transferred to Panel Reserve
     * @notice if a majority can still be reached without the overdue mediator's vote, a decision will be rendered
     * @notice if the votes are tied, an arbiter may be assigned by Nebulai to break the tie
     * @dev if all votes are revealed, phase will have advanced and function will revert
     */
    function overdueReveal(uint256 _disputeId) external {
        Dispute memory dispute = getDispute(_disputeId);
        if (dispute.phase != Phase.Reveal) revert MediationService__OnlyDuringReveal();
        if (block.timestamp < dispute.revealStart + REVEAL_PERIOD) revert MediationService__RevealPeriodStillActive();
        (uint256 votesFor, uint256 votesAgainst) = _countVotes(dispute.disputeId);
        uint256 votesNeeded = mediatorsNeeded(dispute.disputeId);
        uint256 totalStakeForfeits; 
        Panel memory panel = getPanel(dispute.disputeId);
        for(uint i; i < panel.confirmedMediators.length; ++i) {
            if (!hasRevealedVote(panel.confirmedMediators[i], dispute.disputeId)) {
                uint256 stakeForfeit = getMediatorStakeHeld(panel.confirmedMediators[i], dispute.disputeId);
                mediatorStakes[panel.confirmedMediators[i]][dispute.disputeId] -= stakeForfeit;
                totalStakeForfeits += stakeForfeit; 
                _removeMediator(dispute.disputeId, panel.confirmedMediators[i]);
            }
        }
        if ((votesFor > votesNeeded / 2) || (votesAgainst > votesNeeded / 2)) { 
            _renderDecision(dispute.disputeId, votesFor, votesAgainst); 
        } else { 
            votesTied[dispute.disputeId] = true;
            mediatorPool.fundMediationReserve{value: totalStakeForfeits}(); 
        }  
        emit OverdueReveal(dispute.disputeId, votesTied[dispute.disputeId]);      
    }

    /**
     * @notice removes a mediator from the panel of a dispute
     * @dev called internally when a mediator fails to commit or reveal
     */
    function _removeMediator(uint256 _disputeId, address _mediator) private {
        Panel storage panel = panels[_disputeId];
        for (uint i; i < panel.confirmedMediators.length; ++i) {
            if (panel.confirmedMediators[i] == _mediator) {
                if (i == panel.confirmedMediators.length - 1) panel.confirmedMediators.pop();
                else {
                    address temp = panel.confirmedMediators[panel.confirmedMediators.length - 1];
                    panel.confirmedMediators[panel.confirmedMediators.length - 1] = panel.confirmedMediators[i];
                    panel.confirmedMediators[i] = temp;
                    panel.confirmedMediators.pop();
                }
            }
        }
        for (uint i; i < panel.drawnMediators.length; ++i) {
            if (panel.drawnMediators[i] == _mediator) {
                if (i == panel.drawnMediators.length - 1) panel.drawnMediators.pop();
                else {
                    address temp = panel.drawnMediators[panel.drawnMediators.length - 1];
                    panel.drawnMediators[panel.drawnMediators.length - 1] = panel.drawnMediators[i];
                    panel.drawnMediators[i] = temp;
                    panel.drawnMediators.pop();
                }
            }
        }
        emit MediatorRemoved(_disputeId, _mediator);
    }

    /**
     * @notice assigns an arbiter to a deadlocked case to break the tie
     * @dev can only be called by an admin address
     */
    function assignArbiter(uint256 _disputeId, address _arbiter) external {
        if (!IGovernor(GOVERNOR).isAdmin(msg.sender)) revert MediationService__OnlyAdmin();
        Dispute memory dispute = getDispute(_disputeId);
        if (!votesTied[dispute.disputeId]) revert MediationService__CaseNotDeadlocked();
        if (dispute.phase != Phase.Reveal) revert MediationService__OnlyDuringReveal();
        if (_arbiter == dispute.claimant || _arbiter == dispute.respondent) revert MediationService__InvalidArbiter();
        if (!mediatorPool.isEligible(_arbiter)) revert MediationService__InvalidArbiter();
        if (isConfirmedMediator(dispute.disputeId, _arbiter)) revert MediationService__InvalidArbiter();
        arbiter[dispute.disputeId] = _arbiter;
        emit ArbiterAssigned(dispute.disputeId, _arbiter);
    }

    /**
     * @notice assigned arbiter breaks tie on a deadlocked case
     * @dev if case is not marked deadlocked via overdueReveal(), there can be no assigned arbiter and function will revert
     */
    function breakTie(uint256 _disputeId, bool _arbiterVote) external {
        Dispute memory dispute = getDispute(_disputeId);
        if (dispute.phase != Phase.Reveal) revert MediationService__OnlyDuringReveal();
        if (msg.sender != arbiter[dispute.disputeId]) revert MediationService__InvalidArbiter();
        (uint256 votesFor, uint256 votesAgainst) = _countVotes(dispute.disputeId);
        (_arbiterVote == true) ? ++votesFor : ++votesAgainst;
        _renderDecision(dispute.disputeId, votesFor, votesAgainst);
        emit ArbiterVote(dispute.disputeId, msg.sender, _arbiterVote);
    }

    //////////////////////
    ///   GOVERNANCE   ///
    //////////////////////

    function setMediatorFlatFee(uint256 _flatFee) external onlyGovernor {
        require(_flatFee > 0);
        mediatorFlatFee = _flatFee;
    }

    //////////////////
    ///  GETTERS   ///
    //////////////////

    function getDispute(uint256 _disputeId) public view returns (Dispute memory) {
        return disputes[_disputeId];
    }

    function getFeesHeld(uint256 _disputeId) public view returns (uint256) {
        return feesHeld[_disputeId];
    }

    function getPanel(uint256 _disputeId) public view returns (Panel memory) {
        return panels[_disputeId];
    }

    function isConfirmedMediator(uint256 _disputeId, address _mediator) public view returns (bool) {
        Panel memory panel = getPanel(_disputeId);
        for(uint i; i < panel.confirmedMediators.length; ++i) {
            if(_mediator == panel.confirmedMediators[i]) return true;
        }
        return false;
    }

    function getMediatorStakeHeld(address _mediator, uint256 _disputeId) public view returns (uint256) {
        return mediatorStakes[_mediator][_disputeId];
    }

    function getCommit(address _mediator, uint256 _disputeId) public view returns (bytes32) {
        return commits[_mediator][_disputeId];
    }

    function hasRevealedVote(address _mediator, uint256 _disputeId) public view returns (bool) {
        return hasRevealed[_mediator][_disputeId];
    }

    function getVote(address _mediator, uint256 _disputeId) public view returns (bool) {
        if(!hasRevealedVote(_mediator, _disputeId)) revert MediationService__VoteHasNotBeenRevealed();
        return votes[_mediator][_disputeId];
    }

    function getMediatorFeesOwed(address _mediator) public view returns (uint256) {
        return feesToMediator[_mediator];
    }

}
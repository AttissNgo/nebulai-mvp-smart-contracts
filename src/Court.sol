// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "chainlink/VRFCoordinatorV2Interface.sol";
import "chainlink/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./Interfaces/IGovernor.sol";
import "./Interfaces/IMarketplace.sol";
import "./Interfaces/IJuryPool.sol";

contract Court is VRFConsumerBaseV2 {
    using Counters for Counters.Counter;

    address public immutable GOVERNOR;
    address public immutable MARKETPLACE;
    IJuryPool public juryPool;

    // fees
    uint256 public jurorFlatFee = 20 ether; 
    mapping(uint256 => uint256) private feesHeld; // petition ID => arbitration fees held

    // randomness 
    VRFCoordinatorV2Interface public immutable VRF_COORDINATOR;
    bytes32 public keyHash = 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f;
    uint64 public subscriptionId;
    uint16 public requestConfirmations = 3;
    uint32 public callbackGasLimit = 800000;
    uint32 public numWords = 2; 
    mapping(uint256 => uint256) public vrfRequestToPetition; //  VRF request ID => petitionID

    /**
     * @notice the stage of a petition
     * Discovery - evidence may be submitted (after paying arbitration fee)
     * JurySelection - jury is drawn randomly and drawn jurors may accept the case
     * Voting - jurors commit a hidden vote
     * Ruling - jurors reveal their votes
     * Verdict - all votes have been counted and a ruling is made
     * DefaultJudgement - one party does not pay arbitration fee, petition is ruled in favor of paying party
     * Dismissed - case is invalid and Marketplace reverts to original project conditions
     * SettledExternally - case was settled by change order in Marketplace and arbitration does not progress
     */
    enum Phase {
        Discovery,
        JurySelection, 
        Voting, 
        Ruling, 
        Verdict,
        DefaultJudgement, 
        Dismissed, 
        SettledExternally 
    }

    struct Petition {
        uint256 petitionId;
        uint256 projectId;
        uint256 adjustedProjectFee;
        uint256 providerStakeForfeit;
        address plaintiff;
        address defendant;
        uint256 arbitrationFee;
        bool feePaidPlaintiff;
        bool feePaidDefendant;
        uint256 discoveryStart;
        uint256 selectionStart;
        uint256 votingStart;
        uint256 rulingStart;
        uint256 verdictRenderedDate;
        bool isAppeal;
        bool petitionGranted;
        Phase phase;
        string[] evidence;
    }

    struct Jury {
        address[] drawnJurors;
        address[] confirmedJurors;
    }

    Counters.Counter private petitionIds;
    mapping(uint256 => Petition) private petitions; // petitionId => Petition
    mapping(uint256 => Jury) private juries; // petitionId => Jury
    mapping(address => mapping(uint256 => uint256)) private jurorStakes; // juror address => petitionId => stake
    mapping(address => mapping(uint256 => bytes32)) private commits; // juror address => petitionId => commit
    mapping(address => mapping(uint256 => bool)) private votes; // juror address => petitionId => vote
    mapping(address => mapping(uint256 => bool)) private hasRevealed; 
    mapping(address => uint256) private feesToJuror;
    mapping(uint256 => bool) public votesTied;
    mapping(uint256 => address) public arbiter;

    //////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////
    //////////////////////////////////////////
    //////////////////////////////////////////
    /// NOTE: the following time variables have been made changeable for in-house testing

    // // Time variables
    // uint24 public constant DISCOVERY_PERIOD = 7 days;
    // uint24 public constant JURY_SELECTION_PERIOD = 3 days;
    // uint24 public constant VOTING_PERIOD = 4 days;
    // uint24 public constant RULING_PERIOD = 3 days;
    
    uint24 public DISCOVERY_PERIOD = 7 days;
    uint24 public JURY_SELECTION_PERIOD = 3 days;
    uint24 public VOTING_PERIOD = 4 days;
    uint24 public RULING_PERIOD = 3 days;

    function setDiscoveryPeriod(uint24 _newPeriod) public {
        DISCOVERY_PERIOD = _newPeriod;
    }
    function setJurySelectionPeriod(uint24 _newPeriod) public {
        JURY_SELECTION_PERIOD = _newPeriod;
    }
    function setVotingPeriod(uint24 _newPeriod) public {
        VOTING_PERIOD = _newPeriod;
    }
    function setRulingPeriod(uint24 _newPeriod) public {
        RULING_PERIOD = _newPeriod;
    }

    // The testing changes end here. Be sure to make the time variables constant (un-comment above) before continuing
    //////////////////////////////////////////
    //////////////////////////////////////////
    //////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////
    //////////////////////////////////////////////////////////

    event PetitionCreated(uint256 indexed petitionId, uint256 projectId);
    event AppealCreated(uint256 indexed petitionId, uint256 indexed originalPetitionId, uint256 projectId);
    event ArbitrationFeePaid(uint256 indexed petitionId, address indexed user);
    event JurySelectionInitiated(uint256 indexed petitionId, uint256 requestId);
    event AdditionalJurorDrawingInitiated(uint256 indexed petitionId, uint256 requestId);
    event AdditionalJurorsAssigned(uint256 indexed petitionId, address[] assignedJurors);
    event JuryDrawn(uint256 indexed petitionId, bool isRedraw);
    event JurorConfirmed(uint256 indexed petitionId, address jurorAddress);
    event VotingInitiated(uint256 indexed petitionId);
    event VoteCommitted(uint256 indexed petitionId, address indexed juror, bytes32 commit);
    event RulingInitiated(uint256 indexed petitionId);
    event VoteRevealed(uint256 indexed petitionId, address indexed juror, bool vote);
    event VerdictReached(uint256 indexed petitionId, bool verdict, uint256 majorityVotes);
    event JurorFeesClaimed(address indexed juror, uint256 amount);
    event ArbitrationFeeReclaimed(uint256 indexed petitionId, address indexed claimedBy, uint256 amount);
    event CaseDismissed(uint256 indexed petitionId);
    event SettledExternally(uint256 indexed petitionId);
    event DefaultJudgementEntered(uint256 indexed petitionId, address indexed claimedBy, bool verdict);
    event JurorRemoved(uint256 indexed petitionId, address indexed juror);
    event DelinquentReveal(uint256 indexed petitionId, bool deadlocked);
    event ArbiterAssigned(uint256 indexed petitionId, address indexed arbiter);
    event ArbiterVote(uint256 indexed petitionId, address indexed arbiter, bool vote);

    error Court__TransferFailed();
    // permissions
    error Court__OnlyGovernor();
    error Court__OnlyAdmin();
    error Court__OnlyMarketplace();
    error Court__ProjectHasOpenPetition();
    error Court__OnlyLitigant();
    // petition
    error Court__ArbitrationFeeAlreadyPaid();
    error Court__ArbitrationFeeNotPaid();
    error Court__InsufficientAmount();
    error Court__EvidenceCanNoLongerBeSubmitted();
    error Court__ArbitrationFeeCannotBeReclaimed();
    error Court__OnlyPrevailingParty();
    error Court__ArbitrationFeeAlreadyReclaimed();
    error Court__PetitionDoesNotExist();
    error Court__RulingCannotBeAppealed();
    error Court__FeesNotOverdue();
    error Court__ProjectIsNotDisputed();
    error Court__OnlyDuringDiscovery();
    error Court__OnlyDuringJurySelection();
    error Court__InitialSelectionPeriodStillOpen();
    error Court__JuryAlreadyRedrawn();
    error Court__JuryNotRedrawn();
    error Court__VotingPeriodStillActive();
    error Court__NoDelinquentCommits();
    error Court__OnlyDuringRuling();
    error Court__RulingPeriodStillActive();
    error Court__CaseNotDeadlocked();
    error Court__InvalidArbiter();
    // juror actions
    error Court__JurorSeatsFilled();
    error Court__InvalidJuror();
    error Court__InsufficientJurorStake();
    error Court__AlreadyConfirmedJuror();
    error Court__NotDrawnJuror();
    error Court__JurorHasAlreadyCommmitedVote();
    error Court__InvalidCommit();
    error Court__CannotRevealBeforeAllVotesCommitted();
    error Court__AlreadyRevealed();
    error Court__RevealDoesNotMatchCommit();
    error Court__VoteHasNotBeenRevealed();
    error Court__NoJurorFeesOwed();

    modifier onlyGovernor() {
        if(msg.sender != GOVERNOR) revert Court__OnlyGovernor();
        _;
    }

    modifier onlyMarketplace() {
        if(msg.sender != MARKETPLACE) revert Court__OnlyMarketplace();
        _;
    }

    constructor(
        address _governor,
        address _juryPool,
        address _vrfCoordinatorV2, 
        uint64 _subscriptionId,
        address _calculatedMarketplace
    ) 
         VRFConsumerBaseV2(_vrfCoordinatorV2) 
    {
        GOVERNOR = _governor;
        juryPool = IJuryPool(_juryPool);
        VRF_COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinatorV2);
        subscriptionId = _subscriptionId;
        MARKETPLACE = _calculatedMarketplace;
    }

    /**
     * @dev callback from Chainlink VRF which draws jurors 
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {   
        Petition storage petition = petitions[vrfRequestToPetition[requestId]];
        bool isRedraw;   
        if(petition.selectionStart != 0) isRedraw = true;
        Jury storage jury = juries[petition.petitionId];
        uint256 numNeeded = jurorsNeeded(petition.petitionId) * 3; 
        if(isRedraw) numNeeded = jurorsNeeded(petition.petitionId) * 2;
        address[] memory jurorsDrawn = new address[](numNeeded);
        uint256 nonce = 0;
        uint256 numSelected = 0;
        uint256 poolSize = juryPool.juryPoolSize();
        while (numSelected < numNeeded) {
            address jurorA = juryPool.getJuror(uint256(keccak256(abi.encodePacked(randomWords[0], nonce))) % poolSize);
            address jurorB = juryPool.getJuror(uint256(keccak256(abi.encodePacked(randomWords[1], nonce))) % poolSize);
            address drawnJuror = _weightedDrawing(jurorA, jurorB, randomWords[0]);
            bool isInvalid = false;
            if(!juryPool.isEligible(drawnJuror)) isInvalid = true;
            if(drawnJuror == petition.plaintiff || drawnJuror == petition.defendant) isInvalid = true;
            for(uint i; i < jurorsDrawn.length; ++i) {
                if(jurorsDrawn[i] == drawnJuror) isInvalid = true; 
            }
            // if redraw check against already drawn jurors as well
            if(isRedraw) {
                for(uint i; i < jury.drawnJurors.length; ++i) {
                    if(jury.drawnJurors[i] == drawnJuror) isInvalid = true;
                }
            }
            if(!isInvalid) {
                jurorsDrawn[numSelected] = drawnJuror;
                ++numSelected;
            }
            ++nonce;
        }
        if(!isRedraw) {
            petition.selectionStart = block.timestamp;
            jury.drawnJurors = jurorsDrawn;
        } else {
            for(uint i; i < jurorsDrawn.length; ++i) {
                jury.drawnJurors.push(jurorsDrawn[i]);
            }
        }
        emit JuryDrawn(petition.petitionId, isRedraw);   
    }

    /**
     * @dev selects one of two randomly drawn jurors using weighted probability based on stake in jury pool
     */
    function _weightedDrawing(
        address _jurorA, 
        address _jurorB, 
        uint256 _randomWord
    ) 
        internal 
        view 
        returns (address) 
    {
        uint256 stakeA = juryPool.getJurorStake(_jurorA);
        uint256 stakeB = juryPool.getJurorStake(_jurorB);
        address drawnJuror = _jurorA;
        if(stakeA > stakeB) {
            if(_randomWord % 100 >= (stakeA * 100)/(stakeA + stakeB)) drawnJuror = _jurorB;
        } else if(stakeB > stakeA) {
            if(_randomWord % 100 < (stakeB * 100)/(stakeA + stakeB)) drawnJuror = _jurorB;
        }
        return drawnJuror;
    }

    ////////////////////
    ///   PETITION   ///
    ////////////////////

    /**
     * @notice creates a new petition
     * @dev can only be called from Marketplace disputeProject()
     * @return petitionId
     */
    function createPetition(
        uint256 _projectId,
        uint256 _adjustedProjectFee,
        uint256 _providerStakeForfeit,
        address _plaintiff,
        address _defendant
    )
        external
        onlyMarketplace
        returns (uint256)
    {
        if(IMarketplace(msg.sender).getArbitrationPetitionId(_projectId) != 0) revert Court__ProjectHasOpenPetition();
        petitionIds.increment(); // can never be 0
        uint256 petitionId = petitionIds.current();
        Petition memory petition;
        petition.petitionId = petitionId;
        petition.projectId = _projectId;
        petition.adjustedProjectFee = _adjustedProjectFee;
        petition.providerStakeForfeit = _providerStakeForfeit;
        petition.plaintiff = _plaintiff;
        petition.defendant = _defendant;
        petition.arbitrationFee = calculateArbitrationFee(false);
        petition.discoveryStart = block.timestamp;
        petitions[petitionId] = petition;
        emit PetitionCreated(petitionId, _projectId);
        return petitionId;
    }

    /**
     *  @notice creates new 'appeal' petition with project/dispute information from original petition 
     *  arbitration fee is higher to compensate larger jury
     *  @dev can only be called from Marketplace appealRuling()
     *  @return ID of new 'appeal' petition 
     */
    function appeal(uint256 _projectId) external onlyMarketplace returns (uint256) {
        uint256 originalPetitionId = IMarketplace(msg.sender).getArbitrationPetitionId(_projectId); 
        if(originalPetitionId == 0) revert Court__PetitionDoesNotExist();
        Petition memory originalPetition = getPetition(originalPetitionId);
        if(originalPetition.isAppeal) revert Court__RulingCannotBeAppealed();
        petitionIds.increment(); 
        uint256 petitionId = petitionIds.current();
        Petition memory petition;
        petition.petitionId = petitionId;
        petition.projectId = _projectId;
        petition.adjustedProjectFee = originalPetition.adjustedProjectFee;
        petition.providerStakeForfeit = originalPetition.providerStakeForfeit;
        petition.plaintiff = originalPetition.plaintiff;
        petition.defendant = originalPetition.defendant;
        petition.arbitrationFee = calculateArbitrationFee(true);
        petition.isAppeal = true;
        petition.discoveryStart = block.timestamp;
        petitions[petitionId] = petition;
        emit AppealCreated(petitionId, originalPetitionId, _projectId);
        return petitionId;
    }

    function calculateArbitrationFee(bool isAppeal) public view returns (uint256) {
        if(!isAppeal) return 3 * jurorFlatFee;
        else return 5 * jurorFlatFee;
    }

    /**
     * @notice pay arbitration fee and submit evidence
     * @dev when both litigants have paid, random words will be requested from Chainlink and jury will be drawn
     */
    function payArbitrationFee(uint256 _petitionId, string[] calldata _evidenceURIs) external payable {
        Petition storage petition = petitions[_petitionId];
        if(msg.sender != petition.plaintiff && msg.sender != petition.defendant) revert Court__OnlyLitigant();
        if(
            (msg.sender == petition.plaintiff && petition.feePaidPlaintiff) || 
            (msg.sender == petition.defendant && petition.feePaidDefendant)
        ) revert Court__ArbitrationFeeAlreadyPaid();
        if(msg.value < petition.arbitrationFee) revert Court__InsufficientAmount();
        (msg.sender == petition.plaintiff) ? petition.feePaidPlaintiff = true : petition.feePaidDefendant = true;
        feesHeld[_petitionId] += msg.value;
        for(uint i = 0; i < _evidenceURIs.length; ++i) {
            petition.evidence.push(_evidenceURIs[i]);
        }
        emit ArbitrationFeePaid(_petitionId, msg.sender);
        if(petition.feePaidPlaintiff && petition.feePaidDefendant) {
            uint256 requestId = _selectJury(_petitionId);
            petition.phase = Phase.JurySelection;
            emit JurySelectionInitiated(_petitionId, requestId);
        }
    }

    /**
     * @notice allows litigants who have paid arbitration fee to submit additional evidence
     * evidence can only be submitted during Discovery and Jury Selection
     */
    function submitAdditionalEvidence(uint256 _petitionId, string[] calldata _evidenceURIs) external {
        Petition storage petition = petitions[_petitionId];
        if(msg.sender != petition.plaintiff && msg.sender != petition.defendant) revert Court__OnlyLitigant();
        if(petition.phase != Phase.Discovery && petition.phase != Phase.JurySelection) {
            revert Court__EvidenceCanNoLongerBeSubmitted();
        }
        if(
            (msg.sender == petition.plaintiff && !petition.feePaidPlaintiff) ||
            (msg.sender == petition.defendant && !petition.feePaidDefendant)
        ) revert Court__ArbitrationFeeNotPaid();
        for(uint i = 0; i < _evidenceURIs.length; ++i) {
            petition.evidence.push(_evidenceURIs[i]);
        }
    }

    /**
     * @notice prevailing party may reclaim arbitration fee
     */
    function reclaimArbitrationFee(uint256 _petitionId) external {
        Petition memory petition = getPetition(_petitionId);
        if(msg.sender != petition.plaintiff && msg.sender != petition.defendant) revert Court__OnlyLitigant();
        if(petition.phase == Phase.Verdict) {
            if(petition.petitionGranted && msg.sender != petition.plaintiff) revert Court__OnlyPrevailingParty();
            else if(!petition.petitionGranted && msg.sender != petition.defendant) revert Court__OnlyPrevailingParty();
        } else if (petition.phase == Phase.SettledExternally) {
            if(!petition.feePaidPlaintiff && msg.sender == petition.plaintiff) revert Court__ArbitrationFeeNotPaid();
            else if(!petition.feePaidDefendant && msg.sender == petition.defendant) revert Court__ArbitrationFeeNotPaid();
        } else revert Court__ArbitrationFeeCannotBeReclaimed();
        if(feesHeld[_petitionId] != petition.arbitrationFee) revert Court__ArbitrationFeeAlreadyReclaimed();
        uint256 reclaimAmount = feesHeld[_petitionId];
        feesHeld[_petitionId] -= reclaimAmount;
        (bool success, ) = msg.sender.call{value: reclaimAmount}("");
        if(!success) revert Court__TransferFailed();
        emit ArbitrationFeeReclaimed(_petitionId, msg.sender, reclaimAmount);
    }

    /**
     * @notice a dismissed case will return to original project fee amount in Marketplace
     */
    function dismissUnpaidCase(uint256 _petitionId) public {
        Petition storage petition = petitions[_petitionId];
        if(petition.petitionId == 0) revert Court__PetitionDoesNotExist();
        if(block.timestamp < petition.discoveryStart + DISCOVERY_PERIOD) revert Court__FeesNotOverdue();
        if(petition.feePaidPlaintiff || petition.feePaidDefendant) revert Court__ArbitrationFeeAlreadyPaid();
        petition.phase = Phase.Dismissed;
        emit CaseDismissed(_petitionId);
    } 

    /**
     * @dev called automatically by Marketplace when a change order is approved on a disputed Project
     */
    function settledExternally(uint256 _petitionId) external onlyMarketplace {
        Petition storage petition = petitions[_petitionId];
        petition.phase = Phase.SettledExternally;
        emit SettledExternally(petition.petitionId);
    }

    /**
     * @notice rules in favor of paying litigant when one litigant has not paid within DISCOVERY_PERIOD
     * @dev if both litigants have paid, phase will have been advanced to JurySelection and function will revert
     */
    function requestDefaultJudgement(uint256 _petitionId) external {
        Petition storage petition = petitions[_petitionId];
        if(msg.sender != petition.plaintiff && msg.sender != petition.defendant) revert Court__OnlyLitigant();
        if(petition.phase != Phase.Discovery) revert Court__OnlyDuringDiscovery();
        if(msg.sender == petition.plaintiff) {
            if(!petition.feePaidPlaintiff) revert Court__ArbitrationFeeNotPaid();
        } else {
            if(!petition.feePaidDefendant) revert Court__ArbitrationFeeNotPaid();
        }
        if(block.timestamp < petition.discoveryStart + DISCOVERY_PERIOD) revert Court__FeesNotOverdue();
        (msg.sender == petition.plaintiff) ? petition.petitionGranted = true : petition.petitionGranted = false;
        petition.phase = Phase.DefaultJudgement;
        uint256 reclaimAmount = feesHeld[_petitionId];
        feesHeld[_petitionId] -= reclaimAmount;
        (bool success, ) = msg.sender.call{value: reclaimAmount}("");
        if(!success) revert Court__TransferFailed();
        emit DefaultJudgementEntered(_petitionId, msg.sender, petition.petitionGranted);
    }

    ////////////////
    ///   JURY   ///
    ////////////////

    /**
     * @dev creates a request for random words from Chainlink VRF - called internally when jury selection is needed
     * @return requestID from Chainlink VRF
     */
    function _selectJury(uint256 _petitionId) private returns (uint256) {
        uint256 requestId = VRF_COORDINATOR.requestRandomWords(
            keyHash, 
            subscriptionId, 
            requestConfirmations, 
            callbackGasLimit, 
            numWords
        );
        vrfRequestToPetition[requestId] = _petitionId;
        return requestId;
    }

    function jurorsNeeded(uint256 petitionId) public view returns (uint256) {
        if(petitions[petitionId].isAppeal) return 5;
        else return 3;
    } 

    /**
     * @dev called internally when enough jurors have accepted a case
     */
    function _juryAssembled(uint256 _petitionId) private {
        Petition storage petition = petitions[_petitionId];
        petition.phase = Phase.Voting;
        petition.votingStart = block.timestamp;
        emit VotingInitiated(_petitionId);
    }

    /**
     * @dev called internally when all jurors have committed their hidden votes
     */
    function _allVotesCommitted(uint256 _petitionId) private {
        Petition storage petition = petitions[_petitionId];
        petition.phase = Phase.Ruling;
        petition.rulingStart = block.timestamp;
        emit RulingInitiated(_petitionId);
    }

    /**
     * @dev called internally when a juror votes or when delinquentReveal() is called
     * @return votesFor number of votes in favor of petition
     * @return votesAgainst number of votes against petition
     */
    function _countVotes(uint256 _petitionId) private view returns (uint256, uint256) {
        Jury memory jury = getJury(_petitionId);
        uint256 votesFor;
        uint256 votesAgainst;
        for(uint i; i < jury.confirmedJurors.length; ++i) {
            if(hasRevealedVote(jury.confirmedJurors[i], _petitionId)) {
                (votes[jury.confirmedJurors[i]][_petitionId]) ? ++votesFor : ++votesAgainst;
            }
        }
        return(votesFor, votesAgainst);
    }

    /**
     * @notice jurors who voted in majority may claim juror fee, jurors in minority will not receive payment
     * @dev called internally when there are enough votes to render a verdict
     * @dev in the case of remaining arbitration fees, the remaining currency will be transferred to the Jury Reserve
     */
    function _renderVerdict(
        uint256 _petitionId, 
        uint256 _votesFor, 
        uint256 _votesAgainst
    ) 
        private 
    {
        Petition storage petition = petitions[_petitionId];
        petition.phase = Phase.Verdict;
        petition.petitionGranted = (_votesFor > _votesAgainst);
        petition.verdictRenderedDate = block.timestamp;
        uint256 jurorFee = petition.arbitrationFee / jurorsNeeded(_petitionId);
        uint256 remainingFees = petition.arbitrationFee;
        Jury memory jury = getJury(_petitionId);
        for(uint i; i < jury.confirmedJurors.length; ++i) {
            if(hasRevealedVote(jury.confirmedJurors[i], _petitionId)) {
                if(petition.petitionGranted && votes[jury.confirmedJurors[i]][_petitionId] == true) {
                    feesToJuror[jury.confirmedJurors[i]] += jurorFee;
                    remainingFees -= jurorFee;
                } else if (!petition.petitionGranted && votes[jury.confirmedJurors[i]][_petitionId] == false) {
                    feesToJuror[jury.confirmedJurors[i]] += jurorFee;
                    remainingFees -= jurorFee;
                }
            }
        }
        feesHeld[_petitionId] -= petition.arbitrationFee;
        if(remainingFees > 0) {
            juryPool.fundJuryReserve{value: remainingFees}();
        }
        uint256 majorityVotes;
        (petition.petitionGranted) ? majorityVotes = _votesFor : majorityVotes = _votesAgainst;
        emit VerdictReached(_petitionId, petition.petitionGranted, majorityVotes);
    }

    /////////////////////////
    ///   JUROR ACTIONS   ///
    /////////////////////////

    /**
     * @notice drawn juror may accept a case by staking an amount equal to the jurorFlatFee
     * @dev calls _juryAssembled() when enough jurors have accepted case
     */
    function acceptCase(uint256 _petitionId) external payable {
        Jury storage jury = juries[_petitionId];
        if(jury.confirmedJurors.length >= jurorsNeeded(_petitionId)) revert Court__JurorSeatsFilled();
        for(uint i; i < jury.confirmedJurors.length; ++i) {
            if(msg.sender == jury.confirmedJurors[i]) revert Court__AlreadyConfirmedJuror();
        }
        if(msg.value < jurorFlatFee) revert Court__InsufficientJurorStake();
        if(juryPool.getJurorStatus(msg.sender) != IJuryPool.JurorStatus.Active) revert Court__InvalidJuror();
        bool isDrawnJuror;
        for(uint i; i < jury.drawnJurors.length; ++i) {
            if(msg.sender == jury.drawnJurors[i]) isDrawnJuror = true;
        }
        if(!isDrawnJuror) revert Court__NotDrawnJuror();
        jurorStakes[msg.sender][_petitionId] = msg.value;
        jury.confirmedJurors.push(msg.sender);
        emit JurorConfirmed(_petitionId, msg.sender);
        if(jury.confirmedJurors.length == jurorsNeeded(_petitionId)) {
            _juryAssembled(_petitionId);
        }
    }

    /**
     * @notice juror commits their hidden vote
     * @dev calls _allVotesCommitted() when if call is the last commit needed
     * @param _commit keccak256 hash of packed abi encoding of vote (bool) and juror's salt
     */
    function commitVote(uint256 _petitionId, bytes32 _commit) external {
        if(uint(getCommit(msg.sender, _petitionId)) != 0) revert Court__JurorHasAlreadyCommmitedVote();
        if(uint(_commit) == 0) revert Court__InvalidCommit();
        Jury memory jury = getJury(_petitionId);
        bool isJuror;
        uint256 voteCount;
        for(uint i; i < jury.confirmedJurors.length; ++i) {
            if(msg.sender == jury.confirmedJurors[i]) isJuror = true;
            if(uint(getCommit(jury.confirmedJurors[i], _petitionId)) != 0) ++voteCount;
        }
        if(!isJuror) revert Court__InvalidJuror();
        commits[msg.sender][_petitionId] = _commit;
        emit VoteCommitted(_petitionId, msg.sender, _commit);
        if(voteCount + 1 >= jurorsNeeded(_petitionId)) {
            _allVotesCommitted(_petitionId);
        }
    }

    /**
     * @notice juror reveals hidden vote and juror stake is returned
     * @dev calls _renderVerdict() when all jurors have revealed
     * @param _vote bool originally encoded in commit
     * @param _salt string originally encoded in commit
     */
    function revealVote(uint256 _petitionId, bool _vote, string calldata _salt) external {
        if(!isConfirmedJuror(_petitionId, msg.sender)) revert Court__InvalidJuror();
        if(getPetition(_petitionId).phase != Phase.Ruling) revert Court__CannotRevealBeforeAllVotesCommitted();
        if(hasRevealedVote(msg.sender, _petitionId)) revert Court__AlreadyRevealed();
        bytes32 reveal = keccak256(abi.encodePacked(_vote, _salt));
        if(reveal != getCommit(msg.sender, _petitionId)) revert Court__RevealDoesNotMatchCommit();
        votes[msg.sender][_petitionId] = _vote;
        hasRevealed[msg.sender][_petitionId] = true;
        uint256 stakeRefund = jurorStakes[msg.sender][_petitionId];
        jurorStakes[msg.sender][_petitionId] -= stakeRefund;
        (bool success,) = msg.sender.call{value: stakeRefund}("");
        if(!success) revert Court__TransferFailed();
        emit VoteRevealed(_petitionId, msg.sender, _vote);
        (uint256 votesFor, uint256 votesAgainst) = _countVotes(_petitionId);
        if(votesFor + votesAgainst == jurorsNeeded(_petitionId)) {
            _renderVerdict(_petitionId, votesFor, votesAgainst);
        }
    }

    /**
     * @notice withdraw fees earned for serving on jury
     */
    function claimJurorFees() external {
        uint256 feesOwed = feesToJuror[msg.sender];
        if(feesOwed < 1) revert Court__NoJurorFeesOwed();
        feesToJuror[msg.sender] = 0;
        (bool success,) = msg.sender.call{value: feesOwed}("");
        if(!success) revert Court__TransferFailed();
        emit JurorFeesClaimed(msg.sender, feesOwed);
    }

    ///////////////////////////
    ///   JURY EXCEPTIONS   ///
    ///////////////////////////

    /**
     * @notice draws additional jurors if not enough jurors have accepted case after JURY_SELECTION_PERIOD elapses
     * @dev can only be called once per case
     */
    function drawAdditionalJurors(uint256 _petitionId) external {
        Petition memory petition = getPetition(_petitionId);
        if(petition.phase != Phase.JurySelection) revert Court__OnlyDuringJurySelection();
        if(block.timestamp < petition.selectionStart + JURY_SELECTION_PERIOD) {
            revert Court__InitialSelectionPeriodStillOpen();
        } 
        Jury memory jury = getJury(_petitionId);
        if(jury.drawnJurors.length > jurorsNeeded(_petitionId) * 3) revert Court__JuryAlreadyRedrawn();
        uint256 requestId = _selectJury(_petitionId);
        emit AdditionalJurorDrawingInitiated(petition.petitionId, requestId);
    }

    function assignAdditionalJurors(uint256 _petitionId, address[] calldata _additionalJurors) external {
        if(!IGovernor(GOVERNOR).isAdmin(msg.sender)) revert Court__OnlyAdmin();
        Petition memory petition = getPetition(_petitionId);
        if(petition.phase != Phase.JurySelection) revert Court__OnlyDuringJurySelection();
        if(block.timestamp < petition.selectionStart + JURY_SELECTION_PERIOD) {
            revert Court__InitialSelectionPeriodStillOpen();
        } 
        Jury storage jury = juries[_petitionId];
        if(!(jury.drawnJurors.length > jurorsNeeded(_petitionId) * 3)) revert Court__JuryNotRedrawn();
        // must be valid jurors
        for(uint i; i < _additionalJurors.length; ++i) {
            if(isConfirmedJuror(petition.petitionId, _additionalJurors[i])) revert Court__InvalidJuror();
            if(!juryPool.isEligible(_additionalJurors[i])) revert Court__InvalidJuror();
            if(_additionalJurors[i] == petition.plaintiff || _additionalJurors[i] == petition.defendant) {
                revert Court__InvalidJuror();
            }
            jury.drawnJurors.push(_additionalJurors[i]);
        }
        emit AdditionalJurorsAssigned(petition.petitionId, _additionalJurors);
    }

    /**
     * @notice removes juror who does not commit vote within voting period
     * transfers stake of delinquent juror to Jury Reserve
     * @dev restarts voting period so remaining drawn jurors may accept case and vote
     */
    function delinquentCommit(uint256 _petitionId) external {
        Petition storage petition = petitions[_petitionId];
        if(petition.phase != Phase.Voting) revert Court__NoDelinquentCommits();
        if(block.timestamp < petition.votingStart + VOTING_PERIOD) revert Court__VotingPeriodStillActive();
        Jury memory jury = getJury(petition.petitionId);
        for(uint i; i < jury.confirmedJurors.length; ++i) {
            if(uint(getCommit(jury.confirmedJurors[i], petition.petitionId)) == 0) {
                uint256 stakeForfeit = getJurorStakeHeld(jury.confirmedJurors[i], petition.petitionId);
                jurorStakes[jury.confirmedJurors[i]][petition.petitionId] -= stakeForfeit;
                juryPool.fundJuryReserve{value: stakeForfeit}();
                _removeJuror(petition.petitionId, jury.confirmedJurors[i]);
            }
        }
        petition.votingStart = block.timestamp;
    }

    /**
     * @notice called if a juror fails to reveal hidden vote
     * juror's stake will be forfeitted and transferred to Jury Reserve
     * if a majority can still be reached without the delinquent juror's vote, a verdict will be rendered
     * if the votes are tied, an arbiter may be assigned by Nebulai to break the tie
     * @dev if all votes are revealed, phase will have advanced and function will revert
     */
    function delinquentReveal(uint256 _petitionId) external {
        Petition memory petition = getPetition(_petitionId);
        if(petition.phase != Phase.Ruling) revert Court__OnlyDuringRuling();
        if(block.timestamp < petition.rulingStart + RULING_PERIOD) revert Court__RulingPeriodStillActive();
        (uint256 votesFor, uint256 votesAgainst) = _countVotes(petition.petitionId);
        uint256 votesNeeded = jurorsNeeded(petition.petitionId);
        uint256 totalStakeForfeits; 
        Jury memory jury = getJury(petition.petitionId);
        for(uint i; i < jury.confirmedJurors.length; ++i) {
            if(!hasRevealedVote(jury.confirmedJurors[i], petition.petitionId)) {
                uint256 stakeForfeit = getJurorStakeHeld(jury.confirmedJurors[i], petition.petitionId);
                jurorStakes[jury.confirmedJurors[i]][petition.petitionId] -= stakeForfeit;
                totalStakeForfeits += stakeForfeit; 
                _removeJuror(petition.petitionId, jury.confirmedJurors[i]);
            }
        }
        if((votesFor > votesNeeded / 2) || (votesAgainst > votesNeeded / 2)) { 
            _renderVerdict(petition.petitionId, votesFor, votesAgainst); 
        } else { 
            votesTied[petition.petitionId] = true;
            juryPool.fundJuryReserve{value: totalStakeForfeits}(); 
        }  
        emit DelinquentReveal(petition.petitionId, votesTied[petition.petitionId]);      
    }

    /**
     * @dev removes a juror from the jury of a petition. Called internally when a juror fails to commit or reveal.
     */
    function _removeJuror(uint256 _petitionId, address _juror) private {
        Jury storage jury = juries[_petitionId];
        for(uint i; i < jury.confirmedJurors.length; ++i) {
            if(jury.confirmedJurors[i] == _juror) {
                if(i == jury.confirmedJurors.length - 1) jury.confirmedJurors.pop();
                else {
                    address temp = jury.confirmedJurors[jury.confirmedJurors.length - 1];
                    jury.confirmedJurors[jury.confirmedJurors.length - 1] = jury.confirmedJurors[i];
                    jury.confirmedJurors[i] = temp;
                    jury.confirmedJurors.pop();
                }
            }
        }
        for(uint i; i < jury.drawnJurors.length; ++i) {
            if(jury.drawnJurors[i] == _juror) {
                if(i == jury.drawnJurors.length - 1) jury.drawnJurors.pop();
                else {
                    address temp = jury.drawnJurors[jury.drawnJurors.length - 1];
                    jury.drawnJurors[jury.drawnJurors.length - 1] = jury.drawnJurors[i];
                    jury.drawnJurors[i] = temp;
                    jury.drawnJurors.pop();
                }
            }
        }
        emit JurorRemoved(_petitionId, _juror);
    }

    /**
     * @notice assigns an arbiter to a deadlocked case to break the tie
     * @dev can only be called by an admin address
     */
    function assignArbiter(uint256 _petitionId, address _arbiter) external {
        if(!IGovernor(GOVERNOR).isAdmin(msg.sender)) revert Court__OnlyAdmin();
        Petition memory petition = getPetition(_petitionId);
        if(!votesTied[petition.petitionId]) revert Court__CaseNotDeadlocked();
        if(petition.phase != Phase.Ruling) revert Court__OnlyDuringRuling();
        if(_arbiter == petition.plaintiff || _arbiter == petition.defendant) revert Court__InvalidArbiter();
        if(!juryPool.isEligible(_arbiter)) revert Court__InvalidArbiter();
        if(isConfirmedJuror(petition.petitionId, _arbiter)) revert Court__InvalidArbiter();
        arbiter[petition.petitionId] = _arbiter;
        emit ArbiterAssigned(petition.petitionId, _arbiter);
    }

    /**
     * @notice assigned arbiter breaks tie on a deadlocked case
     * @dev if case is not marked deadlocked via delinquentReveal(), there can be no assigned arbiter and function will revert
     */
    function breakTie(uint256 _petitionId, bool _arbiterVote) external {
        Petition memory petition = getPetition(_petitionId);
        if(petition.phase != Phase.Ruling) revert Court__OnlyDuringRuling();
        if(msg.sender != arbiter[petition.petitionId]) revert Court__InvalidArbiter();
        (uint256 votesFor, uint256 votesAgainst) = _countVotes(petition.petitionId);
        (_arbiterVote == true) ? ++votesFor : ++votesAgainst;
        _renderVerdict(petition.petitionId, votesFor, votesAgainst);
        emit ArbiterVote(petition.petitionId, msg.sender, _arbiterVote);
    }

    //////////////////////
    ///   GOVERNANCE   ///
    //////////////////////

    function setJurorFlatFee(uint256 _flatFee) external onlyGovernor {
        jurorFlatFee = _flatFee;
    }

    //////////////////
    ///  GETTERS   ///
    //////////////////

    function getPetition(uint256 _petitionId) public view returns (Petition memory) {
        return petitions[_petitionId];
    }

    function getFeesHeld(uint256 _petitionId) public view returns (uint256) {
        return feesHeld[_petitionId];
    }

    function getJury(uint256 _petitionId) public view returns (Jury memory) {
        return juries[_petitionId];
    }

    function isConfirmedJuror(uint256 _petitionId, address _juror) public view returns (bool) {
        Jury memory jury = getJury(_petitionId);
        bool isJuror;
        for(uint i; i < jury.confirmedJurors.length; ++i) {
            if(_juror == jury.confirmedJurors[i]) isJuror = true;
        }
        return isJuror;
    }

    function getJurorStakeHeld(address _juror, uint256 _petitionId) public view returns (uint256) {
        return jurorStakes[_juror][_petitionId];
    }

    function getCommit(address _juror, uint256 _petitionId) public view returns (bytes32) {
        return commits[_juror][_petitionId];
    }

    function hasRevealedVote(address _juror, uint256 _petitionId) public view returns (bool) {
        return hasRevealed[_juror][_petitionId];
    }

    function getVote(address _juror, uint256 _petitionId) public view returns (bool) {
        if(!hasRevealedVote(_juror, _petitionId)) revert Court__VoteHasNotBeenRevealed();
        return votes[_juror][_petitionId];
    }

    function getJurorFeesOwed(address _juror) public view returns (uint256) {
        return feesToJuror[_juror];
    }

}
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "chainlink/VRFCoordinatorV2Interface.sol";
import "chainlink/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./Interfaces/IMarketplace.sol";
import "./Interfaces/IJuryPool.sol";

contract Court is VRFConsumerBaseV2 {
    using Counters for Counters.Counter;

    address public immutable GOVERNOR;
    IJuryPool public juryPool;

    mapping(address => bool) private registeredMarketplaces;

    // fees
    uint256 public jurorFlatFee = 20 ether;
    mapping(uint256 => uint256) private feesHeld; // petition ID => arbitration fees held
    mapping(address => uint256) private feesToJuror;

    // randomness 
    VRFCoordinatorV2Interface public immutable VRF_COORDINATOR;
    bytes32 public keyHash = 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f;
    uint64 public subscriptionId;
    uint16 public requestConfirmations = 3;
    uint32 public callbackGasLimit = 800000;
    uint32 public numWords = 2; 
    mapping(uint256 => uint256) public vrfRequestToPetition; //  VRF request ID => petitionID

    enum Phase {
        Discovery, // fees + evidence
        JurySelection, // drawing jurors
        Voting, // jurors must commit votes
        Ruling, // jurors must reveal votes
        Verdict,
        DefaultJudgement, // one party doesn't pay - arbitration fee refunded - jury not drawn 
        Dismissed, // case is invalid, Marketplace reverts to original project conditions
        SettledExternally // case was settled by change order in marketplace (arbitration does not progress)
    }

    struct Petition {
        uint256 petitionId;
        address marketplace;
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
    Counters.Counter private petitionIds;
    mapping(uint256 => Petition) private petitions; // by petitionId

    // JURY
    struct Jury {
        address[] drawnJurors;
        address[] confirmedJurors;
    }
    mapping(uint256 => Jury) private juries; // by petitionId
    mapping(address => mapping(uint256 => uint256)) private jurorStakes; // juror address => petitionId => stake
    mapping(address => mapping(uint256 => bytes32)) private commits; // juror address => petitionId => commit
    mapping(address => mapping(uint256 => bool)) private votes;
    mapping(address => mapping(uint256 => bool)) private hasRevealed;
    // mapping(uint256 => bool) public hungJury; // by petitionId 
    mapping(address => uint256) private jurorFeeReimbursementOwed; // juror address => amount

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

    event MarketplaceRegistered(address marketplace);
    event PetitionCreated(uint256 indexed petitionId, address marketplace, uint256 projectId);
    event AppealCreated(uint256 indexed petitionId, uint256 indexed originalPetitionId, address marketplace, uint256 projectId);
    event ArbitrationFeePaid(uint256 indexed petitionId, address indexed user);
    event JurySelectionInitiated(uint256 indexed petitionId, uint256 requestId);
    event AdditionalJurorDrawingInitiated(uint256 indexed petitionId, uint256 requestId);
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
    event JurorRemoved(uint256 indexed petitionId, address indexed juror, uint256 stakeForfeit);
    event JurorFeeReimbursementOwed(uint256 indexed petitionId, address indexed juror, uint256 jurorFee);
    event DelinquentReveal(uint256 indexed petitionId, bool deadlocked);
    event CaseRestarted(uint256 indexed petitionId, uint256 requestId);

    // permissions
    error Court__OnlyGovernor();
    error Court__OnlyMarketplace();
    error Court__ProjectHasOpenPetition();
    error Court__OnlyLitigant();
    error Court__InvalidMarketplace();
    // config 
    error Court__MarketplaceAlreadyRegistered();
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
    error Court__VotingPeriodStillActive();
    error Court__NoDelinquentCommit();
    error Court__OnlyDuringRuling();
    error Court__RulingPeriodStillActive();
    error Court__NoDelinquentReveals();
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

    error Court__TransferFailed();

    modifier onlyGovernor() {
        if(msg.sender != GOVERNOR) revert Court__OnlyGovernor();
        _;
    }

    modifier onlyMarketplace() {
        if(!isRegisteredMarketplace(msg.sender)) revert Court__OnlyMarketplace();
        _;
    }

    constructor(
        address _governor,
        address _juryPool,
        address _vrfCoordinatorV2, 
        uint64 _subscriptionId,
        //////////////////////////////////////////////////////////////////////
        //////////////////////////////////////////////////////////////////////
        //////////////////////////////////////////////////////////////////////
        address _calculatedMarketplace
        //////////////////////////////////////////////////////////////////////
        //////////////////////////////////////////////////////////////////////
        //////////////////////////////////////////////////////////////////////
    ) 
         VRFConsumerBaseV2(_vrfCoordinatorV2) 
    {
        GOVERNOR = _governor;
        juryPool = IJuryPool(_juryPool);
        VRF_COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinatorV2);
        subscriptionId = _subscriptionId;
        //////////////////////////////////////////////////////////////////////
        //////////////////////////////////////////////////////////////////////
        //////////////////////////////////////////////////////////////////////
        _registerMarketplace(_calculatedMarketplace);
        //////////////////////////////////////////////////////////////////////
        //////////////////////////////////////////////////////////////////////
        //////////////////////////////////////////////////////////////////////
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {   
        Petition storage petition = petitions[vrfRequestToPetition[requestId]];
        bool isRedraw;   
        if(petition.selectionStart != 0) isRedraw = true;
        Jury storage jury = juries[petition.petitionId];
        uint256 numNeeded = jurorsNeeded(petition.petitionId) * 3; // will draw 3x jurors needed
        if(isRedraw) numNeeded = jurorsNeeded(petition.petitionId) * 2;
        address[] memory jurorsDrawn = new address[](numNeeded);
        uint256 nonce = 0;
        uint256 numSelected = 0;
        uint256 poolSize = juryPool.juryPoolSize();
        while (numSelected < numNeeded) {
            IJuryPool.Juror memory jurorA = juryPool.getJuror(
                uint256(keccak256(abi.encodePacked(randomWords[0], nonce))) % poolSize
            );
            IJuryPool.Juror memory jurorB = juryPool.getJuror(
                uint256(keccak256(abi.encodePacked(randomWords[1], nonce))) % poolSize
            );
            IJuryPool.Juror memory drawnJuror = _weightedDrawing(jurorA, jurorB, randomWords[0]);

            bool isInvalid = false;
            if(
                drawnJuror.jurorStatus != IJuryPool.JurorStatus.Active ||
                drawnJuror.jurorAddress == petition.plaintiff ||
                drawnJuror.jurorAddress == petition.defendant
            ) isInvalid = true;
            for(uint i; i < jurorsDrawn.length; ++i) {
                if(jurorsDrawn[i] == drawnJuror.jurorAddress) isInvalid = true; 
            }
            // if redraw check against already drawn jurors as well
            if(isRedraw) {
                for(uint i; i < jury.drawnJurors.length; ++i) {
                    if(jury.drawnJurors[i] == drawnJuror.jurorAddress) isInvalid = true;
                }
            }
            if(!isInvalid) {
                jurorsDrawn[numSelected] = drawnJuror.jurorAddress;
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

            // // this works with scripts
        // Petition storage petition = petitions[vrfRequestToPetition[requestId]];
        // petition.selectionStart = block.timestamp;
        // Jury storage jury = juries[petition.petitionId];
        // jury.drawnJurors = [
        //     0x14dC79964da2C08b23698B3D3cc7Ca32193d9955,
        //     0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f,
        //     0xa0Ee7A142d267C1f36714E4a8F75612F20a79720
        // ];

            // // This also works
        // Petition storage petition = petitions[vrfRequestToPetition[requestId]];
        // bool isRedraw;   
        // if(petition.selectionStart != 0) isRedraw = true;
        // Jury storage jury = juries[petition.petitionId];
        // // uint256 numNeeded = jurorsNeeded(petition.petitionId) * 3; // will draw 3x jurors needed
        // uint256 numNeeded = jurorsNeeded(petition.petitionId); // will draw 3x jurors needed
        // // if(isRedraw) numNeeded = jurorsNeeded(petition.petitionId) * 2;
        // if(isRedraw) numNeeded = jurorsNeeded(petition.petitionId);
        // address[] memory jurorsDrawn = new address[](numNeeded);
        // uint256 nonce = 0;
        // uint256 numSelected = 0;
        // uint256 poolSize = juryPool.juryPoolSize();
        // while (numSelected < numNeeded) {
        //     IJuryPool.Juror memory drawnJuror = juryPool.getJuror(
        //         uint256(keccak256(abi.encodePacked(randomWords[0], nonce))) % poolSize
        //     );
        //     bool isInvalid = false;
        //     if(
        //         drawnJuror.jurorStatus != IJuryPool.JurorStatus.Active ||
        //         drawnJuror.jurorAddress == petition.plaintiff ||
        //         drawnJuror.jurorAddress == petition.defendant
        //     ) isInvalid = true;
        //     for(uint i; i < jurorsDrawn.length; ++i) {
        //         if(jurorsDrawn[i] == drawnJuror.jurorAddress) isInvalid = true; 
        //     }
        //     // if redraw check against already drawn jurors as well
        //     if(isRedraw) {
        //         for(uint i; i < jury.drawnJurors.length; ++i) {
        //             if(jury.drawnJurors[i] == drawnJuror.jurorAddress) isInvalid = true;
        //         }
        //     }
        //     if(!isInvalid) {
        //         jurorsDrawn[numSelected] = drawnJuror.jurorAddress;
        //         ++numSelected;
        //     }
        //     ++nonce;
        // }
        // if(!isRedraw) {
        //     petition.selectionStart = block.timestamp;
        //     jury.drawnJurors = jurorsDrawn;
        // } else {
        //     for(uint i; i < jurorsDrawn.length; ++i) {
        //         jury.drawnJurors.push(jurorsDrawn[i]);
        //     }
        // }
        // emit JuryDrawn(petition.petitionId, isRedraw);   
    }

    function _weightedDrawing(
        IJuryPool.Juror memory _jurorA, 
        IJuryPool.Juror memory _jurorB, 
        uint256 _randomWord
    ) 
        internal 
        view 
        returns (IJuryPool.Juror memory) 
    {
        uint256 stakeA = juryPool.getJurorStake(_jurorA.jurorAddress);
        uint256 stakeB = juryPool.getJurorStake(_jurorB.jurorAddress);
        IJuryPool.Juror memory drawnJuror = _jurorA;
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
        petition.marketplace = msg.sender;
        petition.projectId = _projectId;
        petition.adjustedProjectFee = _adjustedProjectFee;
        petition.providerStakeForfeit = _providerStakeForfeit;
        petition.plaintiff = _plaintiff;
        petition.defendant = _defendant;
        petition.arbitrationFee = calculateArbitrationFee(false);
        petition.discoveryStart = block.timestamp;
        petitions[petitionId] = petition;
        emit PetitionCreated(petitionId, msg.sender, _projectId);
        return petitionId;
    }

    /// @notice creates new 'appeal' petition with project/dispute information from original petition 
    /// arbitration fee is higher to compensate larger jury
    /// @dev only callable from Marketplace appealRuling()
    /// @return ID of new 'appeal' petition 
    function appeal(uint256 _projectId) external onlyMarketplace returns (uint256) {
        uint256 originalPetitionId = IMarketplace(msg.sender).getArbitrationPetitionId(_projectId); 
        if(originalPetitionId == 0) revert Court__PetitionDoesNotExist();
        Petition memory originalPetition = getPetition(originalPetitionId);
        if(msg.sender != originalPetition.marketplace) revert Court__InvalidMarketplace();
        if(originalPetition.isAppeal) revert Court__RulingCannotBeAppealed();
        petitionIds.increment(); 
        uint256 petitionId = petitionIds.current();
        Petition memory petition;
        petition.petitionId = petitionId;
        petition.marketplace = msg.sender;
        petition.projectId = _projectId;
        petition.adjustedProjectFee = originalPetition.adjustedProjectFee;
        petition.providerStakeForfeit = originalPetition.providerStakeForfeit;
        petition.plaintiff = originalPetition.plaintiff;
        petition.defendant = originalPetition.defendant;
        petition.arbitrationFee = calculateArbitrationFee(true);
        petition.isAppeal = true;
        petition.discoveryStart = block.timestamp;
        petitions[petitionId] = petition;
        emit AppealCreated(petitionId, originalPetitionId, msg.sender, _projectId);
        return petitionId;
    }

    function calculateArbitrationFee(bool isAppeal) public view returns (uint256) {
        // assumes 20 MATIC minimum per juror voting in majority 
        if(!isAppeal) return 3 * jurorFlatFee;
        else return 5 * jurorFlatFee;
    }

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

    function reclaimArbitrationFee(uint256 _petitionId) external {
        Petition memory petition = getPetition(_petitionId);
        if(msg.sender != petition.plaintiff && msg.sender != petition.defendant) revert Court__OnlyLitigant();
        if(petition.phase == Phase.Verdict) {
            if(petition.petitionGranted && msg.sender != petition.plaintiff) revert Court__OnlyPrevailingParty();
            else if(!petition.petitionGranted && msg.sender != petition.defendant) revert Court__OnlyPrevailingParty();
        } else if (petition.phase == Phase.SettledExternally) {
            if(!petition.feePaidPlaintiff && msg.sender == petition.plaintiff) revert Court__ArbitrationFeeNotPaid();
            else if(!petition.feePaidDefendant && msg.sender == petition.defendant) revert Court__ArbitrationFeeNotPaid();
            // else revert Court__ArbitrationFeeNotPaid();
        } else revert Court__ArbitrationFeeCannotBeReclaimed();
        if(feesHeld[_petitionId] != petition.arbitrationFee) revert Court__ArbitrationFeeAlreadyReclaimed();
        uint256 reclaimAmount = feesHeld[_petitionId];
        feesHeld[_petitionId] -= reclaimAmount;
        (bool success, ) = msg.sender.call{value: reclaimAmount}("");
        if(!success) revert Court__TransferFailed();
        emit ArbitrationFeeReclaimed(_petitionId, msg.sender, reclaimAmount);
    }

    function dismissUnpaidCase(uint256 _petitionId) public {
        Petition storage petition = petitions[_petitionId];
        if(petition.petitionId == 0) revert Court__PetitionDoesNotExist();
        // if(!IMarketplace(petition.marketplace).isDisputed(petition.projectId)) revert Court__ProjectIsNotDisputed();
        if(block.timestamp < petition.discoveryStart + DISCOVERY_PERIOD) revert Court__FeesNotOverdue();
        if(petition.feePaidPlaintiff || petition.feePaidDefendant) revert Court__ArbitrationFeeAlreadyPaid();
        petition.phase = Phase.Dismissed;
        emit CaseDismissed(_petitionId);
    } 

    function settledExternally(uint256 _petitionId) external onlyMarketplace {
        Petition storage petition = petitions[_petitionId];
        petition.phase = Phase.SettledExternally;
        emit SettledExternally(petition.petitionId);
    }

    /// @notice enters default judgement when one litigant has not paid arbitration fee within DISCOVERY_PERIOD
    /// i.e. if plaintiff has paid arbitration fee, but defendant has not, function will grant petition
    /// @dev if both parties have paid, phase will automatically advance to JurySelection and function will revert
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

    function _selectJury(uint256 _petitionId) private returns(uint256) {
        uint256 requestId = VRF_COORDINATOR.requestRandomWords(
            keyHash, 
            subscriptionId, 
            requestConfirmations, 
            callbackGasLimit, 
            numWords
        );
        vrfRequestToPetition[requestId] = _petitionId;
        // Petition storage petition = petitions[_petitionId];
        // petition.phase = Phase.JurySelection;
        // emit JurySelectionInitiated(_petitionId, requestId);
        return requestId;
    }

    // placeholder logic - need more comprehensive selection algorithm
    function jurorsNeeded(uint256 petitionId) public view returns (uint256) {
        if(petitions[petitionId].isAppeal) return 5;
        else return 3;
    } 

    function _juryAssembled(uint256 _petitionId) private {
        Petition storage petition = petitions[_petitionId];
        petition.phase = Phase.Voting;
        petition.votingStart = block.timestamp;
        emit VotingInitiated(_petitionId);
    }

    function _allVotesCommitted(uint256 _petitionId) private {
        Petition storage petition = petitions[_petitionId];
        petition.phase = Phase.Ruling;
        petition.rulingStart = block.timestamp;
        emit RulingInitiated(_petitionId);
    }

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
            juryPool.fundJuryReserves{value: remainingFees}();
        }
        // verdictRendered[_petitionId] = block.timestamp;
        uint256 majorityVotes;
        (petition.petitionGranted) ? majorityVotes = _votesFor : majorityVotes = _votesAgainst;
        emit VerdictReached(_petitionId, petition.petitionGranted, majorityVotes);
    }

    /////////////////////////
    ///   JUROR ACTIONS   ///
    /////////////////////////

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
            if(msg.sender == jury.drawnJurors[i]) {isDrawnJuror = true;}
        }
        if(!isDrawnJuror) revert Court__NotDrawnJuror();
        jurorStakes[msg.sender][_petitionId] = msg.value;
        jury.confirmedJurors.push(msg.sender);
        emit JurorConfirmed(_petitionId, msg.sender);
        if(jury.confirmedJurors.length == jurorsNeeded(_petitionId)) {
            _juryAssembled(_petitionId);
        }
    }

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

    function removeJurorNoCommit(uint256 _petitionId, address _juror) external {
        if(!isConfirmedJuror(_petitionId, _juror)) revert Court__InvalidJuror();
        // Petition memory petition = getPetition(_petitionId);
        Petition storage petition = petitions[_petitionId];
        if(petition.phase != Phase.Voting || block.timestamp < petition.votingStart + VOTING_PERIOD) {
            revert Court__VotingPeriodStillActive();
        }
        if(uint(getCommit(_juror, _petitionId)) != 0) revert Court__NoDelinquentCommit();
        uint256 stakeForfeit = getJurorStakeHeld(_juror, _petitionId);
        jurorStakes[_juror][_petitionId] -= stakeForfeit;
        juryPool.fundJuryReserves{value: stakeForfeit}();
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
        petition.votingStart = block.timestamp; // restart voting period so there is time for new jurors to accept the case and vote
        emit JurorRemoved(_petitionId, _juror, stakeForfeit);
    }

    function delinquentReveal(uint256 _petitionId) external {
        Petition memory petition = getPetition(_petitionId);
        if(petition.phase != Phase.Ruling) revert Court__OnlyDuringRuling();
        if(block.timestamp < petition.rulingStart + RULING_PERIOD) revert Court__RulingPeriodStillActive();
        (uint256 votesFor, uint256 votesAgainst) = _countVotes(petition.petitionId);
        uint256 votesNeeded = jurorsNeeded(petition.petitionId);
        bool caseDeadlocked = false;
        uint256 stakeForfeit; // find jurors who didn't reveal, collect stake amount in case of deadlock
        Jury memory jury = getJury(petition.petitionId);
        for(uint i; i < jury.confirmedJurors.length; ++i) {
            if(!hasRevealedVote(jury.confirmedJurors[i], petition.petitionId)) {
                stakeForfeit += getJurorStakeHeld(jury.confirmedJurors[i], petition.petitionId);
                jurorStakes[jury.confirmedJurors[i]][petition.petitionId] -= stakeForfeit;
            }
        }
        if((votesFor > votesNeeded / 2) || (votesAgainst > votesNeeded / 2)) { 
            _renderVerdict(petition.petitionId, votesFor, votesAgainst); // if majority exists, render verdict as normal
        } else { // if tied, record reimbursement for revealed jurors and restart case 
            caseDeadlocked = true;
            uint256 jurorFee = petition.arbitrationFee / jurorsNeeded(petition.petitionId);
            for(uint i; i < jury.confirmedJurors.length; ++i) {
                if(hasRevealedVote(jury.confirmedJurors[i], petition.petitionId)) {
                    jurorFeeReimbursementOwed[jury.confirmedJurors[i]] += jurorFee;
                    emit JurorFeeReimbursementOwed(petition.petitionId, jury.confirmedJurors[i], jurorFee);
                }
            } 
            juryPool.fundJuryReserves{value: stakeForfeit}(); 
            _restartDeadlockedCase(_petitionId);
        }  
        emit DelinquentReveal(petition.petitionId, caseDeadlocked);      
    }

    function _restartDeadlockedCase(uint256 _petitionId) private {
        Petition storage petition = petitions[_petitionId];
        delete juries[petition.petitionId];
        petition.selectionStart = 0; // will be reset by fulfillRandomWords() and we don't want the function to think it's a re-draw
        uint256 requestId = _selectJury(petition.petitionId);
        petition.phase = Phase.JurySelection;
        emit CaseRestarted(petition.petitionId, requestId);
    }

    //////////////////////
    ///   GOVERNANCE   ///
    //////////////////////

    function registerMarketplace(address _marketplace) external onlyGovernor {
        _registerMarketplace(_marketplace);
        emit MarketplaceRegistered(_marketplace);
    }

    /////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////
    function _registerMarketplace(address _marketplace) private {
        if(registeredMarketplaces[_marketplace]) revert Court__MarketplaceAlreadyRegistered();
        registeredMarketplaces[_marketplace] = true;
    }
    /////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////


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

    function isRegisteredMarketplace(address _marketplace) public view returns (bool) {
        return registeredMarketplaces[_marketplace];
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

    function getJurorFeeReimbursementOwed(address _juror) public view returns (uint256) {
        return jurorFeeReimbursementOwed[_juror];
    }

}
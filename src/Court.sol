// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "chainlink/VRFCoordinatorV2Interface.sol";
import "chainlink/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./interfaces/IMarketplace.sol";
import "./interfaces/IJuryPool.sol";

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
        Dismissed // case is invalid, Marketplace reverts to original project conditions
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

    // Time variables
    uint24 public constant DISCOVERY_PERIOD = 7 days;
    uint24 public constant JURY_SELECTION_PERIOD = 3 days;
    uint24 public constant VOTING_PERIOD = 4 days;
    uint24 public constant RULING_PERIOD = 3 days;

    event PetitionCreated(uint256 indexed petitionId, address marketplace, uint256 projectId);
    event ArbitrationFeePaid(uint256 indexed petitionId, address indexed user);
    event JurySelectionInitiated(uint256 indexed petitionId, uint256 requestId);

    event MarketplaceRegistered(address marketplace);
    


    // permissions
    error Court__OnlyGovernor();
    error Court__OnlyMarketplace();
    error Court__ProjectHasOpenPetition();
    error Court__OnlyLitigant();
    // config 
    error Court__MarketplaceAlreadyRegistered();
    // petition
    error Court__ArbitrationFeeAlreadyPaid();
    error Court__ArbitrationFeeNotPaid();
    error Court__InsufficientAmount();
    error Court__EvidenceCanNoLongerBeSubmitted();

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
        uint64 _subscriptionId
    ) 
         VRFConsumerBaseV2(_vrfCoordinatorV2) 
    {
        GOVERNOR = _governor;
        juryPool = IJuryPool(_juryPool);
        VRF_COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinatorV2);
        subscriptionId = _subscriptionId;
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        // uint256 petitionId = vrfRequestToPetition[requestId];
        Petition storage petition = petitions[vrfRequestToPetition[requestId]];
        bool isRedraw;   
        // if(selectionStart[petitionId] != 0) isRedraw = true; 
        if(petition.selectionStart != 0) isRedraw = true;
        Jury storage jury = juries[petition.petitionId];
        uint256 numNeeded = jurorsNeeded(petition.petitionId) * 3; // will draw 3x jurors needed
        // if(isRedraw) numNeeded = jurorsNeeded(petition.petitionId) * 2;
        address[] memory jurorsDrawn = new address[](numNeeded);
        uint256 nonce = 0;
        uint256 numSelected = 0;
        uint256 poolSize = juryPool.juryPoolSize();
        while (numSelected < numNeeded) {
            uint256 index; 
            uint256 a = uint256(keccak256(abi.encodePacked(randomWords[0], nonce))) % poolSize;
            uint256 b = uint256(keccak256(abi.encodePacked(randomWords[1], nonce))) % poolSize;
            // break if wrong juror status, break if plaintiff or defendant
            // IJuryPool.Juror memory juror = juryPool.getJuror(jurorId);
            // IJuryPool.Juror memory juror = juryPool.getJuror(a);
            // if(juror.jurorStatus != IJuryPool.JurorStatus.Active) {

            // }
            
            // uint256 stakeJurorA = juryPool.getJurorStake(a);
            // uint256 stakeJurorB = juryPool.getJurorStake(b);
            // if(stakeJurorA == stakeJurorB) {
            //     index = a; // if same stake, choose a
            // } else if(stakeJurorA > stakeJurorB) {
            //     (randomWords[0] % 100 < (stakeJurorA * 100)/(stakeJurorA + stakeJurorB)) ? index = a : index = b;
            // } else if(stakeJurorB > stakeJurorA) {
            //     (randomWords[1] % 100 < (stakeJurorB * 100)/(stakeJurorA + stakeJurorB)) ? index = b : index = a;
            // }
            // bool isInvalid = false;
            // // if(!isValidJuror(index, petitionId)) isInvalid = true; // check if juror is allowed to serve
            // address jurorAddr = juryPool.getJuror(index).jurorAddress;
            // for(uint i = 0; i < numSelected; ++i) { // check for duplicates
            //     if (jurorsDrawn[i] == jurorAddr) {
            //         isInvalid = true;
            //         break;
            //     }
            // }
            // if(isRedraw) {
            //     for(uint j; j < jury.drawnJurors.length; ++j) {
            //         if(jurorAddr == jury.drawnJurors[j]) {
            //             isInvalid = true;
            //             break;
            //         } 
            //     }
            // }
            // if(!isInvalid) {
            //     jurorsDrawn[numSelected] = jurorAddr;
            //     ++numSelected;
            // }
            ++nonce;
        }
        for(uint i; i < jurorsDrawn.length; ++i) {
            jury.drawnJurors.push(jurorsDrawn[i]);
        }
        // if(!isRedraw) selectionStart[petitionId] = block.timestamp;
        if(!isRedraw) petition.selectionStart = block.timestamp;
        // emit JuryDrawn(petitionId, isRedraw);   ` 
    }

    function isValidJuror(address _juror, uint256 _petitionId) internal returns (bool) {

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
        if(petition.feePaidPlaintiff && petition.feePaidDefendant) _selectJury(_petitionId);
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

    ////////////////
    ///   JURY   ///
    ////////////////

    function _selectJury(uint256 _petitionId) private {
        uint256 requestId = VRF_COORDINATOR.requestRandomWords(
            keyHash, 
            subscriptionId, 
            requestConfirmations, 
            callbackGasLimit, 
            numWords
        );
        vrfRequestToPetition[requestId] = _petitionId;
        Petition storage petition = petitions[_petitionId];
        petition.phase = Phase.JurySelection;
        emit JurySelectionInitiated(_petitionId, requestId);
    }

    // need more complex logic here
    function jurorsNeeded(uint256 petitionId) public view returns (uint256) {
        if(petitions[petitionId].isAppeal) return 5;
        return 3;
    } 

    //////////////////////
    ///   GOVERNANCE   ///
    //////////////////////

    function registerMarketplace(address _marketplace) external onlyGovernor {
        if(registeredMarketplaces[_marketplace]) revert Court__MarketplaceAlreadyRegistered();
        registeredMarketplaces[_marketplace] = true;
        emit MarketplaceRegistered(_marketplace);
    }

    function setJurorFlatFee(uint256 _flatFee) external onlyGovernor {
        jurorFlatFee = _flatFee;
    }

    //////////////////
    ///  GETTERS   ///
    //////////////////

    function getPetition(uint256 _petitionId) public view returns (Petition memory) {
        return petitions[_petitionId];
    }

    function isRegisteredMarketplace(address _marketplace) public view returns (bool) {
        return registeredMarketplaces[_marketplace];
    }

}
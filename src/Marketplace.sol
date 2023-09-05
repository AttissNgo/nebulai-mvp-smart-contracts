// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Interfaces/IWhitelist.sol";
import "./Interfaces/IEscrow.sol";
import "./Interfaces/ICourt.sol";

interface IEscrowFactory {
    function createEscrowContract(
        address _marketplace,
        uint256 _projectId,
        address _buyer,
        address _provider,
        address _paymentToken,
        uint256 _projectFee,
        uint256 _providerStake,
        address _court,
        string memory _detailsURI
    ) external returns (address); 
}

contract Marketplace {
    using Counters for Counters.Counter;

    address public immutable GOVERNOR;
    IWhitelist public immutable WHITELIST;
    ICourt public immutable COURT;
    IEscrowFactory public immutable ESCROW_FACTORY;

    /**
     * @notice ERC20 tokens which can be used as payment token for Projects
     */
    address[] public erc20Tokens;
    mapping(address => bool) public isApprovedToken;


    uint256 public nebulaiTxFee = 3;
    uint256 public constant minimumTxFee = 3 ether;
    /**
     * @dev Transaction fees held for a Project ID (fees will be returned if Project is Cancelled)
     */
    mapping(uint256 => uint256) private txFeesHeld;
    /**
     * @dev token address (zero for native) to amount held by Marketplace (non-refundable)
     */
    mapping(address => uint256) private txFeesPaid;
    /**
     * @dev token address (zero for native) to amount received from completed Projects
     */
    mapping(address => uint256) private commissionFees; 

    /**
     * @notice the state of a Project
     * Created - Escrow holds project fee, but work has not started
     * Cancelled - project is withdrawn by buyer before provider begins work 
     * Active - provider has staked in Escrow and has begun work 
     * Discontinued - either party quits and a change order period begins to handle partial payment
     * Completed - provider claims project is complete and is awaiting buyer approval
     * Approved - buyer is satisfied, escrow will release project fee to provider, Project is closed
     * Challenged - buyer is unsatisfied and submits a Change Order - provider has a chance to accept OR go to arbitration 
     * Disputed - Change Order NOT accepted by provider -> Project goes to arbitration
     * Appealed - the correctness of the court's decision is challenged -> a new arbitration case is opened
     * Resolved_ChangeOrder - escrow releases funds according to change order
     * Resolved_CourtOrder - escrow releases funds according to court petition
     * Resolved_DelinquentPayment - escrow releases funds according to original agreement
     * Resolved_ArbitrationDismissed - escrow releases funds according to original agreement
     */
    enum Status { 
        Created, 
        Cancelled, 
        Active, 
        Discontinued, 
        Completed, 
        Approved, 
        Challenged, 
        Disputed,
        Appealed, 
        Resolved_ChangeOrder, 
        Resolved_CourtOrder, 
        Resolved_DelinquentPayment, 
        Resolved_ArbitrationDismissed 
    }

    /**
     * @notice details of an agreement between a buyer and service provider
     */
    struct Project {
        uint256 projectId;
        address buyer;
        address provider;
        address escrow;
        address paymentToken;
        uint256 projectFee;
        uint256 providerStake;
        uint256 dueDate;
        uint256 reviewPeriodLength;
        uint256 dateCompleted;
        uint256 changeOrderPeriodInitiated;
        uint256 nebulaiTxFee;
        Status status;
        string detailsURI;
    }

    Counters.Counter public projectIds;
    mapping(uint256 => Project) private projects;

    /**
     * @notice proposal to alter payment details of a Project
     */
    struct ChangeOrder {
        uint256 projectId;
        uint256 dateProposed;
        address proposedBy;
        uint256 adjustedProjectFee;
        uint256 providerStakeForfeit;
        bool buyerApproval;
        bool providerApproval;
        string detailsURI;
    }
    /**
     * @dev only one active Change Order per Project ID is possible
     */
    mapping(uint256 => ChangeOrder) private changeOrders; 
    /**
     * @dev Project ID mapped to Petition ID in Court smart contract
     */
    mapping(uint256 => uint256) private arbitrationCases; 

    /**
     * @notice time to approve a Change Order after it is created
     */
    uint24 public constant CHANGE_ORDER_PERIOD = 7 days;
    /**
     * @notice time to appeal a Court decision after the verdict has been rendered
     */
    uint24 public constant APPEAL_PERIOD = 7 days;

    event NebulaiTxFeeChanged(uint256 txFee);
    event ERC20Approved(address token);
    event ERC20Removed(address token);
    event ProjectCreated(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectCancelled(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectActivated(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectDiscontinued(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectCompleted(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectApproved(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectChallenged(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectDisputed(uint256 indexed projectId, address indexed buyer, address indexed provider, uint256 petitionId);
    event ProjectAppealed(uint256 indexed projectId, uint256 indexed petitionId, address appealedBy);
    event DelinquentPayment(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ChangeOrderProposed(uint256 indexed projectId);
    event ChangeOrderApproved(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ChangeOrderRetracted(uint256 indexed projectId, address indexed retractedBy);
    event ResolvedByCourtOrder(uint256 indexed projectId, uint256 indexed petitionId);
    event ResolvedByDismissedCase(uint256 indexed projectId, uint256 indexed petitionId);
    event SettlementProposed(uint256 indexed projectId, uint256 indexed petitionId);
    event CommissionFeeReceived(uint256 indexed projectId, uint256 commissionAmount, address paymentToken);
    event FeesWithdrawnERC20(address recipient, address token, uint256 amount);
    event FeesWithdrawnNative(address recipient, uint256 amount);

    // transfers
    error Marketplace__TransferFailed();
    error Marketplace__InsufficientAmount();
    error Marketplace__InsufficientApproval();
    // permissions
    error Marketplace__OnlyUser();
    error Marketplace__OnlyGovernor();
    error Marketplace__OnlyBuyer();
    error Marketplace__OnlyProvider();
    error Marketplace__OnlyBuyerOrProvider();
    error Marketplace__CommissionMustBePaidByEscrow();
    // input data
    error Marketplace__InvalidProviderAddress();
    error Marketplace__InvalidDueDate();
    error Marketplace__UnapprovedToken();
    // project actions
    error Marketplace__ProjectCannotBeCancelled();
    error Marketplace__ProjectCannotBeActivated();
    error Marketplace__ProjectMustBeActive();
    error Marketplace__ProjectNotCompleted();
    error Marketplace__ProjectCannotBeChallenged();
    error Marketplace__ProjectIsNotOverdue();
    error Marketplace__ProjectReviewPeriodEnded();
    error Marketplace__PaymentIsNotDelinquent();
    // change orders
    error Marketplace__ChangeOrderCannotBeProposed();
    error Marketplace__ChangeOrderAlreadyExists();
    error Marketplace__AdjustedFeeExceedsProjectFee();
    error Marketplace__ForfeitExceedsProviderStake();
    error Marketplace__NoActiveChangeOrder();
    error Marketplace__ChangeOrderNotValid();
    error Marketplace__AlreadyApprovedChangeOrder();
    error Marketplace__ChangeOrderPeriodStillActive();
    error Marketplace__InvalidSettlement();
    // arbitration
    error Marketplace__ProjectCannotBeDisputed();
    error Marketplace__ProjectIsNotDisputed();
    error Marketplace__CourtHasNotRuled();
    error Marketplace__AppealPeriodOver();
    error Marketplace__AppealPeriodNotOver();
    error Marketplace__OnlyNonPrevailingParty();
    error Marketplace__CourtHasNotDismissedCase();
    error Marketplace__CourtCaseAlreadyInitiated();
    
    modifier onlyUser() {
        if(!WHITELIST.isApproved(msg.sender)) revert Marketplace__OnlyUser();
        _;
    }

    modifier onlyGovernor() {
        if(msg.sender != GOVERNOR) revert Marketplace__OnlyGovernor();
        _;
    }

    constructor(
        address _governor,
        address _whitelist,
        address _court,
        address _escrowFactory,
        address[] memory _approvedTokens
    )
    {
        GOVERNOR = _governor;
        WHITELIST = IWhitelist(_whitelist);
        COURT = ICourt(_court);
        ESCROW_FACTORY = IEscrowFactory(_escrowFactory);
        for(uint i = 0; i < _approvedTokens.length; ++i) {
            _approveToken(_approvedTokens[i]);
        }
    }

    fallback() external payable {}
    receive() external payable {}

    /**
     * @notice creates a Project in Marketplace and deploys an Escrow contract
     * @dev project ID cannot be zero
     * @return projectId of newly created Project
     */
    function createProject(
        address _provider,
        address _paymentToken,
        uint256 _projectFee,
        uint256 _providerStake,
        uint256 _dueDate,
        uint256 _reviewPeriodLength,
        string memory _detailsURI
    ) 
        external 
        payable
        onlyUser 
        returns (uint256) 
    {
        if(_provider == msg.sender || _provider == address(0)) revert Marketplace__InvalidProviderAddress();
        if(_dueDate < block.timestamp || _dueDate > block.timestamp + 365 days) revert Marketplace__InvalidDueDate();
        uint256 txFee = calculateNebulaiTxFee(_projectFee);
        projectIds.increment(); 
        Project memory p;
        p.projectId = projectIds.current();
        p.buyer = msg.sender;
        p.provider = _provider;
        p.escrow = ESCROW_FACTORY.createEscrowContract(
            address(this),
            p.projectId,
            msg.sender,
            _provider,
            _paymentToken,
            _projectFee,
            _providerStake,
            address(COURT),
            _detailsURI
        );
        p.paymentToken = _paymentToken;
        p.providerStake = _providerStake;
        p.dueDate = _dueDate;
        p.reviewPeriodLength = _reviewPeriodLength;
        p.nebulaiTxFee = txFee;
        p.detailsURI = _detailsURI;
        if(_paymentToken != address(0)) {
            if(!isApprovedToken[_paymentToken]) revert Marketplace__UnapprovedToken();
            if(IERC20(_paymentToken).allowance(msg.sender, address(this)) < txFee + _projectFee) revert Marketplace__InsufficientApproval();
            bool success = IERC20(_paymentToken).transferFrom(msg.sender, address(this), txFee);
            if(!success) revert Marketplace__TransferFailed();
            success = IERC20(_paymentToken).transferFrom(msg.sender, p.escrow, _projectFee);
            if(!success) revert Marketplace__TransferFailed();
        } else {
            if(msg.value < txFee + _projectFee) revert Marketplace__InsufficientAmount();
            (bool success, ) = p.escrow.call{value: _projectFee}("");
            if(!success) revert Marketplace__TransferFailed();
        }
        p.projectFee = _projectFee;
        txFeesHeld[p.projectId] = txFee;
        projects[p.projectId] = p;
        emit ProjectCreated(p.projectId, p.buyer, p.provider);
        return p.projectId;
    }

    /**
     * @notice Project is closed and Escrow releases projectFee to Buyer
     * @notice txFee is refunded to Buyer
     * @notice can only be called if Provider has not activate Project
     */
    function cancelProject(uint256 _projectId) external {
        Project storage p = projects[_projectId];
        if(msg.sender != p.buyer) revert Marketplace__OnlyBuyer();
        if(p.status != Status.Created) revert Marketplace__ProjectCannotBeCancelled();
        uint256 txFeeRefund = getTxFeesHeld(_projectId);
        p.status = Status.Cancelled;
        txFeesHeld[_projectId] -= txFeeRefund;
        if(p.paymentToken != address(0)) {
            bool success = IERC20(p.paymentToken).transfer(msg.sender, txFeeRefund);
            if(!success) revert Marketplace__TransferFailed();
        } else {
            (bool success,) = msg.sender.call{value: txFeeRefund}("");
            if(!success) revert Marketplace__TransferFailed();
        }
        emit ProjectCancelled(_projectId, p.buyer, p.provider);
    }

    /**
     * @notice Provider stakes in Escrow and begins working on Project
     */
    function activateProject(uint256 _projectId) external payable onlyUser {
        Project storage p = projects[_projectId];
        if(msg.sender != p.provider) revert Marketplace__OnlyProvider();
        if(p.status != Status.Created) revert Marketplace__ProjectCannotBeActivated();
        if(p.providerStake > 0) {
            if(p.paymentToken != address(0)) {
                if(IERC20(p.paymentToken).allowance(msg.sender, address(this)) < p.providerStake) {
                    revert Marketplace__InsufficientApproval();
                }
                bool success = IERC20(p.paymentToken).transferFrom(msg.sender, p.escrow, p.providerStake);
                if(!success) revert Marketplace__TransferFailed();
            } else {
                if(msg.value < p.providerStake) revert Marketplace__InsufficientAmount();
                (bool success,) = p.escrow.call{value: p.providerStake}("");
                if(!success) revert Marketplace__TransferFailed();
            }
        }
        require(IEscrow(p.escrow).verifyProviderStake());
        txFeesPaid[p.paymentToken] += txFeesHeld[_projectId];
        txFeesHeld[_projectId] = 0;
        p.status = Status.Active;
        emit ProjectActivated(_projectId, p.buyer, p.provider);
    }

    /**
     * @notice either Buyer or Provider discontinues Project and proposes a Change Order
     * @param _changeOrderDetailsURI details of Change Order on distributed file system
     */
    function discontinueProject(
        uint256 _projectId,
        uint256 _adjustedProjectFee,
        uint256 _providerStakeForfeit,
        string memory _changeOrderDetailsURI    
    ) 
        external 
    {
        Project storage p = projects[_projectId];
        if(msg.sender != p.buyer && msg.sender != p.provider) revert Marketplace__OnlyBuyerOrProvider();
        if(p.status != Status.Active) revert Marketplace__ProjectMustBeActive();
        p.status = Status.Discontinued;
        p.changeOrderPeriodInitiated = block.timestamp;
        _proposeChangeOrder(
            _projectId,
            _adjustedProjectFee,
            _providerStakeForfeit,
            _changeOrderDetailsURI
        );
        emit ProjectDiscontinued(_projectId, p.buyer, p.provider);
    }

    /**
     * @notice Provider Project is complete, reviewPeriod is initiated in which Buyer reviews deliverables
     */
    function completeProject(uint256 _projectId) external {
        Project storage p = projects[_projectId];
        if(msg.sender != p.provider) revert Marketplace__OnlyProvider();
        if(p.status != Status.Active) revert Marketplace__ProjectMustBeActive();
        p.status = Status.Completed;
        p.dateCompleted = block.timestamp;
        emit ProjectCompleted(p.projectId, p.buyer, p.provider);
    }

    /**
     * @notice Buyer approves deliverables, Project is closed and Escrow releases funds according to Project details
     */
    function approveProject(uint256 _projectId) external {
        Project storage p = projects[_projectId];
        if(msg.sender != p.buyer) revert Marketplace__OnlyBuyer();
        if(p.status != Status.Completed) revert Marketplace__ProjectNotCompleted();
        p.status = Status.Approved;
        emit ProjectApproved(p.projectId, p.buyer, p.provider);
    }

    /**
     * @notice Buyer challenges completed Project and proposes Change Order
     * @param _changeOrderDetailsURI details of Change Order on distributed file system
     */
    function challengeProject(
        uint256 _projectId,
        uint256 _adjustedProjectFee,
        uint256 _providerStakeForfeit,
        string memory _changeOrderDetailsURI 
    ) 
        external 
    {
        Project storage p = projects[_projectId];
        if(msg.sender != p.buyer) revert Marketplace__OnlyBuyer();
        if(p.status != Status.Active && p.status != Status.Completed) revert Marketplace__ProjectCannotBeChallenged();
        if(p.status == Status.Active && block.timestamp < p.dueDate) revert Marketplace__ProjectIsNotOverdue();
        if(p.status == Status.Completed && block.timestamp > p.dateCompleted + p.reviewPeriodLength) {
            revert Marketplace__ProjectReviewPeriodEnded();
        } 
        p.status = Status.Challenged;
        p.changeOrderPeriodInitiated = block.timestamp;
        _proposeChangeOrder(
            _projectId,
            _adjustedProjectFee,
            _providerStakeForfeit,
            _changeOrderDetailsURI
        );
        emit ProjectChallenged(_projectId, p.buyer, p.provider);
    }

    /**
     * @notice Project is closed and Escrow releases funds according to Project details
     * @notice can only be called after reviewPeriod has elapsed and Buyer has not approved or challenged
     */
    function delinquentPayment(uint256 _projectId) external {
        Project storage p = projects[_projectId];
        if(msg.sender != p.provider) revert Marketplace__OnlyProvider();
        if(p.status != Status.Completed || block.timestamp < p.dateCompleted + p.reviewPeriodLength) {
            revert Marketplace__PaymentIsNotDelinquent();
        }
        p.status = Status.Resolved_DelinquentPayment;
        emit DelinquentPayment(_projectId, p.buyer, p.provider); 
    }

    ///////////////////////
    ///   ARBITRATION   ///
    ///////////////////////

    /**
     * @notice initiates arbitration by creating a Petition in Court contract
     * @notice can only be called after a Change Order has failed to be approved within CHANGE_ORDER_PERIOD
     * @dev deletes existing (non-approved) Change Order
     * @return petitionID identifier of Petition in Court contract
     */
    function disputeProject(
        uint256 _projectId,
        uint256 _adjustedProjectFee,
        uint256 _providerStakeForfeit
    ) 
        external 
        returns (uint256)
    {
        Project storage p = projects[_projectId];
        if(msg.sender != p.buyer && msg.sender != p.provider) revert Marketplace__OnlyBuyerOrProvider();
        if(p.status != Status.Challenged && p.status != Status.Discontinued) revert Marketplace__ProjectCannotBeDisputed();
        if(block.timestamp < p.changeOrderPeriodInitiated + CHANGE_ORDER_PERIOD) {
            revert Marketplace__ChangeOrderPeriodStillActive();
        }
        p.status = Status.Disputed;
        ChangeOrder memory emptyChangeOrder;
        changeOrders[p.projectId] = emptyChangeOrder;
        if(_adjustedProjectFee > p.projectFee) revert Marketplace__AdjustedFeeExceedsProjectFee();
        if(_providerStakeForfeit > p.providerStake) revert Marketplace__ForfeitExceedsProviderStake();
        uint256 petitionId = COURT.createPetition(
            p.projectId,
            _adjustedProjectFee,
            _providerStakeForfeit,
            (msg.sender == p.buyer) ? p.buyer : p.provider,
            (msg.sender == p.buyer) ? p.provider : p.buyer
        );
        arbitrationCases[_projectId] = petitionId;
        emit ProjectDisputed(p.projectId, p.buyer, p.provider, petitionId);
        return petitionId;
    }

    /**
     * @notice creates a new Petition in Court contract with same details of original arbitration case
     * @notice can only called between rendering of original verdict and end of APPEAL_PERIOD
     * @return petitionID identifier of Petition in Court contract
     */
    function appealRuling(uint256 _projectId) external returns (uint256) {
        Project storage p = projects[_projectId];
        if(msg.sender != p.buyer && msg.sender != p.provider) revert Marketplace__OnlyBuyerOrProvider();
        if(p.status != Status.Disputed) revert Marketplace__ProjectIsNotDisputed();
        ICourt.Petition memory petition = COURT.getPetition(arbitrationCases[_projectId]);
        if(petition.phase != ICourt.Phase.Verdict) revert Marketplace__CourtHasNotRuled();
        if(block.timestamp >= petition.verdictRenderedDate + APPEAL_PERIOD) revert Marketplace__AppealPeriodOver();
        p.status = Status.Appealed;
        uint256 petitionId = COURT.appeal(_projectId);
        arbitrationCases[_projectId] = petitionId;
        emit ProjectAppealed(_projectId, petitionId, msg.sender);
        return petitionId;
    }

    /**
     * @notice Project is closed and Escrow releases funds according to Petition in Court contract
     * @notice only non-prevailing party may waive the appeal
     */
    function waiveAppeal(uint256 _projectId) external {
        Project storage project = projects[_projectId];
        if(project.status != Status.Disputed) revert Marketplace__ProjectIsNotDisputed();
        ICourt.Petition memory petition = COURT.getPetition(arbitrationCases[_projectId]);
        if(petition.phase != ICourt.Phase.Verdict) revert Marketplace__CourtHasNotRuled();
        if(petition.petitionGranted) {
            if(msg.sender != petition.defendant) revert Marketplace__OnlyNonPrevailingParty();
        } else {
            if(msg.sender != petition.plaintiff) revert Marketplace__OnlyNonPrevailingParty();
        }
        project.status = Status.Resolved_CourtOrder;
        emit ResolvedByCourtOrder(project.projectId, petition.petitionId);
    }

    /**
     * @notice Project is closed and Escrow releases funds according to Petition in Court contract
     * @notice if Petition is not appeal, user must wait until after APPEAL_PERIOD elapses
     */
    function resolveByCourtOrder(uint256 _projectId) public {
        Project storage project = projects[_projectId];
        if(msg.sender != project.buyer && msg.sender != project.provider) revert Marketplace__OnlyBuyerOrProvider();
        if(project.status != Status.Disputed) revert Marketplace__ProjectIsNotDisputed();
        ICourt.Petition memory petition = COURT.getPetition(arbitrationCases[_projectId]);
        if(petition.phase != ICourt.Phase.Verdict && petition.phase != ICourt.Phase.DefaultJudgement) {
            revert Marketplace__CourtHasNotRuled();
        }
        if(!petition.isAppeal) {
            if(block.timestamp < petition.verdictRenderedDate + APPEAL_PERIOD) revert Marketplace__AppealPeriodNotOver();
        }
        project.status = Status.Resolved_CourtOrder;
        emit ResolvedByCourtOrder(_projectId, petition.petitionId);
    }

    /**
     * @notice Project is closed and Escrow releases funds according to Project details
     * @notice Petition can be dismissed in Court contract if neither party pays arbitration fee
     */
    function resolveDismissedCase(uint256 _projectId) public {
        Project storage project = projects[_projectId];
        if(msg.sender != project.buyer && msg.sender != project.provider) revert Marketplace__OnlyBuyerOrProvider();
        if(project.status != Status.Disputed) revert Marketplace__ProjectIsNotDisputed();
        ICourt.Petition memory petition = COURT.getPetition(arbitrationCases[_projectId]);
        if(petition.phase != ICourt.Phase.Dismissed) revert Marketplace__CourtHasNotDismissedCase();
        project.status = Status.Resolved_ArbitrationDismissed;
        emit ResolvedByDismissedCase(_projectId, petition.petitionId);
    }

    /**
     * @notice creates a new Change Order during arbitration
     * @notice can only be created before both parties have paid arbitration fee in Court contract
     * @param _settlementDetailsURI details of Change Order on distributed file system
     */
    function proposeSettlement( 
        uint256 _projectId,
        uint256 _adjustedProjectFee,
        uint256 _providerStakeForfeit,
        string memory _settlementDetailsURI
    ) 
        external 
    {
        Project memory project = projects[_projectId];
        if(msg.sender != project.buyer && msg.sender != project.provider) revert Marketplace__OnlyBuyerOrProvider();
        if(project.status != Status.Disputed) revert Marketplace__ProjectIsNotDisputed();
        ICourt.Petition memory petition = COURT.getPetition(getArbitrationPetitionId(project.projectId));
        if(petition.phase != ICourt.Phase.Discovery) revert Marketplace__CourtCaseAlreadyInitiated();
        _proposeChangeOrder(
            _projectId,
            _adjustedProjectFee,
            _providerStakeForfeit,
            _settlementDetailsURI
        );
        emit SettlementProposed(_projectId, getArbitrationPetitionId(_projectId));
    }

    ////////////////////////
    ///   CHANGE ORDER   ///
    ////////////////////////

    /**
     * @notice creates a new Change Order
     * @dev sets approval as true for user who proposes Change Order
     */
    function _proposeChangeOrder(
        uint256 _projectId,
        uint256 _adjustedProjectFee,
        uint256 _providerStakeForfeit,
        string memory _changeOrderDetailsURI
    ) 
        private 
    {
        Project memory p = getProject(_projectId);
        if(msg.sender != p.buyer && msg.sender != p.provider) revert Marketplace__OnlyBuyerOrProvider();
        if(
            p.status != Status.Discontinued && 
            p.status != Status.Challenged && 
            p.status != Status.Disputed
        ) revert Marketplace__ChangeOrderCannotBeProposed();
        if(_adjustedProjectFee > p.projectFee) revert Marketplace__AdjustedFeeExceedsProjectFee();
        if(_providerStakeForfeit > p.providerStake) revert Marketplace__ForfeitExceedsProviderStake();
        changeOrders[_projectId] = ChangeOrder({
            projectId: _projectId,
            dateProposed: block.timestamp,
            proposedBy: msg.sender,
            adjustedProjectFee: _adjustedProjectFee,
            providerStakeForfeit: _providerStakeForfeit,
            buyerApproval: (msg.sender == p.buyer) ? true : false,
            providerApproval: (msg.sender == p.provider) ? true : false,
            detailsURI: _changeOrderDetailsURI
        }); 
        emit ChangeOrderProposed(p.projectId);
    }

    /**
     * @notice Project is closed and Escrow releases funds according to Change Order
     */
    function approveChangeOrder(uint256 _projectId) external {
        if(!activeChangeOrder(_projectId)) revert Marketplace__NoActiveChangeOrder();
        Project storage p = projects[_projectId];
        if(msg.sender != p.buyer && msg.sender != p.provider) revert Marketplace__OnlyBuyerOrProvider();
        if(
            p.status != Status.Discontinued &&
            p.status != Status.Challenged && 
            p.status != Status.Disputed 
        ) revert Marketplace__ChangeOrderNotValid();
        ChangeOrder storage c = changeOrders[_projectId];
        if(
            msg.sender == p.buyer && c.buyerApproval ||
            msg.sender == p.provider && c.providerApproval
        ) revert Marketplace__AlreadyApprovedChangeOrder();
        if(msg.sender == p.buyer) c.buyerApproval = true;
        if(msg.sender == p.provider) c.providerApproval = true;
        if(p.status == Status.Disputed) {
            _validSettlement(p.projectId);
        }
        p.status = Status.Resolved_ChangeOrder;
        emit ChangeOrderApproved(p.projectId, p.buyer, p.provider);
    }
    
    /**
     * @dev updates Petition phase in Court contract if Change Order is settlement
     */
    function _validSettlement(uint256 _projectId) private {
        ICourt.Petition memory petition = COURT.getPetition(getArbitrationPetitionId(_projectId));
        if(petition.phase != ICourt.Phase.Discovery) revert Marketplace__ChangeOrderNotValid();
        COURT.settledExternally(petition.petitionId);
    }

    ////////////////
    ///   UTIL   ///
    ////////////////

    function calculateNebulaiTxFee(uint256 _projectFee) public view returns (uint256) {
        uint256 txFee = (_projectFee * nebulaiTxFee) / 100;
        if(txFee < minimumTxFee) txFee = minimumTxFee;
        return txFee;
    }

    function _approveToken(address _token) private {
        erc20Tokens.push(_token);
        isApprovedToken[_token] = true;
    }

    /**
     * @dev called by Escrow after tranferring commission fee to Marketplace when Provider withdraws
     */
    function receiveCommission(uint256 _projectId, uint256 _commission) external {
        Project memory project = getProject(_projectId);
        if(msg.sender != project.escrow) revert Marketplace__CommissionMustBePaidByEscrow();
        commissionFees[project.paymentToken] += _commission;
        emit CommissionFeeReceived(_projectId, _commission, project.paymentToken);
    }

    //////////////////////
    ///   GOVERNANCE   ///
    //////////////////////

    function setNebulaiTxFee(uint256 _feePercentage) external onlyGovernor {
        require(_feePercentage > 0 && _feePercentage < 10);
        nebulaiTxFee = _feePercentage;
        emit NebulaiTxFeeChanged(_feePercentage);
    }

    function approveToken(address _erc20) external onlyGovernor {
        _approveToken(_erc20);
        emit ERC20Approved(_erc20);
    }

    function removeToken(address _erc20) external onlyGovernor {
        isApprovedToken[_erc20] = false;
        emit ERC20Removed(_erc20);
    }

    /**
     * @dev transfers all releasable fees paid in native currency and ERC20 tokens 
     */
    function withdrawFees(address _recipient) external onlyGovernor {
        for(uint i; i < erc20Tokens.length; ++i) {
            if(!isApprovedToken[erc20Tokens[i]]) revert Marketplace__UnapprovedToken();
            uint256 erc20Fees = txFeesPaid[erc20Tokens[i]] + commissionFees[erc20Tokens[i]];
            txFeesPaid[erc20Tokens[i]] = 0;
            commissionFees[erc20Tokens[i]] = 0;
            if(erc20Fees > 0) {
                bool erc20success = IERC20(erc20Tokens[i]).transfer(_recipient, erc20Fees);
                if(!erc20success) revert Marketplace__TransferFailed();
                emit FeesWithdrawnERC20(_recipient, erc20Tokens[i], erc20Fees);
            }
        }
        // get all matic
        uint256 nativeFees = txFeesPaid[address(0)] + commissionFees[address(0)];
        txFeesPaid[address(0)] = 0;
        commissionFees[address(0)] = 0;
        if(nativeFees > 0) {
            (bool success, ) = _recipient.call{value: nativeFees}("");
            if(!success) revert Marketplace__TransferFailed();
        }
        emit FeesWithdrawnNative(_recipient, nativeFees);
    }

    ///////////////////
    ///   GETTERS   ///
    ///////////////////

    function getProject(uint256 _projectId) public view returns (Project memory) {
        return projects[_projectId];
    }

    function getProjectStatus(uint256 _projectId) public view returns (Status) {
        Project memory project = getProject(_projectId);
        return project.status;
    }

    function isDisputed(uint256 _projectId) public view returns (bool) {
        return projects[_projectId].status == Status.Disputed;
    }

    function getTxFeesHeld(uint256 _projectId) public view returns (uint256) {
        return txFeesHeld[_projectId];
    }

    function getTxFeesPaid(address _paymentToken) public view returns (uint256) {
        return txFeesPaid[_paymentToken];
    }

    function getCommissionFees(address _paymentToken) public view returns (uint256) {
        return commissionFees[_paymentToken];
    }

    function getChangeOrder(uint256 _projectId) public view returns (ChangeOrder memory) {
        return changeOrders[_projectId];
    }

    function activeChangeOrder(uint256 _projectId) public view returns (bool) {
        ChangeOrder memory c = getChangeOrder(_projectId);
        if(c.dateProposed == 0) return false;
        return true;
    }

    function getArbitrationPetitionId(uint256 projectId) public view returns (uint256) {
        return arbitrationCases[projectId];
    }

    function getErc20Tokens() public view returns (address[] memory) {
        return erc20Tokens;
    }

}
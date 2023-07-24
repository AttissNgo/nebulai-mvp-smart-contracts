// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Interfaces/IWhitelist.sol";
import "./Interfaces/IEscrow.sol";
import "./Interfaces/ICourt.sol";

/**
 * Stores project state
 * Used to get details of project
 * coordinates change orders and court orders
 */

interface IEscrowFactory {
    function createEscrowContract(
        address _marketplace,
        uint256 _projectId,
        address _buyer,
        address _provider,
        address _paymentToken,
        uint256 _projectFee,
        uint256 _providerStake,
        string memory _detailsURI
    ) external returns (address); 
}

contract Marketplace {
    using Counters for Counters.Counter;

    address public immutable GOVERNOR;
    IWhitelist public immutable WHITELIST;
    ICourt public immutable COURT;
    IEscrowFactory public immutable ESCROW_FACTORY;

    mapping(address => bool) public isApprovedToken; // ERC20 tokens accepted by Marketplace

    uint256 public nebulaiTxFee = 3;
    uint256 public constant minimumTxFee = 3 ether; // if project fee is very low or zero, buyer still must pay 3 matic to create project
    mapping(uint256 => uint256) private txFeesHeld; // project ID to amount held - check Project object for payment token
    mapping(address => uint256) private txFeesPaid; // token address (0 for matic) => amount

    enum Status { 
        Created, // project is created but has not been started - Escrow holds project fee
        Cancelled, // project is withdrawn by buyer before provider begins work
        Active, // provider has started work - Provider must stake in ESCROW to initiate this status
        Discontinued, // either party quits - change order period begins
        Completed, // provider claims project is complete
        Approved, // buyer is satisfied and project fee is released to provider, Project is closed
        Challenged, // buyer requests full or partial refund via Change Order - provider has a chance to accept OR go to aribtration 
        Disputed, // Change Order NOT accepted by provider -> Project goes to arbitration
        Appealed, // new arbitration case is opened
        Resolved_ChangeOrder, // escrow releases according to change order
        Resolved_CourtOrder, // escrow releases according to court petition
        Resolved_DelinquentPayment, // escrow releases according to original agreement
        Resolved_ArbitrationDismissed // escrow releases according to original agreement
    }

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

    struct ChangeOrder {
        uint256 projectId;
        // uint256 changeOrderId;
        uint256 dateProposed;
        address proposedBy;
        uint256 adjustedProjectFee;
        uint256 providerStakeForfeit;
        bool buyerApproval;
        bool providerApproval;
        string detailsURI;
    }
    // Counters.Counter private changeOrderIds; // each Change Order has unique ID
    mapping(uint256 => ChangeOrder) private changeOrders; // projectId => ChangeOrder - only one active per project allowed
    mapping(uint256 => uint256) private arbitrationCases; // project ID => court petition ID 

    // After Challenge or Discontinuation --> time to complete a Change Order
    uint24 public constant CHANGE_ORDER_PERIOD = 7 days;
    // After COURT rules --> loser has time to make counter offer or appeal 
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
        projectIds.increment(); // project ID cannot be 0
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

    function cancelProject(uint256 _projectId) external {
        Project storage p = projects[_projectId];
        if(msg.sender != p.buyer) revert Marketplace__OnlyBuyer();
        if(p.status != Status.Created) revert Marketplace__ProjectCannotBeCancelled();
        uint256 txFeeRefund = getTxFeesHeld(_projectId);
        p.status = Status.Cancelled;
        txFeesHeld[_projectId] -= txFeeRefund;
        // refund tx fee to buyer
        if(p.paymentToken != address(0)) {
            bool success = IERC20(p.paymentToken).transfer(msg.sender, txFeeRefund);
            if(!success) revert Marketplace__TransferFailed();
        } else {
            (bool success,) = msg.sender.call{value: txFeeRefund}("");
            if(!success) revert Marketplace__TransferFailed();
        }
        emit ProjectCancelled(_projectId, p.buyer, p.provider);
    }

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

    function completeProject(uint256 _projectId) external {
        Project storage p = projects[_projectId];
        if(msg.sender != p.provider) revert Marketplace__OnlyProvider();
        if(p.status != Status.Active) revert Marketplace__ProjectMustBeActive();
        p.status = Status.Completed;
        p.dateCompleted = block.timestamp;
        emit ProjectCompleted(p.projectId, p.buyer, p.provider);
    }

    function approveProject(uint256 _projectId) external {
        Project storage p = projects[_projectId];
        if(msg.sender != p.buyer) revert Marketplace__OnlyBuyer();
        if(p.status != Status.Completed) revert Marketplace__ProjectNotCompleted();
        p.status = Status.Approved;
        emit ProjectApproved(p.projectId, p.buyer, p.provider);
    }

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
        // delete existing change order 
        ChangeOrder memory emptyChangeOrder;
        changeOrders[p.projectId] = emptyChangeOrder;
        // create petition
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

    function resolveByCourtOrder(uint256 _projectId) public {
        Project storage project = projects[_projectId];
        if(msg.sender != project.buyer && msg.sender != project.provider) revert Marketplace__OnlyBuyerOrProvider();
        if(project.status != Status.Disputed) revert Marketplace__ProjectIsNotDisputed();
        ICourt.Petition memory petition = COURT.getPetition(arbitrationCases[_projectId]);
        if(petition.phase != ICourt.Phase.Verdict && petition.phase != ICourt.Phase.DefaultJudgement) {
            revert Marketplace__CourtHasNotRuled();
        }
        if(block.timestamp < petition.verdictRenderedDate + APPEAL_PERIOD) revert Marketplace__AppealPeriodNotOver();
        project.status = Status.Resolved_CourtOrder;
        emit ResolvedByCourtOrder(_projectId, petition.petitionId);
    }

    function resolveDismissedCase(uint256 _projectId) public {
        Project storage project = projects[_projectId];
        if(msg.sender != project.buyer && msg.sender != project.provider) revert Marketplace__OnlyBuyerOrProvider();
        if(project.status != Status.Disputed) revert Marketplace__ProjectIsNotDisputed();
        ICourt.Petition memory petition = COURT.getPetition(arbitrationCases[_projectId]);
        if(petition.phase != ICourt.Phase.Dismissed) revert Marketplace__CourtHasNotDismissedCase();
        project.status = Status.Resolved_ArbitrationDismissed;
        emit ResolvedByDismissedCase(_projectId, petition.petitionId);
    }

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
        // if(p.status != Status.Discontinued && p.status != Status.Challenged) revert Marketplace__ChangeOrderCannotBeProposed();
        // if(activeChangeOrder(_projectId)) revert Marketplace__ChangeOrderAlreadyExists();
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

    function _validSettlement(uint256 _projectId) private {
        ICourt.Petition memory petition = COURT.getPetition(getArbitrationPetitionId(_projectId));
        if(petition.phase != ICourt.Phase.Discovery) revert Marketplace__ChangeOrderNotValid();
        COURT.settledExternally(petition.petitionId);
    }

    function proposeCounterOffer(
        uint256 _projectId,
        uint256 _adjustedProjectFee,
        uint256 _providerStakeForfeit,
        string memory _changeOrderDetailsURI
    )
        external
    {
        if(!activeChangeOrder(_projectId)) revert Marketplace__NoActiveChangeOrder();
        Project memory p = getProject(_projectId);
        // _propose will check status, all we need here is to check petition status for disputed
        if(p.status == Status.Disputed) {
            // INebulaiCourt.Petition memory petition = COURT.getPetition(arbitrationCases[_projectId]);
            // if(petition.phase != INebulaiCourt.Phase.Verdict) revert Marketplace__CourtHasNotRuled();
        }
        // create change order which will supercede any existing order
        _proposeChangeOrder(
            _projectId,
            _adjustedProjectFee,
            _providerStakeForfeit,
            _changeOrderDetailsURI
        );
    }

    ////////////////
    ///   UTIL   ///
    ////////////////

    function calculateNebulaiTxFee(uint256 _projectFee) public view returns (uint256) {
        uint256 txFee = (_projectFee * nebulaiTxFee) / 100;
        if(txFee < minimumTxFee) txFee = minimumTxFee;
        return txFee;
    }

    ////////////////////
    ///   INTERNAL   ///
    ////////////////////

    function _approveToken(address _token) private {
        isApprovedToken[_token] = true;
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

    ///////////////////
    ///   GETTERS   ///
    ///////////////////

    function getProject(uint256 _projectId) public view returns (Project memory) {
        // check if exists
        return projects[_projectId];
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

}
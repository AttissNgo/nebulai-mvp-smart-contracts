// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Interfaces/IWhitelist.sol";

contract MediatorPool {

    address public immutable GOVERNOR;
    IWhitelist public immutable WHITELIST;

    /**
     * @notice determines if a mediator can be drawn for mediation 
     * Active - the account can be drawn for cases
     * Paused - the account cannot be drawn for cases (mediator can re-activate)
     * Suspended - the account cannot be drawn for cases (only governor can re-activate)
     */
    enum MediatorStatus {
        Active, 
        Paused, 
        Suspended
    }

    /**
     * @dev stake is used in the weighted mediator drawing
     * @dev if stake falls below the minimum stake, mediator will not be eligible for drawing
     */
    mapping(address => uint256) private mediatorPoolStake;
    uint256 public minimumStake;
    address[] public mediators;
    mapping(address => bool) public isMediator;
    mapping(address => MediatorStatus) private mediatorStatus;

    /**
     * @dev used to pay additional mediators if there is a problem with a case
     */
    uint256 private mediationReserve;

    event MinimumStakeSet(uint256 minimumStake);
    event MediatorRegistered(address indexed mediator);
    event MediatorPaused(address indexed mediator);
    event MediatorReactivated(address indexed mediator);
    event MediatorSuspended(address indexed mediator);
    event MediatorReinstated(address indexed mediator);
    event StakeWithdrawn(address indexed mediator, uint256 withdrawAmount, uint256 totalStake);
    event Staked(address indexed mediator, uint256 stakeAmount, uint256 totalStake);
    event MediationReserveFunded(uint256 amount, address from);
    event MediationReserveWithdrawn(address recipient, uint256 amount);

    error MediatorPool__OnlyGovernor();
    error MediatorPool__OnlyWhitelisted();
    error MediatorPool__AlreadyRegistered();
    error MediatorPool__MinimumStakeNotMet();
    error MediatorPool__NotRegistered();
    error MediatorPool__MediatorNotActive();
    error MediatorPool__MediatorAlreadyActive();
    error MediatorPool__MediatorSuspended();
    error MediatorPool__MediatorAlreadySuspended();
    error MediatorPool__MediatorNotSuspended();
    error MediatorPool__InsufficientStake();
    error MediatorPool__TransferFailed();
    error MediatorPool__InsufficientReserve();

    modifier onlyGovernor() {
        if(msg.sender != GOVERNOR) revert MediatorPool__OnlyGovernor();
        _;
    }

    modifier onlyWhitelisted() {
        if(!WHITELIST.isApproved(msg.sender)) revert MediatorPool__OnlyWhitelisted();
        _;
    }

    modifier onlyRegistered() {
        if(!isMediator[msg.sender]) revert MediatorPool__NotRegistered();
        _;
    }

    constructor(address _governor, address _whitelist, uint256 _minimumStake) {
        GOVERNOR = _governor;
        WHITELIST = IWhitelist(_whitelist);
        minimumStake = _minimumStake;
    }

    /**
     * @notice mediator can be drawn for mediation cases
     */
    function registerAsMediator() external payable onlyWhitelisted {
        if(isMediator[msg.sender]) revert MediatorPool__AlreadyRegistered();
        if(msg.value < minimumStake) revert MediatorPool__MinimumStakeNotMet();
        mediatorPoolStake[msg.sender] += msg.value;
        mediators.push(msg.sender);
        isMediator[msg.sender] = true;
        emit MediatorRegistered(msg.sender);
    }

    /**
     * @notice mediator will no longer be drawn for mediation until reactivated
     */
    function pauseMediator() external onlyRegistered {
        if(mediatorStatus[msg.sender] != MediatorStatus.Active) revert MediatorPool__MediatorNotActive();
        mediatorStatus[msg.sender] = MediatorStatus.Paused;
        emit MediatorPaused(msg.sender);
    } 

    /**
     * @notice mediator will be eligible for drawing again
     */
    function reactivateMediator() external onlyRegistered {
        if(mediatorStatus[msg.sender] == MediatorStatus.Active) revert MediatorPool__MediatorAlreadyActive();
        if(mediatorStatus[msg.sender] == MediatorStatus.Suspended) revert MediatorPool__MediatorSuspended();
        mediatorStatus[msg.sender] = MediatorStatus.Active;
        emit MediatorReactivated(msg.sender);
    }

    /**
     * @notice add additional funds to stake to increase chances of being drawn for mediation
     */
    function stake() external payable onlyRegistered {
        mediatorPoolStake[msg.sender] += msg.value;
        emit Staked(msg.sender, msg.value, mediatorPoolStake[msg.sender]);
    }

    /**
     * @notice withdraw deposited mediator stake
     * @notice suspended mediators cannot withdraw stake
     */
    function withdrawStake(uint256 _withdrawAmount) external onlyRegistered {
        if(mediatorStatus[msg.sender] == MediatorStatus.Suspended) revert MediatorPool__MediatorSuspended();
        if(getMediatorStake(msg.sender) < _withdrawAmount) revert MediatorPool__InsufficientStake();
        mediatorPoolStake[msg.sender] -= _withdrawAmount;
        (bool success, ) = msg.sender.call{value: _withdrawAmount}("");
        if(!success) revert MediatorPool__TransferFailed();
        emit StakeWithdrawn(msg.sender, _withdrawAmount, mediatorPoolStake[msg.sender]);
    }

    /**
     * @notice reserve is used to pay additional mediators
     * @dev called by MediationService when mediator does not perform (fails to commit or reveal) 
     */
    function fundMediationReserve() external payable {
        mediationReserve += msg.value;
        emit MediationReserveFunded(msg.value, msg.sender);
    }

    //////////////////////
    ///   GOVERNANCE   ///
    //////////////////////

    function setMinimumStake(uint256 _minimumStake) external onlyGovernor {
        require(_minimumStake > 0);
        minimumStake = _minimumStake;
        emit MinimumStakeSet(_minimumStake);
    }

    /**
     * @notice makes mediator ineligible for drawing and freezes their stake until reinstatement
     */
    function suspendMediator(address _mediator) external onlyGovernor {
        if(!isMediator[_mediator]) revert MediatorPool__NotRegistered();
        if(mediatorStatus[_mediator] == MediatorStatus.Suspended) revert MediatorPool__MediatorAlreadySuspended();
        mediatorStatus[_mediator] = MediatorStatus.Suspended;
        emit MediatorSuspended(_mediator);
    }

    /**
     * @notice makes mediator eligible for drawing and allows them to withdraw their stake
     */
    function reinstateMediator(address _mediator) external onlyGovernor {
        if(!isMediator[_mediator]) revert MediatorPool__NotRegistered();
        if(mediatorStatus[_mediator] != MediatorStatus.Suspended) revert MediatorPool__MediatorNotSuspended();
        mediatorStatus[_mediator] = MediatorStatus.Active;
        emit MediatorReinstated(_mediator);
    }

    /**
     * @notice transfer MATIC from jury reserve
     * @param _recipient address to receive the transfer
     * @param _amount amount to transfer
     */
    function withdrawMediationReserve(address _recipient, uint256 _amount) external onlyGovernor {
        require(_amount > 0);
        if(_amount > mediationReserve) revert MediatorPool__InsufficientReserve();
        mediationReserve -= _amount;
        (bool success, ) = _recipient.call{value: _amount}("");
        if(!success) revert MediatorPool__TransferFailed();
        emit MediationReserveWithdrawn(_recipient, _amount);
    }

    ///////////////////
    ///   GETTERS   ///
    ///////////////////

    function isEligible(address _mediator) public view returns (bool) {
        if(!isMediator[_mediator]) return false;
        if(mediatorStatus[_mediator] != MediatorStatus.Active) return false;
        if(mediatorPoolStake[_mediator] < minimumStake) return false;
        return true;
    }

    function getMediator(uint256 _index) public view returns (address) {
        return mediators[_index];
    }

    function getMediatorStatus(address _mediator) public view returns (MediatorStatus) {
        return mediatorStatus[_mediator];
    }

    function getMediatorStake(address _mediator) public view returns (uint256) {
        return mediatorPoolStake[_mediator];
    }

    function mediatorPoolSize() public view returns (uint256) {
        return mediators.length;
    }

    function getMediationReserve() public view returns (uint256) {
        return mediationReserve;
    }

}
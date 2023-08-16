// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Interfaces/IWhitelist.sol";

contract JuryPool {

    address public immutable GOVERNOR;
    IWhitelist public immutable WHITELIST;

    /**
     * @notice determines if a juror can be drawn for arbitration 
     * Active - the account can be drawn for cases
     * Paused - the account cannot be drawn for cases (juror can re-activate)
     * Suspended - the account cannot be drawn for cases (only governor can re-activate)
     */
    enum JurorStatus {
        Active, 
        Paused, 
        Suspended
    }

    /**
     * @dev stake is used in the weighted juror drawing
     * @dev if stake falls below the minimum stake, juror will not be eligible for drawing
     */
    mapping(address => uint256) private juryPoolStake;
    uint256 public minimumStake;
    address[] public jurors;
    mapping(address => bool) public isJuror;
    mapping(address => JurorStatus) private jurorStatus;

    /**
     * @dev used to pay additional jurors if there is a problem with a case
     */
    uint256 private juryReserves;

    event MinimumStakeSet(uint256 minimumStake);
    event JurorRegistered(address indexed juror);
    event JurorPaused(address indexed juror);
    event JurorReactivated(address indexed juror);
    event JurorSuspended(address indexed juror);
    event JurorReinstated(address indexed juror);
    event StakeWithdrawn(address indexed juror, uint256 withdrawAmount, uint256 totalStake);
    event Staked(address indexed juror, uint256 stakeAmount, uint256 totalStake);
    event JuryReservesFunded(uint256 amount, address from);
    event JuryReservesWithdrawn(address recipient, uint256 amount);

    error JuryPool__OnlyGovernor();
    error JuryPool__OnlyWhitelisted();
    error JuryPool__AlreadyRegistered();
    error JuryPool__MinimumStakeNotMet();
    error JuryPool__NotRegistered();
    error JuryPool__JurorNotActive();
    error JuryPool__JurorAlreadyActive();
    error JuryPool__JurorSuspended();
    error JuryPool__JurorAlreadySuspended();
    error JuryPool__JurorNotSuspended();
    error JuryPool__InsufficientStake();
    error JuryPool__TransferFailed();
    error JuryPool__InsufficientReserves();

    modifier onlyGovernor() {
        if(msg.sender != GOVERNOR) revert JuryPool__OnlyGovernor();
        _;
    }

    modifier onlyWhitelisted() {
        if(!WHITELIST.isApproved(msg.sender)) revert JuryPool__OnlyWhitelisted();
        _;
    }

    modifier onlyRegistered() {
        if(!isJuror[msg.sender]) revert JuryPool__NotRegistered();
        _;
    }

    constructor(address _governor, address _whitelist, uint256 _minimumStake) {
        GOVERNOR = _governor;
        WHITELIST = IWhitelist(_whitelist);
        minimumStake = _minimumStake;
    }

    /**
     * @notice juror can be drawn for arbitration cases
     */
    function registerAsJuror() external payable onlyWhitelisted {
        if(isJuror[msg.sender]) revert JuryPool__AlreadyRegistered();
        if(msg.value < minimumStake) revert JuryPool__MinimumStakeNotMet();
        juryPoolStake[msg.sender] += msg.value;
        jurors.push(msg.sender);
        isJuror[msg.sender] = true;
        emit JurorRegistered(msg.sender);
    }

    /**
     * @notice juror will no longer be drawn for arbitration until reactivated
     */
    function pauseJuror() external onlyRegistered {
        if(jurorStatus[msg.sender] != JurorStatus.Active) revert JuryPool__JurorNotActive();
        jurorStatus[msg.sender] = JurorStatus.Paused;
        emit JurorPaused(msg.sender);
    } 

    /**
     * @notice juror will be eligible for drawing again
     */
    function reactivateJuror() external onlyRegistered {
        if(jurorStatus[msg.sender] == JurorStatus.Active) revert JuryPool__JurorAlreadyActive();
        if(jurorStatus[msg.sender] == JurorStatus.Suspended) revert JuryPool__JurorSuspended();
        jurorStatus[msg.sender] = JurorStatus.Active;
        emit JurorReactivated(msg.sender);
    }

    /**
     * @notice add additional funds to stake to increase chances of being drawn for arbitration
     */
    function stake() external payable onlyRegistered {
        juryPoolStake[msg.sender] += msg.value;
        emit Staked(msg.sender, msg.value, juryPoolStake[msg.sender]);
    }

    /**
     * @notice withdraw deposited juror stake
     * @notice suspended jurors cannot withdraw stake
     */
    function withdrawStake(uint256 _withdrawAmount) external onlyRegistered {
        if(jurorStatus[msg.sender] == JurorStatus.Suspended) revert JuryPool__JurorSuspended();
        if(getJurorStake(msg.sender) < _withdrawAmount) revert JuryPool__InsufficientStake();
        juryPoolStake[msg.sender] -= _withdrawAmount;
        (bool success, ) = msg.sender.call{value: _withdrawAmount}("");
        if(!success) revert JuryPool__TransferFailed();
        emit StakeWithdrawn(msg.sender, _withdrawAmount, juryPoolStake[msg.sender]);
    }

    /**
     * @notice reserves are used to pay additional jurors
     * @dev called by Court when juror does not perform (fails to commit or reveal) 
     */
    function fundJuryReserves() external payable {
        juryReserves += msg.value;
        emit JuryReservesFunded(msg.value, msg.sender);
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
     * @notice makes juror ineligible for drawing and freezes their stake until reinstatement
     */
    function suspendJuror(address _juror) external onlyGovernor {
        if(!isJuror[_juror]) revert JuryPool__NotRegistered();
        if(jurorStatus[_juror] == JurorStatus.Suspended) revert JuryPool__JurorAlreadySuspended();
        jurorStatus[_juror] = JurorStatus.Suspended;
        emit JurorSuspended(_juror);
    }

    /**
     * @notice makes juror eligible for drawing and allows them to withdraw their stake
     */
    function reinstateJuror(address _juror) external onlyGovernor {
        if(!isJuror[_juror]) revert JuryPool__NotRegistered();
        if(jurorStatus[_juror] != JurorStatus.Suspended) revert JuryPool__JurorNotSuspended();
        jurorStatus[_juror] = JurorStatus.Active;
        emit JurorReinstated(_juror);
    }

    /**
     * @notice transfer MATIC from jury reserves
     * @param _recipient address to receive the transfer
     * @param _amount amount to transfer
     */
    function withdrawJuryReserves(address _recipient, uint256 _amount) external onlyGovernor {
        require(_amount > 0);
        if(_amount > juryReserves) revert JuryPool__InsufficientReserves();
        juryReserves -= _amount;
        (bool success, ) = _recipient.call{value: _amount}("");
        if(!success) revert JuryPool__TransferFailed();
        emit JuryReservesWithdrawn(_recipient, _amount);
    }

    ///////////////////
    ///   GETTERS   ///
    ///////////////////

    function isEligible(address _juror) public view returns (bool) {
        if(!isJuror[_juror]) return false;
        if(jurorStatus[_juror] != JurorStatus.Active) return false;
        if(juryPoolStake[_juror] < minimumStake) return false;
        return true;
    }

    function getJuror(uint256 _index) public view returns (address) {
        return jurors[_index];
    }

    function getJurorStatus(address _juror) public view returns (JurorStatus) {
        return jurorStatus[_juror];
    }

    function getJurorStake(address _juror) public view returns (uint256) {
        return juryPoolStake[_juror];
    }

    function juryPoolSize() public view returns (uint256) {
        return jurors.length;
    }

    function getJuryReserves() public view returns (uint256) {
        return juryReserves;
    }

}
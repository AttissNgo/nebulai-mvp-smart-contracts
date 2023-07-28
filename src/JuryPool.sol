// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Interfaces/IWhitelist.sol";

contract JuryPool {

    address public immutable GOVERNOR;
    IWhitelist public immutable WHITELIST;

    enum JurorStatus {
        Active, // the account can be drawn for cases
        Paused, // the account cannot be drawn for cases (juror can re-activate - de-activated by self or due to inactivity)
        Suspended // the account cannot be drawn for cases (under investigation - only governor can re-activate)
    }

    struct Juror {
        address jurorAddress;
        JurorStatus jurorStatus;
        uint16 casesOffered;
        uint16 casesCompleted;
        uint8 majorityPercentage;
    }

    uint256 public minimumStake = 100 ether;
    mapping(address => uint256) private juryPoolStake;

    Juror[] public jurors;
    mapping(address => uint256) private jurorIndex;
    mapping(address => bool) public isJuror;

    // reserves for emergency juror drawing
    uint256 private juryReserves;

    event MinimumStakeSet(uint256 minimumStake);
    event JurorRegistered(address indexed juror, uint256 jurorIndex);
    event JurorPaused(address indexed juror, uint256 jurorIndex);
    event JurorReactivated(address indexed juror, uint256 indexed index);
    event JurorSuspended(address indexed juror, uint256 indexed index);
    event JurorReinstated(address indexed juror, uint256 indexed index);
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

    constructor(address _governor, address _whitelist) {
        GOVERNOR = _governor;
        WHITELIST = IWhitelist(_whitelist);

    }

    function registerAsJuror() external payable onlyWhitelisted returns (uint256) {
        if(isJuror[msg.sender]) revert JuryPool__AlreadyRegistered();
        if(msg.value < minimumStake) revert JuryPool__MinimumStakeNotMet();
        juryPoolStake[msg.sender] += msg.value;
        Juror memory juror;
        juror.jurorAddress = msg.sender;
        juror.jurorStatus = JurorStatus.Active;
        jurors.push(juror);
        uint256 index = jurors.length - 1;
        jurorIndex[msg.sender] = index;
        isJuror[msg.sender] = true;
        emit JurorRegistered(msg.sender, index);
        return index;
    }

    function pauseJuror() external onlyRegistered {
        uint256 index = getJurorIndex(msg.sender);
        Juror storage juror = jurors[index];
        if(juror.jurorStatus != JurorStatus.Active) revert JuryPool__JurorNotActive();
        juror.jurorStatus = JurorStatus.Paused;
        emit JurorPaused(juror.jurorAddress, index);
    } 

    function reactivateJuror() external onlyRegistered {
        uint256 index = getJurorIndex(msg.sender);
        Juror storage juror = jurors[index];
        if(juror.jurorStatus == JurorStatus.Active) revert JuryPool__JurorAlreadyActive();
        if(juror.jurorStatus == JurorStatus.Suspended) revert JuryPool__JurorSuspended();
        juror.jurorStatus = JurorStatus.Active;
        emit JurorReactivated(juror.jurorAddress, index);
    }

    function stake() external payable onlyRegistered {
        juryPoolStake[msg.sender] += msg.value;
        emit Staked(msg.sender, msg.value, juryPoolStake[msg.sender]);
    }

    function withdrawStake(uint256 _withdrawAmount) external onlyRegistered {
        if(getJurorStake(msg.sender) < _withdrawAmount) revert JuryPool__InsufficientStake();
        juryPoolStake[msg.sender] -= _withdrawAmount;
        (bool success, ) = msg.sender.call{value: _withdrawAmount}("");
        if(!success) revert JuryPool__TransferFailed();
        emit StakeWithdrawn(msg.sender, _withdrawAmount, juryPoolStake[msg.sender]);
    }

    function fundJuryReserves() external payable {
        juryReserves += msg.value;
        emit JuryReservesFunded(msg.value, msg.sender);
    }

    /////////////////
    ///   ADMIN   ///
    /////////////////

    function setMinimumStake(uint256 _minimumStake) external onlyGovernor {
        require(_minimumStake > 0);
        minimumStake = _minimumStake;
        emit MinimumStakeSet(_minimumStake);
    }

    function suspendJuror(address _juror) external onlyGovernor {
        if(!isJuror[_juror]) revert JuryPool__NotRegistered();
        uint256 index = getJurorIndex(_juror);
        Juror storage juror = jurors[index];
        if(juror.jurorStatus == JurorStatus.Suspended) revert JuryPool__JurorAlreadySuspended();
        juror.jurorStatus = JurorStatus.Suspended;
        emit JurorSuspended(juror.jurorAddress, index);
    }

    function reinstateJuror(address _juror) external onlyGovernor {
        if(!isJuror[_juror]) revert JuryPool__NotRegistered();
        uint256 index = getJurorIndex(_juror);
        Juror storage juror = jurors[index];
        if(juror.jurorStatus != JurorStatus.Suspended) revert JuryPool__JurorNotSuspended();
        juror.jurorStatus = JurorStatus.Active;
        emit JurorReinstated(juror.jurorAddress, index);
    }

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

    function getJuror(uint256 _index) public view returns (Juror memory) {
        return jurors[_index];
    }

    function getJurorStatus(address _juror) public view returns (JurorStatus) {
        Juror memory juror = getJuror(jurorIndex[_juror]);
        return juror.jurorStatus;
    }

    function getJurorIndex(address _juror) public view returns (uint256) {
        return jurorIndex[_juror];
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
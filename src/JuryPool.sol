// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Interfaces/IWhitelist.sol";

contract JuryPool {

    address public immutable GOVERNOR;
    IWhitelist public immutable WHITELIST;

    enum JurorStatus {
        Unregistered, // init prop, used to check if Juror exists
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

    event MinimumStakeSet(uint256 minimumStake);
    event JurorRegistered(address indexed juror, uint256 jurorIndex);

    error JuryPool__OnlyGovernor();
    error JuryPool__OnlyWhitelisted();
    error JuryPool__AlreadyRegistered();
    error JuryPool__MinimumStakeNotMet();

    modifier onlyGovernor() {
        if(msg.sender != GOVERNOR) revert JuryPool__OnlyGovernor();
        _;
    }

    modifier onlyWhitelisted() {
        if(!WHITELIST.isApproved(msg.sender)) revert JuryPool__OnlyWhitelisted();
        _;
    }

    constructor(address _governor, address _whitelist) {
        GOVERNOR = _governor;
        WHITELIST = IWhitelist(_whitelist);

    }

    function registerAsJuror() external payable onlyWhitelisted returns (uint256) {
        if(isJuror[msg.sender]) revert JuryPool__AlreadyRegistered();
        if(msg.value < minimumStake) revert JuryPool__MinimumStakeNotMet();
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

    
    /////////////////
    ///   ADMIN   ///
    /////////////////

    function setMinimumStake(uint256 _minimumStake) external onlyGovernor {
        require(_minimumStake > 0);
        minimumStake = _minimumStake;
        emit MinimumStakeSet(_minimumStake);
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

    // function getJurorIndex(address _juror) public view returns (uint256) {
    //     return jurorIndex[_juror];
    // }

    function getJurorStake(address _juror) public view returns (uint256) {
        return juryPoolStake[_juror];
    }

    function juryPoolSize() public view returns (uint256) {
        return jurors.length;
    }

}
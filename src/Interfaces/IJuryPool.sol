// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IJuryPool {

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

    function getJuror(uint256 _index) external view returns (Juror memory);
    function juryPoolSize() external view returns (uint256);
    function getJurorStake(address _juror) external view returns (uint256);
}
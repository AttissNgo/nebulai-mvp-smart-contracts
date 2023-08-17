// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IJuryPool {

    enum JurorStatus {
        Active, 
        Paused, 
        Suspended 
    }

    function fundJuryReserve() external payable;
    function getJuror(uint256 _index) external view returns (address);
    function juryPoolSize() external view returns (uint256);
    function getJurorStatus(address _juror) external view returns (JurorStatus);
    function isEligible(address _juror) external view returns (bool);
    function getJurorStake(address _juror) external view returns (uint256);
}
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IMediatorPool {

    enum MediatorStatus {
        Active, 
        Paused, 
        Suspended 
    }
    
    function fundMediationReserve() external payable;
    function getMediator(uint256 _index) external view returns (address);
    function mediatorPoolSize() external view returns (uint256);
    function getMediatorStatus(address _mediator) external view returns (MediatorStatus);
    function isEligible(address _mediator) external view returns (bool);
    function getMediatorStake(address _mediator) external view returns (uint256);
}
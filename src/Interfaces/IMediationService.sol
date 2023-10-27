// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../DataStructuresLibrary.sol";

interface IMediationService {
    function createDispute(
        uint256 _projectId,
        uint256 _adjustedProjectFee,
        uint256 _providerStakeForfeit,
        address _claimant,
        address _respondent
    ) external returns (uint256);
    function appeal(uint256 _projectId) external returns (uint256);
    function settledExternally(uint256 _disputeId) external;
    function getDispute(uint256 _disputeId) external view returns (DataStructuresLibrary.Dispute memory);


}
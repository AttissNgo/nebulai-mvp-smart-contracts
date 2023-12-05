// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../DataStructuresLibrary.sol";

interface IMarketplace {
    function getDisputeId(uint256 _projectId) external view returns (uint256);
    function isDisputed(uint256 _projectId) external view returns (bool);
    function receiveCommission(uint256 _projectId, uint256 _commission) external;
    function getProjectStatus(uint256 _projectId) external view returns (DataStructuresLibrary.Status);
    function getChangeOrders(uint256 _projectId) external view returns (DataStructuresLibrary.ChangeOrder[] memory);
    function getActiveChangeOrder(uint256 _projectId) external view returns (DataStructuresLibrary.ChangeOrder memory);
    function escrowWithdrawnEvent(uint256 _projectId, address _user, uint256 _amount, uint256 _commissionPaid) external;
}
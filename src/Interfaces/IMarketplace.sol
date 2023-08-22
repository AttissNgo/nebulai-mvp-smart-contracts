// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IMarketplace {

    enum Status { 
        Created, 
        Cancelled, 
        Active, 
        Discontinued, 
        Completed, 
        Approved, 
        Challenged, 
        Disputed, 
        Appealed, 
        Resolved_ChangeOrder, 
        Resolved_CourtOrder, 
        Resolved_DelinquentPayment, 
        Resolved_ArbitrationDismissed 
    }

    struct ChangeOrder {
        uint256 projectId;
        uint256 dateProposed;
        address proposedBy;
        uint256 adjustedProjectFee;
        uint256 providerStakeForfeit;
        bool buyerApproval;
        bool providerApproval;
        string detailsURI;
    }

    function getArbitrationPetitionId(uint256 _projectId) external view returns (uint256);
    function isDisputed(uint256 _projectId) external view returns (bool);
    function receiveCommission(uint256 _projectId, uint256 _commission) external;
    function getProjectStatus(uint256 _projectId) external view returns (Status);
    function getChangeOrder(uint256 _projectId) external view returns (ChangeOrder memory);
}
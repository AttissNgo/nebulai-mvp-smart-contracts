// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IMarketplace {

    enum Status { 
        Created, // project is created but has not been started - Escrow holds project fee
        Cancelled, // project is withdrawn by buyer before provider begins work
        Active, // provider has started work - Provider must stake in ESCROW to initiate this status
        Discontinued, // either party quits - change order period begins
        Completed, // provider claims project is complete
        Approved, // buyer is satisfied and project fee is released to provider, Project is closed
        Challenged, // buyer requests full or partial refund via Change Order - provider has a chance to accept OR go to aribtration 
        Disputed, // Change Order NOT accepted by provider -> Project goes to arbitration
        Appealed, // new arbitration case is opened
        Resolved_ChangeOrder, // escrow releases according to change order
        Resolved_CourtOrder, // escrow releases according to court petition
        Resolved_DelinquentPayment, // escrow releases according to original agreement
        Resolved_ArbitrationDismissed // escrow releases according to original agreement
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
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract DataStructuresLibrary {

    ///////////////////////////////////////
    ///   MARKETPLACE DATA STRUCTURES   ///
    ///////////////////////////////////////

    /**
     * @notice the state of a Project
     * Created - Escrow holds project fee, but work has not started
     * Cancelled - project is withdrawn by buyer before provider begins work 
     * Active - provider has staked in Escrow and has begun work 
     * Discontinued - either party quits and a change order period begins to handle partial payment
     * Completed - provider claims project is complete and is awaiting buyer approval
     * Approved - buyer is satisfied, escrow will release project fee to provider, Project is closed
     * Challenged - buyer is unsatisfied and submits a Change Order - provider has a chance to accept OR go to arbitration 
     * Disputed - Change Order NOT accepted by provider -> Project goes to arbitration
     * Appealed - the correctness of the court's decision is challenged -> a new arbitration case is opened
     * Resolved_ChangeOrder - escrow releases funds according to change order
     * Resolved_CourtOrder - escrow releases funds according to court petition
     * Resolved_DelinquentPayment - escrow releases funds according to original agreement
     * Resolved_ArbitrationDismissed - escrow releases funds according to original agreement
     */
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

    /**
     * @notice details of an agreement between a buyer and service provider
     */
    struct Project {
        uint256 projectId;
        address buyer;
        address provider;
        address escrow;
        address paymentToken;
        uint256 projectFee;
        uint256 providerStake;
        uint256 dueDate;
        uint256 reviewPeriodLength;
        uint256 dateCompleted;
        uint256 changeOrderPeriodInitiated;
        uint256 nebulaiTxFee;
        Status status;
        string detailsURI;
    }

    /**
     * @notice proposal to alter payment details of a Project
     */
    struct ChangeOrder {
        uint256 changeOrderId;
        uint256 projectId;
        uint256 dateProposed;
        address proposedBy;
        uint256 adjustedProjectFee;
        uint256 providerStakeForfeit;
        bool active;
        bool buyerApproval;
        bool providerApproval;
        string detailsURI;
    }

    /////////////////////////////////
    ///   COURT DATA STRUCTURES   ///
    /////////////////////////////////

    /**
     * @notice the stage of a petition
     * Discovery - evidence may be submitted (after paying arbitration fee)
     * JurySelection - jury is drawn randomly and drawn jurors may accept the case
     * Voting - jurors commit a hidden vote
     * Ruling - jurors reveal their votes
     * Verdict - all votes have been counted and a ruling is made
     * DefaultJudgement - one party does not pay arbitration fee, petition is ruled in favor of paying party
     * Dismissed - case is invalid and Marketplace reverts to original project conditions
     * SettledExternally - case was settled by change order in Marketplace and arbitration does not progress
     */
    enum Phase {
        Discovery,
        JurySelection, 
        Voting, 
        Ruling, 
        Verdict,
        DefaultJudgement, 
        Dismissed, 
        SettledExternally 
    }

    struct Petition {
        uint256 petitionId;
        uint256 projectId;
        uint256 adjustedProjectFee;
        uint256 providerStakeForfeit;
        address plaintiff;
        address defendant;
        uint256 arbitrationFee;
        bool feePaidPlaintiff;
        bool feePaidDefendant;
        uint256 discoveryStart;
        uint256 selectionStart;
        uint256 votingStart;
        uint256 rulingStart;
        uint256 verdictRenderedDate;
        bool isAppeal;
        bool petitionGranted;
        Phase phase;
        string[] evidence;
    }
}
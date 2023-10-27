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
     * Challenged - buyer is unsatisfied and submits a Change Order - provider has a chance to accept OR go to mediation 
     * Disputed - Change Order NOT accepted by provider -> Project goes to mediation
     * Appealed - the correctness of the mediationService's decision is challenged -> a new mediation case is opened
     * Resolved_ChangeOrder - escrow releases funds according to change order
     * Resolved_Mediation - escrow releases funds according to mediationService dispute
     * Resolved_DelinquentPayment - escrow releases funds according to original agreement
     * Resolved_MediationDismissed - escrow releases funds according to original agreement
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
        Resolved_Mediation, 
        Resolved_DelinquentPayment, 
        Resolved_MediationDismissed 
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
    ///   MEDIATION_SERVICE DATA STRUCTURES   ///
    /////////////////////////////////

    /**
     * @notice the stage of a dispute
     * Disclosure - evidence may be submitted (after paying mediation fee)
     * PanelSelection - panel is drawn randomly and drawn mediators may accept the case
     * Voting - mediators commit a hidden vote
     * Determination - mediators reveal their votes
     * Decision - all votes have been counted and a determination is made
     * DefaultDecision - one party does not pay mediation fee, dispute is ruled in favor of paying party
     * Dismissed - case is invalid and Marketplace reverts to original project conditions
     * SettledExternally - case was settled by change order in Marketplace and mediation does not progress
     */
    enum Phase {
        Disclosure,
        PanelSelection, 
        Voting, 
        Determination, 
        Decision,
        DefaultDecision, 
        Dismissed, 
        SettledExternally 
    }

    struct Dispute {
        uint256 disputeId;
        uint256 projectId;
        uint256 adjustedProjectFee;
        uint256 providerStakeForfeit;
        address claimant;
        address respondent;
        uint256 mediationFee;
        bool feePaidClaimant;
        bool feePaidRespondent;
        uint256 disclosureStart;
        uint256 selectionStart;
        uint256 votingStart;
        uint256 determinationStart;
        uint256 decisionRenderedDate;
        bool isAppeal;
        bool granted;
        Phase phase;
        string[] evidence;
    }
}
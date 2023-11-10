// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/Interfaces/IEscrow.sol";
import "forge-std/console.sol";

contract MediationServiceDisputeTest is Test, TestSetup {

    event DisputeCreated(uint256 indexed disputeId, uint256 projectId);
    event MediationFeePaid(uint256 indexed disputeId, address indexed user);
    event PanelSelectionInitiated(uint256 indexed disputeId, uint256 requestId);
    event CaseDismissed(uint256 indexed disputeId);
    event DefaultDecisionEntered(uint256 indexed disputeId, address indexed claimedBy, bool decision);
    event SettledExternally(uint256 indexed disputeId);
    event MediationFeeReclaimed(uint256 indexed disputeId, address indexed claimedBy, uint256 amount);
    event AppealCreated(uint256 indexed disputeId, uint256 indexed originalDisputeId, uint256 projectId);

    function setUp() public {
        _setUp();
        _whitelistUsers();
        _registerMediators();
        _initializeTestProjects();
        _initializeMediationProjects();
    }

    function test_createDispute() public {
        Project memory project = marketplace.getProject(id_challenged_ERC20);
        vm.expectEmit(true, false, false, true);
        emit DisputeCreated(mediationService.disputeIds() + 1, project.projectId);
        _disputeProject(project.projectId, changeOrderAdjustedProjectFee, changeOrderProviderStakeForfeit);
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(project.projectId));
        assertEq(dispute.disputeId, marketplace.getDisputeId(project.projectId));
        assertEq(dispute.projectId, project.projectId);
        assertEq(dispute.adjustedProjectFee, changeOrderAdjustedProjectFee);
        assertEq(dispute.providerStakeForfeit, changeOrderProviderStakeForfeit);
        assertEq(dispute.claimant, project.buyer);
        assertEq(dispute.respondent, project.provider);
        assertEq(dispute.mediationFee, mediationService.calculateMediationFee(false));
        assertEq(dispute.feePaidClaimant, false);
        assertEq(dispute.feePaidRespondent, false);
        assertEq(dispute.disclosureStart, block.timestamp);
        assertEq(dispute.selectionStart, 0);
        assertEq(dispute.votingStart, 0);
        assertEq(dispute.decisionRenderedDate, 0);
        assertEq(dispute.isAppeal, false);
        assertEq(dispute.granted, false);
        assertEq(uint(dispute.phase), uint(Phase.Disclosure));
        assertEq(dispute.evidence.length, 0);
    }

    function test_payMediationFee() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_disclosure_ERC20));
        assertEq(dispute.feePaidClaimant, false);
        assertEq(dispute.feePaidRespondent, false);
        assertEq(dispute.evidence.length, 0);
        assertEq(mediationService.getFeesHeld(dispute.disputeId), 0);

        // claimant pays fee & submits evidence
        vm.expectEmit(true, true, false, false);
        emit MediationFeePaid(dispute.disputeId, dispute.claimant);
        vm.prank(dispute.claimant);
        mediationService.payMediationFee{value: dispute.mediationFee}(dispute.disputeId, evidence1);

        // data recorded correctly in dispute
        dispute = mediationService.getDispute(dispute.disputeId);
        assertEq(dispute.feePaidClaimant, true);
        assertEq(dispute.evidence.length, evidence1.length);
        assertEq(mediationService.getFeesHeld(dispute.disputeId), dispute.mediationFee);   

        // claimant pays fee & submits evidence, triggering _selectPanel() and VRF request
        vm.expectEmit(true, true, false, false);
        emit MediationFeePaid(dispute.disputeId, dispute.respondent);
        vm.expectEmit(true, false, false, false /* request ID unknown at this time */);
        emit PanelSelectionInitiated(dispute.disputeId, 42);
        vm.recordLogs();
        vm.prank(dispute.respondent);
        mediationService.payMediationFee{value: dispute.mediationFee}(dispute.disputeId, evidence2);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[2].data));
        vrf.fulfillRandomWords(requestId, address(mediationService));

        // data recorded correctly in dispute
        dispute = mediationService.getDispute(dispute.disputeId);
        assertEq(dispute.feePaidRespondent, true);
        assertEq(dispute.evidence.length, evidence1.length + evidence2.length);
        assertEq(mediationService.getFeesHeld(dispute.disputeId), dispute.mediationFee + dispute.mediationFee);  

        // mediators have been drawn
        assertEq(uint(dispute.phase), uint(Phase.PanelSelection));
        assertEq(dispute.selectionStart, block.timestamp);
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        assertEq(panel.drawnMediators.length, mediationService.mediatorsNeeded(dispute.disputeId) * 3);
    }

    function test_payMediationFee_revert() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_disclosure_ERC20));
        // not disputant 
        vm.expectRevert(MediationService.MediationService__OnlyDisputant.selector);
        vm.prank(zorro);
        mediationService.payMediationFee{value: dispute.mediationFee}(dispute.disputeId, evidence1);
        // insufficient amount
        vm.expectRevert(MediationService.MediationService__InsufficientAmount.selector);
        vm.prank(dispute.claimant);
        mediationService.payMediationFee{value: dispute.mediationFee - 1}(dispute.disputeId, evidence1);
        // fee already paid
        vm.prank(dispute.claimant);
        mediationService.payMediationFee{value: dispute.mediationFee}(dispute.disputeId, evidence1);
        vm.expectRevert(MediationService.MediationService__MediationFeeAlreadyPaid.selector);
        vm.prank(dispute.claimant);
        mediationService.payMediationFee{value: dispute.mediationFee}(dispute.disputeId, evidence1);
    }

    function test_submitAdditionalEvidence() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_panelSelection_ERC20));
        uint256 evidenceLengthBefore = dispute.evidence.length;

        vm.prank(dispute.claimant);
        mediationService.submitAdditionalEvidence(dispute.disputeId, evidence1);

        dispute = mediationService.getDispute(dispute.disputeId);    
        assertEq(dispute.evidence.length, evidenceLengthBefore + evidence1.length);
    }

    function test_submitAdditionalEvidence_revert() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_disclosure_MATIC));
        // not disputant 
        vm.expectRevert(MediationService.MediationService__OnlyDisputant.selector);
        vm.prank(zorro);
        mediationService.submitAdditionalEvidence(dispute.disputeId, evidence1);
        // mediation fee not paid
        assertEq(dispute.feePaidRespondent, false);
        vm.expectRevert(MediationService.MediationService__MediationFeeNotPaid.selector);
        vm.prank(dispute.respondent);
        mediationService.submitAdditionalEvidence(dispute.disputeId, evidence1);
        // wrong phase!
        dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_confirmedPanel_MATIC));
        vm.expectRevert(MediationService.MediationService__EvidenceCanNoLongerBeSubmitted.selector);
        vm.prank(dispute.respondent);
        mediationService.submitAdditionalEvidence(dispute.disputeId, evidence1);
    }

    function test_dismissUnpaidCase() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_disclosure_MATIC));
        assertTrue(!dispute.feePaidRespondent && !dispute.feePaidClaimant);
        vm.warp(block.timestamp + mediationService.DISCLOSURE_PERIOD() + 1);

        vm.expectEmit(true, false, false, false);
        emit CaseDismissed(dispute.disputeId);
        mediationService.dismissUnpaidCase(dispute.disputeId);

        dispute = mediationService.getDispute(dispute.disputeId);
        assertEq(uint(dispute.phase), uint(Phase.Dismissed));
    }

    function test_dismissUnpaidCase_revert() public {
        // nonexistant dispute
        vm.expectRevert(MediationService.MediationService__DisputeDoesNotExist.selector);
        mediationService.dismissUnpaidCase(10000000);
        // fees not overdue (still within DISCLOSURE_PERIOD)
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_disclosure_ERC20));
        vm.expectRevert(MediationService.MediationService__FeesNotOverdue.selector);
        mediationService.dismissUnpaidCase(dispute.disputeId);
        // at least one party has paid mediation fee
        vm.warp(block.timestamp + mediationService.DISCLOSURE_PERIOD() + 1);
        vm.prank(dispute.respondent);
        mediationService.payMediationFee{value: dispute.mediationFee}(dispute.disputeId, evidence1);
        vm.expectRevert(MediationService.MediationService__MediationFeeAlreadyPaid.selector);
        mediationService.dismissUnpaidCase(dispute.disputeId);
    }

    function test_requestDefaultDecision() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_disclosure_ERC20));
        vm.prank(dispute.claimant);
        mediationService.payMediationFee{value: dispute.mediationFee}(dispute.disputeId, evidence1);
        uint256 reclaimAmount = mediationService.getFeesHeld(dispute.disputeId);
        uint256 claimantBalBefore = dispute.claimant.balance;
        uint256 mediationServiceBalBefore = address(mediationService).balance;
        vm.warp(block.timestamp + mediationService.DISCLOSURE_PERIOD() + 1);

        vm.expectEmit(true, true, false, true);
        emit DefaultDecisionEntered(dispute.disputeId, dispute.claimant, true);
        vm.prank(dispute.claimant);
        mediationService.requestDefaultDecision(dispute.disputeId);

        dispute = mediationService.getDispute(dispute.disputeId);
        assertEq(uint(dispute.phase), uint(Phase.DefaultDecision));
        assertEq(dispute.granted, true);
        assertEq(mediationService.getFeesHeld(dispute.disputeId), 0);
        assertEq(dispute.claimant.balance, claimantBalBefore + reclaimAmount);
        assertEq(address(mediationService).balance, mediationServiceBalBefore - reclaimAmount);

        // again but this time respondent pays
        dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_disclosure_MATIC));
        vm.prank(dispute.respondent);
        mediationService.payMediationFee{value: dispute.mediationFee}(dispute.disputeId, evidence1);
        reclaimAmount = mediationService.getFeesHeld(dispute.disputeId);
        uint256 respondentBalBefore = dispute.respondent.balance;
        mediationServiceBalBefore = address(mediationService).balance;

        vm.expectEmit(true, true, false, true);
        emit DefaultDecisionEntered(dispute.disputeId, dispute.respondent, false);
        vm.prank(dispute.respondent);
        mediationService.requestDefaultDecision(dispute.disputeId);

        dispute = mediationService.getDispute(dispute.disputeId);
        assertEq(uint(dispute.phase), uint(Phase.DefaultDecision));
        assertEq(dispute.granted, false);
        assertEq(mediationService.getFeesHeld(dispute.disputeId), 0);
        assertEq(dispute.respondent.balance, respondentBalBefore + reclaimAmount);
        assertEq(address(mediationService).balance, mediationServiceBalBefore - reclaimAmount);
    }

    function test_requestDefaultDecision_revert() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_disclosure_MATIC));
        vm.prank(dispute.claimant);
        mediationService.payMediationFee{value: dispute.mediationFee}(dispute.disputeId, evidence1);
        // in disclosure, but fees not overdue (within DISCLOSURE_PERIOD)
        vm.expectRevert(MediationService.MediationService__FeesNotOverdue.selector);
        vm.prank(dispute.claimant);
        mediationService.requestDefaultDecision(dispute.disputeId);
        // mediation fee not paid
        vm.warp(block.timestamp + mediationService.DISCLOSURE_PERIOD() + 1);
        vm.expectRevert(MediationService.MediationService__MediationFeeNotPaid.selector);
        vm.prank(dispute.respondent);
        mediationService.requestDefaultDecision(dispute.disputeId);
        // not disputant
        vm.expectRevert(MediationService.MediationService__OnlyDisputant.selector);
        vm.prank(zorro);
        mediationService.requestDefaultDecision(dispute.disputeId);
        // wrong phase
        dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_panelSelection_MATIC));
        vm.expectRevert(MediationService.MediationService__OnlyDuringDisclosure.selector);
        vm.prank(dispute.claimant);
        mediationService.requestDefaultDecision(dispute.disputeId);
    }

    function test_settledExternally() public {
        Project memory project = marketplace.getProject(id_mediation_disclosure_ERC20);
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(project.projectId));
        vm.prank(project.provider);
        marketplace.proposeSettlement(
            project.projectId,
            settlementAdjustedProjectFee,
            settlementProviderStakeForfeit,
            "ipfs://settlementDetails"
        );

        vm.expectEmit(true, false, false, false);
        emit SettledExternally(dispute.disputeId);
        vm.prank(project.buyer);
        marketplace.approveChangeOrder(project.projectId);

        dispute = mediationService.getDispute(dispute.disputeId);
        assertEq(uint(dispute.phase), uint(Phase.SettledExternally));

    }
 
    function test_reclaimMediationFee() public {
        bool[3] memory voteInputs = [false, false, true];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customReveal(id_mediation_confirmedPanel_MATIC, votes, true);
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_confirmedPanel_MATIC));
        assertEq(uint(dispute.phase), uint(Phase.Decision));
        assertEq(dispute.granted, false);
        assertEq(mediationService.getFeesHeld(dispute.disputeId), dispute.mediationFee);
        uint256 respondentBalBefore = dispute.respondent.balance;
        uint256 mediationServiceBalBefore = address(mediationService).balance;
        
        vm.expectEmit(true, true, false, true);
        emit MediationFeeReclaimed(dispute.disputeId, dispute.respondent, dispute.mediationFee);
        vm.prank(dispute.respondent);
        mediationService.reclaimMediationFee(dispute.disputeId);

        assertEq(mediationService.getFeesHeld(dispute.disputeId), 0);
        assertEq(dispute.respondent.balance, respondentBalBefore + dispute.mediationFee);
        assertEq(address(mediationService).balance, mediationServiceBalBefore - dispute.mediationFee);


        // once again, but with a granted dispute
        voteInputs = [false, true, true];
        votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customReveal(id_mediation_confirmedPanel_ERC20, votes, true);
        dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_confirmedPanel_ERC20));
        assertEq(uint(dispute.phase), uint(Phase.Decision));
        assertEq(dispute.granted, true);
        assertEq(mediationService.getFeesHeld(dispute.disputeId), dispute.mediationFee);
        uint256 claimantBalBefore = dispute.claimant.balance;
        mediationServiceBalBefore = address(mediationService).balance;
        
        vm.expectEmit(true, true, false, true);
        emit MediationFeeReclaimed(dispute.disputeId, dispute.claimant, dispute.mediationFee);
        vm.prank(dispute.claimant);
        mediationService.reclaimMediationFee(dispute.disputeId);

        assertEq(mediationService.getFeesHeld(dispute.disputeId), 0);
        assertEq(dispute.claimant.balance, claimantBalBefore + dispute.mediationFee);
        assertEq(address(mediationService).balance, mediationServiceBalBefore - dispute.mediationFee);
    }

    function test_reclaimMediationFee_revert() public {
        // wrong phase
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_confirmedPanel_MATIC));
        vm.expectRevert(MediationService.MediationService__MediationFeeCannotBeReclaimed.selector);
        vm.prank(dispute.claimant);
        mediationService.reclaimMediationFee(dispute.disputeId);
        
        bool[3] memory voteInputs = [false, false, true];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customReveal(id_mediation_confirmedPanel_MATIC, votes, true);
        dispute = mediationService.getDispute(dispute.disputeId);
        
        // not disputant
        vm.expectRevert(MediationService.MediationService__OnlyDisputant.selector);
        vm.prank(admin1);
        mediationService.reclaimMediationFee(dispute.disputeId);
        // not prevailing party 
        assertEq(dispute.granted, false);
        vm.expectRevert(MediationService.MediationService__OnlyPrevailingParty.selector);
        vm.prank(dispute.claimant);
        mediationService.reclaimMediationFee(dispute.disputeId);
        // settlement - mediation fee NOT paid
        Project memory project = marketplace.getProject(id_mediation_disclosure_ERC20);
        vm.prank(project.provider);
        marketplace.proposeSettlement(
            project.projectId,
            settlementAdjustedProjectFee,
            settlementProviderStakeForfeit,
            "ipfs://settlementDetails"
        );
        vm.prank(project.buyer);
        marketplace.approveChangeOrder(project.projectId);
        dispute = mediationService.getDispute(marketplace.getDisputeId(project.projectId));
        assertEq(dispute.feePaidRespondent, false);
        vm.expectRevert(MediationService.MediationService__MediationFeeNotPaid.selector);
        vm.prank(dispute.respondent);
        mediationService.reclaimMediationFee(dispute.disputeId);
    }

    function test_setMediatorFlatFee() public {
        assertEq(mediationService.mediatorFlatFee(), 20 ether);
        bytes memory data = abi.encodeWithSignature("setMediatorFlatFee(uint256)", 100 ether);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(mediationService), 0, data);
        util_executeGovernorTx(txIndex);

        assertEq(mediationService.mediatorFlatFee(), 100 ether);
    }

    function test_setMediatorFlatFee_revert() public {
        bytes memory data = abi.encodeWithSignature("setMediatorFlatFee(uint256)", 0);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(mediationService), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        vm.expectRevert();
        vm.prank(admin3);
        governor.signTransaction(txIndex);
    }

    function test_appeal() public {
        uint256 currentDisputeId = mediationService.disputeIds();
        Project memory project = marketplace.getProject(id_mediation_disclosure_ERC20);
        Dispute memory oldDispute = mediationService.getDispute(marketplace.getDisputeId(project.projectId));
        _disclosureToResolved(project.projectId, true);

        vm.expectEmit(true, true, false, true);
        emit AppealCreated(currentDisputeId + 1, marketplace.getDisputeId(project.projectId), project.projectId);
        vm.prank(project.provider);
        uint256 newDisputeId = marketplace.appealDecision(project.projectId);

        // new dispute created
        Dispute memory newDispute = mediationService.getDispute(newDisputeId);
        assertEq(newDispute.disputeId, newDisputeId);
        assertEq(newDispute.projectId, project.projectId);
        assertEq(newDispute.adjustedProjectFee, oldDispute.adjustedProjectFee);
        assertEq(newDispute.providerStakeForfeit, oldDispute.providerStakeForfeit);
        assertEq(newDispute.claimant, oldDispute.claimant);
        assertEq(newDispute.respondent, oldDispute.respondent);
        assertEq(newDispute.isAppeal, true);
        assertEq(newDispute.mediationFee, mediationService.calculateMediationFee(newDispute.isAppeal));
        assertEq(newDispute.disclosureStart, block.timestamp);
    }

}
        

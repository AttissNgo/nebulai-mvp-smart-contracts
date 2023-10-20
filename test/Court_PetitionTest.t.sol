// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/Interfaces/IEscrow.sol";
import "forge-std/console.sol";

contract CourtPetitionTest is Test, TestSetup {

    event PetitionCreated(uint256 indexed petitionId, uint256 projectId);
    event ArbitrationFeePaid(uint256 indexed petitionId, address indexed user);
    event JurySelectionInitiated(uint256 indexed petitionId, uint256 requestId);
    event CaseDismissed(uint256 indexed petitionId);
    event DefaultJudgementEntered(uint256 indexed petitionId, address indexed claimedBy, bool verdict);
    event SettledExternally(uint256 indexed petitionId);
    event ArbitrationFeeReclaimed(uint256 indexed petitionId, address indexed claimedBy, uint256 amount);

    function setUp() public {
        _setUp();
        _whitelistUsers();
        _registerJurors();
        _initializeTestProjects();
        _initializeArbitrationProjects();
    }

    function test_createPetition() public {
        Project memory project = marketplace.getProject(id_challenged_ERC20);
        vm.expectEmit(true, false, false, true);
        emit PetitionCreated(court.petitionIds() + 1, project.projectId);
        _disputeProject(project.projectId, changeOrderAdjustedProjectFee, changeOrderProviderStakeForfeit);
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(project.projectId));
        assertEq(petition.petitionId, marketplace.getArbitrationPetitionId(project.projectId));
        assertEq(petition.projectId, project.projectId);
        assertEq(petition.adjustedProjectFee, changeOrderAdjustedProjectFee);
        assertEq(petition.providerStakeForfeit, changeOrderProviderStakeForfeit);
        assertEq(petition.plaintiff, project.buyer);
        assertEq(petition.defendant, project.provider);
        assertEq(petition.arbitrationFee, court.calculateArbitrationFee(false));
        assertEq(petition.feePaidPlaintiff, false);
        assertEq(petition.feePaidDefendant, false);
        assertEq(petition.discoveryStart, block.timestamp);
        assertEq(petition.selectionStart, 0);
        assertEq(petition.votingStart, 0);
        assertEq(petition.verdictRenderedDate, 0);
        assertEq(petition.isAppeal, false);
        assertEq(petition.petitionGranted, false);
        assertEq(uint(petition.phase), uint(Phase.Discovery));
        assertEq(petition.evidence.length, 0);
    }

    function test_payArbitrationFee() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_discovery_ERC20));
        assertEq(petition.feePaidPlaintiff, false);
        assertEq(petition.feePaidDefendant, false);
        assertEq(petition.evidence.length, 0);
        assertEq(court.getFeesHeld(petition.petitionId), 0);

        // plaintiff pays fee & submits evidence
        vm.expectEmit(true, true, false, false);
        emit ArbitrationFeePaid(petition.petitionId, petition.plaintiff);
        vm.prank(petition.plaintiff);
        court.payArbitrationFee{value: petition.arbitrationFee}(petition.petitionId, evidence1);

        // data recorded correctly in petition
        petition = court.getPetition(petition.petitionId);
        assertEq(petition.feePaidPlaintiff, true);
        assertEq(petition.evidence.length, evidence1.length);
        assertEq(court.getFeesHeld(petition.petitionId), petition.arbitrationFee);   

        // plaintiff pays fee & submits evidence, triggering _selectJury() and VRF request
        vm.expectEmit(true, true, false, false);
        emit ArbitrationFeePaid(petition.petitionId, petition.defendant);
        vm.expectEmit(true, false, false, false /* request ID unknown at this time */);
        emit JurySelectionInitiated(petition.petitionId, 42);
        vm.recordLogs();
        vm.prank(petition.defendant);
        court.payArbitrationFee{value: petition.arbitrationFee}(petition.petitionId, evidence2);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[2].data));
        vrf.fulfillRandomWords(requestId, address(court));

        // data recorded correctly in petition
        petition = court.getPetition(petition.petitionId);
        assertEq(petition.feePaidDefendant, true);
        assertEq(petition.evidence.length, evidence1.length + evidence2.length);
        assertEq(court.getFeesHeld(petition.petitionId), petition.arbitrationFee + petition.arbitrationFee);  

        // jurors have been drawn
        assertEq(uint(petition.phase), uint(Phase.JurySelection));
        assertEq(petition.selectionStart, block.timestamp);
        Court.Jury memory jury = court.getJury(petition.petitionId);
        assertEq(jury.drawnJurors.length, court.jurorsNeeded(petition.petitionId) * 3);
    }

    function test_payArbitrationFee_revert() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_discovery_ERC20));
        // not litigant 
        vm.expectRevert(Court.Court__OnlyLitigant.selector);
        vm.prank(zorro);
        court.payArbitrationFee{value: petition.arbitrationFee}(petition.petitionId, evidence1);
        // insufficient amount
        vm.expectRevert(Court.Court__InsufficientAmount.selector);
        vm.prank(petition.plaintiff);
        court.payArbitrationFee{value: petition.arbitrationFee - 1}(petition.petitionId, evidence1);
        // fee already paid
        vm.prank(petition.plaintiff);
        court.payArbitrationFee{value: petition.arbitrationFee}(petition.petitionId, evidence1);
        vm.expectRevert(Court.Court__ArbitrationFeeAlreadyPaid.selector);
        vm.prank(petition.plaintiff);
        court.payArbitrationFee{value: petition.arbitrationFee}(petition.petitionId, evidence1);
    }

    function test_submitAdditionalEvidence() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_jurySelection_ERC20));
        uint256 evidenceLengthBefore = petition.evidence.length;

        vm.prank(petition.plaintiff);
        court.submitAdditionalEvidence(petition.petitionId, evidence1);

        petition = court.getPetition(petition.petitionId);    
        assertEq(petition.evidence.length, evidenceLengthBefore + evidence1.length);
    }

    function test_submitAdditionalEvidence_revert() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_discovery_MATIC));
        // not litigant 
        vm.expectRevert(Court.Court__OnlyLitigant.selector);
        vm.prank(zorro);
        court.submitAdditionalEvidence(petition.petitionId, evidence1);
        // arbitration fee not paid
        assertEq(petition.feePaidDefendant, false);
        vm.expectRevert(Court.Court__ArbitrationFeeNotPaid.selector);
        vm.prank(petition.defendant);
        court.submitAdditionalEvidence(petition.petitionId, evidence1);
        // wrong phase!
        petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_confirmedJury_MATIC));
        vm.expectRevert(Court.Court__EvidenceCanNoLongerBeSubmitted.selector);
        vm.prank(petition.defendant);
        court.submitAdditionalEvidence(petition.petitionId, evidence1);
    }

    function test_dismissUnpaidCase() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_discovery_MATIC));
        assertTrue(!petition.feePaidDefendant && !petition.feePaidPlaintiff);
        vm.warp(block.timestamp + court.DISCOVERY_PERIOD() + 1);

        vm.expectEmit(true, false, false, false);
        emit CaseDismissed(petition.petitionId);
        court.dismissUnpaidCase(petition.petitionId);

        petition = court.getPetition(petition.petitionId);
        assertEq(uint(petition.phase), uint(Phase.Dismissed));
    }

    function test_dismissUnpaidCase_revert() public {
        // nonexistant petition
        vm.expectRevert(Court.Court__PetitionDoesNotExist.selector);
        court.dismissUnpaidCase(10000000);
        // fees not overdue (still within DISCOVERY_PERIOD)
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_discovery_ERC20));
        vm.expectRevert(Court.Court__FeesNotOverdue.selector);
        court.dismissUnpaidCase(petition.petitionId);
        // at least one party has paid arbitration fee
        vm.warp(block.timestamp + court.DISCOVERY_PERIOD() + 1);
        vm.prank(petition.defendant);
        court.payArbitrationFee{value: petition.arbitrationFee}(petition.petitionId, evidence1);
        vm.expectRevert(Court.Court__ArbitrationFeeAlreadyPaid.selector);
        court.dismissUnpaidCase(petition.petitionId);
    }

    function test_requestDefaultJudgement() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_discovery_ERC20));
        vm.prank(petition.plaintiff);
        court.payArbitrationFee{value: petition.arbitrationFee}(petition.petitionId, evidence1);
        uint256 reclaimAmount = court.getFeesHeld(petition.petitionId);
        uint256 plaintiffBalBefore = petition.plaintiff.balance;
        uint256 courtBalBefore = address(court).balance;
        vm.warp(block.timestamp + court.DISCOVERY_PERIOD() + 1);

        vm.expectEmit(true, true, false, true);
        emit DefaultJudgementEntered(petition.petitionId, petition.plaintiff, true);
        vm.prank(petition.plaintiff);
        court.requestDefaultJudgement(petition.petitionId);

        petition = court.getPetition(petition.petitionId);
        assertEq(uint(petition.phase), uint(Phase.DefaultJudgement));
        assertEq(petition.petitionGranted, true);
        assertEq(court.getFeesHeld(petition.petitionId), 0);
        assertEq(petition.plaintiff.balance, plaintiffBalBefore + reclaimAmount);
        assertEq(address(court).balance, courtBalBefore - reclaimAmount);

        // again but this time defendant pays
        petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_discovery_MATIC));
        vm.prank(petition.defendant);
        court.payArbitrationFee{value: petition.arbitrationFee}(petition.petitionId, evidence1);
        reclaimAmount = court.getFeesHeld(petition.petitionId);
        uint256 defendantBalBefore = petition.defendant.balance;
        courtBalBefore = address(court).balance;

        vm.expectEmit(true, true, false, true);
        emit DefaultJudgementEntered(petition.petitionId, petition.defendant, false);
        vm.prank(petition.defendant);
        court.requestDefaultJudgement(petition.petitionId);

        petition = court.getPetition(petition.petitionId);
        assertEq(uint(petition.phase), uint(Phase.DefaultJudgement));
        assertEq(petition.petitionGranted, false);
        assertEq(court.getFeesHeld(petition.petitionId), 0);
        assertEq(petition.defendant.balance, defendantBalBefore + reclaimAmount);
        assertEq(address(court).balance, courtBalBefore - reclaimAmount);
    }

    function test_requestDefaultJudgement_revert() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_discovery_MATIC));
        vm.prank(petition.plaintiff);
        court.payArbitrationFee{value: petition.arbitrationFee}(petition.petitionId, evidence1);
        // in discovery, but fees not overdue (within DISCOVERY_PERIOD)
        vm.expectRevert(Court.Court__FeesNotOverdue.selector);
        vm.prank(petition.plaintiff);
        court.requestDefaultJudgement(petition.petitionId);
        // arbitration fee not paid
        vm.warp(block.timestamp + court.DISCOVERY_PERIOD() + 1);
        vm.expectRevert(Court.Court__ArbitrationFeeNotPaid.selector);
        vm.prank(petition.defendant);
        court.requestDefaultJudgement(petition.petitionId);
        // not litigant
        vm.expectRevert(Court.Court__OnlyLitigant.selector);
        vm.prank(zorro);
        court.requestDefaultJudgement(petition.petitionId);
        // wrong phase
        petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_jurySelection_MATIC));
        vm.expectRevert(Court.Court__OnlyDuringDiscovery.selector);
        vm.prank(petition.plaintiff);
        court.requestDefaultJudgement(petition.petitionId);
    }

    function test_settledExternally() public {
        Project memory project = marketplace.getProject(id_arbitration_discovery_ERC20);
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(project.projectId));
        vm.prank(project.provider);
        marketplace.proposeSettlement(
            project.projectId,
            settlementAdjustedProjectFee,
            settlementProviderStakeForfeit,
            "ipfs://settlementDetails"
        );

        vm.expectEmit(true, false, false, false);
        emit SettledExternally(petition.petitionId);
        vm.prank(project.buyer);
        marketplace.approveChangeOrder(project.projectId);

        petition = court.getPetition(petition.petitionId);
        assertEq(uint(petition.phase), uint(Phase.SettledExternally));

    }
 
    function test_reclaimArbitrationFee() public {
        bool[3] memory voteInputs = [false, false, true];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customRuling(id_arbitration_confirmedJury_MATIC, votes, true);
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_confirmedJury_MATIC));
        assertEq(uint(petition.phase), uint(Phase.Verdict));
        assertEq(petition.petitionGranted, false);
        assertEq(court.getFeesHeld(petition.petitionId), petition.arbitrationFee);
        uint256 defendantBalBefore = petition.defendant.balance;
        uint256 courtBalBefore = address(court).balance;
        
        vm.expectEmit(true, true, false, true);
        emit ArbitrationFeeReclaimed(petition.petitionId, petition.defendant, petition.arbitrationFee);
        vm.prank(petition.defendant);
        court.reclaimArbitrationFee(petition.petitionId);

        assertEq(court.getFeesHeld(petition.petitionId), 0);
        assertEq(petition.defendant.balance, defendantBalBefore + petition.arbitrationFee);
        assertEq(address(court).balance, courtBalBefore - petition.arbitrationFee);


        // once again, but with a granted petition
        voteInputs = [false, true, true];
        votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customRuling(id_arbitration_confirmedJury_ERC20, votes, true);
        petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_confirmedJury_ERC20));
        assertEq(uint(petition.phase), uint(Phase.Verdict));
        assertEq(petition.petitionGranted, true);
        assertEq(court.getFeesHeld(petition.petitionId), petition.arbitrationFee);
        uint256 plaintiffBalBefore = petition.plaintiff.balance;
        courtBalBefore = address(court).balance;
        
        vm.expectEmit(true, true, false, true);
        emit ArbitrationFeeReclaimed(petition.petitionId, petition.plaintiff, petition.arbitrationFee);
        vm.prank(petition.plaintiff);
        court.reclaimArbitrationFee(petition.petitionId);

        assertEq(court.getFeesHeld(petition.petitionId), 0);
        assertEq(petition.plaintiff.balance, plaintiffBalBefore + petition.arbitrationFee);
        assertEq(address(court).balance, courtBalBefore - petition.arbitrationFee);
    }

    function test_reclaimArbitrationFee_revert() public {
        // wrong phase
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_confirmedJury_MATIC));
        vm.expectRevert(Court.Court__ArbitrationFeeCannotBeReclaimed.selector);
        vm.prank(petition.plaintiff);
        court.reclaimArbitrationFee(petition.petitionId);
        
        bool[3] memory voteInputs = [false, false, true];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customRuling(id_arbitration_confirmedJury_MATIC, votes, true);
        petition = court.getPetition(petition.petitionId);
        
        // not litigant
        vm.expectRevert(Court.Court__OnlyLitigant.selector);
        vm.prank(admin1);
        court.reclaimArbitrationFee(petition.petitionId);
        // not prevailing party 
        assertEq(petition.petitionGranted, false);
        vm.expectRevert(Court.Court__OnlyPrevailingParty.selector);
        vm.prank(petition.plaintiff);
        court.reclaimArbitrationFee(petition.petitionId);
        // settlement - arbitration fee NOT paid
        Project memory project = marketplace.getProject(id_arbitration_discovery_ERC20);
        vm.prank(project.provider);
        marketplace.proposeSettlement(
            project.projectId,
            settlementAdjustedProjectFee,
            settlementProviderStakeForfeit,
            "ipfs://settlementDetails"
        );
        vm.prank(project.buyer);
        marketplace.approveChangeOrder(project.projectId);
        petition = court.getPetition(marketplace.getArbitrationPetitionId(project.projectId));
        assertEq(petition.feePaidDefendant, false);
        vm.expectRevert(Court.Court__ArbitrationFeeNotPaid.selector);
        vm.prank(petition.defendant);
        court.reclaimArbitrationFee(petition.petitionId);

    }
}
        

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";

contract CourtTest is Test, TestSetup {

    // test project params
    address buyer = alice;
    address provider = bob;
    uint256 projectFee = 1000 ether;
    uint256 providerStake = 50 ether;
    uint256 dueDate;
    uint256 reviewPeriodLength = 3 days;
    string detailsURI = "ipfs://someURI/";
    uint256 projectId_MATIC;
    uint256 petitionId_MATIC;
    uint256 projectId_ERC20;
    uint256 petitionId_ERC20;
    uint256 adjustedProjectFee = 750 ether;
    string[] evidence1 = ["someEvidenceURI", "someOtherEvidenceURI"];
    string[] evidence2 = ["someEvidenceURI2", "someOtherEvidenceURI2"];
    string[] additionalEvidence = ["additionalEvidence1", "additionalEvidence2"];
    bool juror0_vote = true;
    bool juror1_vote = true;
    bool juror2_vote = false;

    event ArbitrationFeePaid(uint256 indexed petitionId, address indexed user);
    event JurySelectionInitiated(uint256 indexed petitionId, uint256 requestId);
    event JuryDrawn(uint256 indexed petitionId, bool isRedraw);
    event JurorConfirmed(uint256 indexed petitionId, address jurorAddress);
    event VotingInitiated(uint256 indexed petitionId);
    event VoteCommitted(uint256 indexed petitionId, address indexed juror, bytes32 commit);
    event RulingInitiated(uint256 indexed petitionId);
    event VerdictReached(uint256 indexed petitionId, bool verdict, uint256 majorityVotes);
    event VoteRevealed(uint256 indexed petitionId, address indexed juror, bool vote);
    event JurorFeesClaimed(address indexed juror, uint256 amount);
    event ArbitrationFeeReclaimed(uint256 indexed petitionId, address indexed claimedBy, uint256 amount);
    event CaseDismissed(uint256 indexed petitionId);
    event SettledExternally(uint256 indexed petitionId);
    event DefaultJudgementEntered(uint256 indexed petitionId, address indexed claimedBy, bool verdict);
    event AdditionalJurorDrawingInitiated(uint256 indexed petitionId, uint256 requestId);
    event JurorRemoved(uint256 indexed petitionId, address indexed juror, uint256 stakeForfeit);
    event DelinquentReveal(uint256 indexed petitionId, bool deadlocked);
    event JurorFeeReimbursementOwed(uint256 indexed petitionId, address indexed juror, uint256 jurorFee);
    event CaseRestarted(uint256 indexed petitionId, uint256 requestId);

    function setUp() public {
        _setUp();
        _whitelistUsers();
        _registerJurors();
        dueDate = block.timestamp + 30 days;
        (projectId_MATIC, petitionId_MATIC) = _disputedProject_MATIC();
        (projectId_ERC20, petitionId_ERC20) = _disputedProject_ERC20();
    }

    function _disputedProject_MATIC() public returns (uint256, uint256) {
        uint256 txFee = marketplace.calculateNebulaiTxFee(projectFee);
        vm.prank(buyer);
        uint256 projectId = marketplace.createProject{value: txFee + projectFee}(
            provider,
            address(0), // MATIC
            projectFee,
            providerStake,
            dueDate,
            reviewPeriodLength,
            detailsURI
        );
        vm.prank(provider);
        marketplace.activateProject{value: providerStake}(projectId);
        vm.prank(provider);
        marketplace.completeProject(projectId);
        vm.prank(buyer);
        marketplace.challengeProject(
            projectId,
            adjustedProjectFee,
            0,
            "someURI"
        );
        vm.warp(block.timestamp + marketplace.CHANGE_ORDER_PERIOD() + 1);
        vm.prank(buyer);
        uint256 petitionId = marketplace.disputeProject(
            projectId,
            adjustedProjectFee,
            0
        );
        return (projectId, petitionId);
    }

    function _disputedProject_ERC20() internal returns (uint256, uint256) {
        uint256 txFee = marketplace.calculateNebulaiTxFee(projectFee);
        vm.prank(buyer);
        usdt.approve(address(marketplace), txFee + projectFee);
        vm.prank(buyer);
        uint256 projectId = marketplace.createProject(
            provider,
            address(usdt),
            projectFee,
            providerStake,
            dueDate,
            reviewPeriodLength,
            detailsURI
        );
        vm.prank(provider);
        usdt.approve(address(marketplace), providerStake);
        vm.prank(provider);
        marketplace.activateProject(projectId);
        vm.prank(provider);
        marketplace.completeProject(projectId);
        vm.prank(buyer);
        marketplace.challengeProject(
            projectId,
            adjustedProjectFee,
            0,
            "someURI"
        );
        vm.warp(block.timestamp + marketplace.CHANGE_ORDER_PERIOD() + 1);
        vm.prank(buyer);
        uint256 petitionId = marketplace.disputeProject(
            projectId,
            adjustedProjectFee,
            0
        );
        return (projectId, petitionId);
    }

    function _petitionWithDrawnJury(uint256 _petitionId) internal {
        Court.Petition memory p = court.getPetition(_petitionId);
        // plaintiff pays
        vm.prank(p.plaintiff);
        court.payArbitrationFee{value: p.arbitrationFee}(_petitionId, evidence1);
        // defendant pays and jury selection is initiated
        vm.recordLogs();
        vm.prank(p.defendant);
        court.payArbitrationFee{value: p.arbitrationFee}(_petitionId, evidence2);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[2].data));
        vrf.fulfillRandomWords(requestId, address(court));
    }

    function _petitionWithConfirmedJury(uint256 _petitionId) internal {
        Court.Petition memory p = court.getPetition(_petitionId);
        vm.prank(p.plaintiff);
        court.payArbitrationFee{value: p.arbitrationFee}(_petitionId, evidence1);
        vm.recordLogs();
        vm.prank(p.defendant);
        court.payArbitrationFee{value: p.arbitrationFee}(_petitionId, evidence2);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[2].data));
        vrf.fulfillRandomWords(requestId, address(court));
        Court.Jury memory jury = court.getJury(p.petitionId);
        uint256 jurorStake = court.jurorFlatFee();
        for(uint i; i < court.jurorsNeeded(p.petitionId); ++i) {
            vm.prank(jury.drawnJurors[i]);
            court.acceptCase{value: jurorStake}(p.petitionId);
        }
    }

    function _petitionWithCommittedVotes(uint256 _petitionId) internal {
        Court.Petition memory p = court.getPetition(_petitionId);
        vm.prank(p.plaintiff);
        court.payArbitrationFee{value: p.arbitrationFee}(_petitionId, evidence1);
        vm.recordLogs();
        vm.prank(p.defendant);
        court.payArbitrationFee{value: p.arbitrationFee}(_petitionId, evidence2);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[2].data));
        vrf.fulfillRandomWords(requestId, address(court));
        Court.Jury memory jury = court.getJury(p.petitionId);
        uint256 jurorStake = court.jurorFlatFee();
        for(uint i; i < court.jurorsNeeded(p.petitionId); ++i) {
            vm.prank(jury.drawnJurors[i]);
            court.acceptCase{value: jurorStake}(p.petitionId);
        }
        jury = court.getJury(p.petitionId);
        bytes32 commit = keccak256(abi.encodePacked(juror0_vote, "someSalt"));
        vm.prank(jury.confirmedJurors[0]);
        court.commitVote(p.petitionId, commit);
        commit = keccak256(abi.encodePacked(juror1_vote, "someSalt"));
        vm.prank(jury.confirmedJurors[1]);
        court.commitVote(p.petitionId, commit);
        commit = keccak256(abi.encodePacked(juror2_vote, "someSalt"));
        vm.prank(jury.confirmedJurors[2]);
        court.commitVote(p.petitionId, commit);
    }

    function _petitionWithRevealedVotes(uint256 _petitionId) public {
        Court.Petition memory p = court.getPetition(_petitionId);
        vm.prank(p.plaintiff);
        court.payArbitrationFee{value: p.arbitrationFee}(_petitionId, evidence1);
        vm.recordLogs();
        vm.prank(p.defendant);
        court.payArbitrationFee{value: p.arbitrationFee}(_petitionId, evidence2);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[2].data));
        vrf.fulfillRandomWords(requestId, address(court));
        Court.Jury memory jury = court.getJury(p.petitionId);
        uint256 jurorStake = court.jurorFlatFee();
        for(uint i; i < court.jurorsNeeded(p.petitionId); ++i) {
            vm.prank(jury.drawnJurors[i]);
            court.acceptCase{value: jurorStake}(p.petitionId);
        }
        jury = court.getJury(p.petitionId);
        bytes32 commit = keccak256(abi.encodePacked(juror0_vote, "someSalt"));
        vm.prank(jury.confirmedJurors[0]);
        court.commitVote(p.petitionId, commit);
        commit = keccak256(abi.encodePacked(juror1_vote, "someSalt"));
        vm.prank(jury.confirmedJurors[1]);
        court.commitVote(p.petitionId, commit);
        commit = keccak256(abi.encodePacked(juror2_vote, "someSalt"));
        vm.prank(jury.confirmedJurors[2]);
        court.commitVote(p.petitionId, commit);

        vm.prank(jury.confirmedJurors[0]);
        court.revealVote(p.petitionId, juror0_vote, "someSalt");
        vm.prank(jury.confirmedJurors[1]);
        court.revealVote(p.petitionId, juror1_vote, "someSalt");
        vm.prank(jury.confirmedJurors[2]);
        court.revealVote(p.petitionId, juror2_vote, "someSalt");
    } 

    ////////////////////
    ///   PETITION   ///
    ////////////////////

    function test_createPetition() public {
        Court.Petition memory p = court.getPetition(petitionId_MATIC);
        assertEq(p.petitionId, petitionId_MATIC);
        assertEq(p.marketplace, address(marketplace));
        assertEq(p.projectId, projectId_MATIC);
        assertEq(p.adjustedProjectFee, adjustedProjectFee);
        assertEq(p.providerStakeForfeit, 0);
        assertEq(p.plaintiff, buyer);
        assertEq(p.defendant, provider);
        assertEq(p.arbitrationFee, court.calculateArbitrationFee(false));
        assertEq(p.feePaidPlaintiff, false);
        assertEq(p.feePaidDefendant, false);
        // assertEq(p.discoveryStart, block.timestamp); // this gets thrown off since we warp a few times in setup()
        assertEq(p.selectionStart, 0);
        assertEq(p.votingStart, 0);
        assertEq(p.rulingStart, 0);
        assertEq(p.verdictRenderedDate, 0);
        assertEq(p.isAppeal, false);
        assertEq(p.petitionGranted, false);
        assertEq(uint(p.phase), uint(Court.Phase.Discovery));
        assertEq(marketplace.getArbitrationPetitionId(projectId_MATIC), p.petitionId);
    }

    // function test_createPetition_revert() public {}

    function test_payArbitrationFee() public {
        Court.Petition memory p = court.getPetition(petitionId_MATIC);
        vm.expectEmit(true, true, false, false);
        emit ArbitrationFeePaid(p.petitionId, p.plaintiff);
        vm.prank(p.plaintiff);
        court.payArbitrationFee{value: p.arbitrationFee}(petitionId_MATIC, evidence1);
        p = court.getPetition(petitionId_MATIC);
        assertEq(p.feePaidPlaintiff, true);
        assertEq(p.evidence[0], evidence1[0]);
        assertEq(p.evidence[1], evidence1[1]);
    }

    function test_payArbitrationFee_automaticJurySelection() public {
        Court.Petition memory p = court.getPetition(petitionId_MATIC);
        // buyer pays
        vm.pauseGasMetering();
        test_payArbitrationFee();
        vm.resumeGasMetering();
        // defentand pays and jury selection is initiated
        vm.expectEmit(true, true, false, false);
        emit ArbitrationFeePaid(p.petitionId, p.defendant);
        vm.expectEmit(true, false, false, false);
        emit JurySelectionInitiated(p.petitionId, 42);
        vm.recordLogs();
        vm.prank(p.defendant);
        court.payArbitrationFee{value: p.arbitrationFee}(petitionId_MATIC, evidence1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // uint256 requestId = uint(entries[2].topics[1]);
        uint256 requestId = uint(bytes32(entries[2].data));
        assertEq(court.vrfRequestToPetition(requestId), p.petitionId);
        // console.log(requestId);
        p = court.getPetition(petitionId_MATIC);
        assertEq(p.feePaidDefendant, true);
        assertEq(p.evidence[2], evidence1[0]);
        assertEq(p.evidence[3], evidence1[1]);
        assertEq(uint(p.phase), uint(Court.Phase.JurySelection));
    }

    function test_payArbitrationFee_revert() public {
        Court.Petition memory p = court.getPetition(petitionId_MATIC);
        // not litigant
        vm.expectRevert(Court.Court__OnlyLitigant.selector);
        vm.prank(zorro);
        court.payArbitrationFee{value: p.arbitrationFee}(petitionId_MATIC, evidence1);
        // already paid
        vm.prank(p.plaintiff);
        court.payArbitrationFee{value: p.arbitrationFee}(petitionId_MATIC, evidence1);
        vm.expectRevert(Court.Court__ArbitrationFeeAlreadyPaid.selector);
        vm.prank(p.plaintiff);
        court.payArbitrationFee{value: p.arbitrationFee}(petitionId_MATIC, evidence1);
        // insufficient amount
        vm.expectRevert(Court.Court__InsufficientAmount.selector);
        vm.prank(p.defendant);
        court.payArbitrationFee{value: p.arbitrationFee - 1}(petitionId_MATIC, evidence1);
    }

    function test_submitAdditionalEvidence() public {
        Court.Petition memory petition = court.getPetition(petitionId_MATIC);
        // buyer pays
        vm.pauseGasMetering();
        test_payArbitrationFee();
        vm.resumeGasMetering();
        vm.prank(buyer);
        court.submitAdditionalEvidence(petition.petitionId, additionalEvidence);
        petition = court.getPetition(petitionId_MATIC);
        assertEq(petition.evidence[2], additionalEvidence[0]);
        assertEq(petition.evidence[3], additionalEvidence[1]);
    }

    function test_submitAdditionalEvidence_revert() public {
        Court.Petition memory petition = court.getPetition(petitionId_MATIC);
        // fee not paid
        assertEq(petition.feePaidDefendant, false);
        vm.expectRevert(Court.Court__ArbitrationFeeNotPaid.selector);
        vm.prank(petition.defendant);
        court.submitAdditionalEvidence(petition.petitionId, additionalEvidence);
        // wrong phase
        _petitionWithConfirmedJury(petition.petitionId);
        vm.expectRevert(Court.Court__EvidenceCanNoLongerBeSubmitted.selector);
        vm.prank(petition.defendant);
        court.submitAdditionalEvidence(petition.petitionId, additionalEvidence);
    }

    function test_reclaimArbitrationFee_after_verdict() public {
        vm.pauseGasMetering();
        _petitionWithRevealedVotes(petitionId_MATIC);
        vm.resumeGasMetering();
        Court.Petition memory p = court.getPetition(petitionId_MATIC);
        assertEq(p.petitionGranted, true);
        uint256 feesHeldBefore = court.getFeesHeld(p.petitionId);
        uint256 plaintiffBalBefore = p.plaintiff.balance;
        assertEq(feesHeldBefore, p.arbitrationFee);
        vm.expectEmit(true, true, false, true);
        emit ArbitrationFeeReclaimed(p.petitionId, p.plaintiff, feesHeldBefore);
        vm.prank(p.plaintiff);
        court.reclaimArbitrationFee(p.petitionId);
        assertEq(court.getFeesHeld(p.petitionId), 0);
        assertEq(p.plaintiff.balance, plaintiffBalBefore + feesHeldBefore);
    }

    function test_reclaimArbitrationFee_after_settlement() public {
        vm.pauseGasMetering();
        Court.Petition memory petition = court.getPetition(petitionId_MATIC);
        // plaintiff (buyer) pays arbitration fee
        vm.prank(petition.plaintiff);
        court.payArbitrationFee{value: petition.arbitrationFee}(petition.petitionId, evidence1);
        // defendant (provider) proposes settlement in marketplace
        Marketplace.Project memory project = marketplace.getProject(petition.projectId);
        string memory settlementDetails = "ipfs://someSettlementDetails";
        vm.prank(petition.defendant);
        marketplace.proposeSettlement(
            project.projectId,
            petition.adjustedProjectFee + 100 ether,
            0,
            settlementDetails
        );
        // plaintiff agrees to settlement 
        vm.prank(petition.plaintiff);
        marketplace.approveChangeOrder(project.projectId);
        vm.resumeGasMetering();
        // plaintiff reclaims arbitration fee 
        petition = court.getPetition(petition.petitionId);
        uint256 plaintiffBalBefore = petition.plaintiff.balance;
        uint256 feesHeldBefore = court.getFeesHeld(petition.petitionId);
        assertEq(petition.feePaidPlaintiff, true);

        vm.expectEmit(true, true, false, true);
        emit ArbitrationFeeReclaimed(petition.petitionId, petition.plaintiff, feesHeldBefore);
        vm.prank(petition.plaintiff);
        court.reclaimArbitrationFee(petition.petitionId);
        assertEq(court.getFeesHeld(petition.petitionId), 0);
        assertEq(petition.plaintiff.balance, plaintiffBalBefore + feesHeldBefore);
    }

    function test_reclaimArbitrationFee_revert() public {
        vm.pauseGasMetering();
        _petitionWithRevealedVotes(petitionId_MATIC); 
        vm.resumeGasMetering();
        // WRONG PHASE
        Court.Petition memory p = court.getPetition(petitionId_ERC20);
        assertEq(uint(p.phase), uint(Court.Phase.Discovery));
        vm.expectRevert(Court.Court__ArbitrationFeeCannotBeReclaimed.selector);
        vm.prank(p.plaintiff);
        court.reclaimArbitrationFee(p.petitionId);
        // not litigant
        vm.expectRevert(Court.Court__OnlyLitigant.selector);
        vm.prank(zorro);
        court.reclaimArbitrationFee(p.petitionId);
        // VERDICT
        p = court.getPetition(petitionId_MATIC);
        // not prevailing party 
        assertEq(p.petitionGranted, true);
        vm.expectRevert(Court.Court__OnlyPrevailingParty.selector);
        vm.prank(p.defendant);
        court.reclaimArbitrationFee(p.petitionId);
        // already reclaimed
        vm.prank(p.plaintiff);
        court.reclaimArbitrationFee(p.petitionId);
        vm.expectRevert(Court.Court__ArbitrationFeeAlreadyReclaimed.selector);
        vm.prank(p.plaintiff);
        court.reclaimArbitrationFee(p.petitionId);
        // not litigant
        vm.expectRevert(Court.Court__OnlyLitigant.selector);
        vm.prank(zorro);
        court.reclaimArbitrationFee(p.petitionId);
        // SETTLEMENT
        // fee not paid
        p = court.getPetition(petitionId_ERC20);
            // settlement proposed by defendant
        string memory settlementURI = "ipfs://someSettlement";
        vm.prank(p.defendant);
        marketplace.proposeSettlement(
            p.projectId,
            projectFee - 100 ether,
            0,
            settlementURI
        );
            // plaintiff agrees 
        vm.prank(p.plaintiff);
        marketplace.approveChangeOrder(p.projectId);
            // no one has paid
        p = court.getPetition(petitionId_ERC20);
        assertEq(p.feePaidPlaintiff, false);
        vm.expectRevert(Court.Court__ArbitrationFeeNotPaid.selector);
        vm.prank(p.plaintiff);
        court.reclaimArbitrationFee(p.petitionId);
    }

    function test_appeal() public {
        vm.pauseGasMetering();
        _petitionWithRevealedVotes(petitionId_MATIC);
        vm.resumeGasMetering();
        Court.Petition memory petition = court.getPetition(petitionId_MATIC);
            // defendant (provider) appeals decision
        vm.prank(petition.defendant);
        uint256 appealPetitionId = marketplace.appealRuling(petition.projectId);
        Court.Petition memory appealPetition = court.getPetition(appealPetitionId);
        assertEq(uint(appealPetition.phase), uint(Court.Phase.Discovery));
        assertEq(appealPetition.isAppeal, true);
        // arbitration fee is for 5 jurors rather than 3
        assertEq(appealPetition.arbitrationFee, court.jurorFlatFee() * 5);
        // old petition is no longer tied to projectId in marketplace
        assertFalse(marketplace.getArbitrationPetitionId(petition.projectId) == petition.petitionId);
        // marketplace maps project ID to new petition
        assertTrue(marketplace.getArbitrationPetitionId(petition.projectId) == appealPetition.petitionId);
    }

    function test_dismissUnpaidCase() public {
        Court.Petition memory p = court.getPetition(petitionId_MATIC);
        vm.warp(block.timestamp + p.discoveryStart + court.DISCOVERY_PERIOD() + 1);
        vm.expectEmit(true, false, false, false);
        emit CaseDismissed(p.petitionId);
        court.dismissUnpaidCase(p.petitionId);
        p = court.getPetition(petitionId_MATIC);
        assertEq(uint(p.phase), uint(Court.Phase.Dismissed));
    }

    // function test_dismissUnpaidCase_revert() public {}

    function test_settledExternally() public {
        vm.pauseGasMetering();
        Court.Petition memory petition = court.getPetition(petitionId_MATIC);
        Marketplace.Project memory project = marketplace.getProject(petition.projectId);
            // settlement proposed and signed
        string memory settlementURI = "ipfs://someSettlement";
        vm.prank(project.buyer);
        marketplace.proposeSettlement(
            project.projectId,
            project.projectFee - 100 ether,
            0,
            settlementURI
        );
        vm.resumeGasMetering();
        vm.expectEmit(true, false, false, false);
        emit SettledExternally(petition.petitionId);
        vm.prank(project.provider);
        marketplace.approveChangeOrder(project.projectId);
        petition = court.getPetition(petition.petitionId);
        assertEq(uint(petition.phase), uint(Court.Phase.SettledExternally));
    }

    function test_settledExternally_revert() public {
        vm.pauseGasMetering();
        Court.Petition memory petition = court.getPetition(petitionId_MATIC);
        Marketplace.Project memory project = marketplace.getProject(petition.projectId);
            // settlement proposed and signed
        string memory settlementURI = "ipfs://someSettlement";
        vm.prank(project.buyer);
        marketplace.proposeSettlement(
            project.projectId,
            project.projectFee - 100 ether,
            0,
            settlementURI
        );
        vm.resumeGasMetering();
        // caller is not marketplace
        vm.expectRevert(Court.Court__OnlyMarketplace.selector);
        court.settledExternally(petition.petitionId);
    }

    function test_requestDefaultJudgement() public {
        Court.Petition memory petition = court.getPetition(petitionId_ERC20);
            // plaintiff pays arbitration fee
        vm.prank(petition.plaintiff);
        court.payArbitrationFee{value: petition.arbitrationFee}(petition.petitionId, evidence1);
            // discovery period passes, defendant has not paid
        vm.warp(block.timestamp + court.DISCOVERY_PERIOD() + 1);
        uint256 plaintiffBalBefore = petition.plaintiff.balance;
        uint256 feesHeldBefore = court.getFeesHeld(petition.petitionId);
        vm.expectEmit(true, true, false, true);
        emit DefaultJudgementEntered(petition.petitionId, petition.plaintiff, true);
        vm.prank(petition.plaintiff);
        court.requestDefaultJudgement(petition.petitionId);
        // arbitration fee has been reclaimed
        assertEq(court.getFeesHeld(petition.petitionId), feesHeldBefore - petition.arbitrationFee);
        assertEq(petition.plaintiff.balance, plaintiffBalBefore + petition.arbitrationFee);
        // phase updated
        petition = court.getPetition(petition.petitionId);
        assertEq(uint(petition.phase), uint(Court.Phase.DefaultJudgement));
        // petition is granted
        assertEq(petition.petitionGranted, true);
    }

    function test_requestDefaultJudgement_revert() public {
        Court.Petition memory petition = court.getPetition(petitionId_ERC20);
            // plaintiff pays arbitration fee
        vm.prank(petition.plaintiff);
        court.payArbitrationFee{value: petition.arbitrationFee}(petition.petitionId, evidence1);
        // still in discovery (fee not overdue)
        vm.expectRevert(Court.Court__FeesNotOverdue.selector);
        vm.prank(petition.plaintiff);
        court.requestDefaultJudgement(petition.petitionId);
        // arbitration fee not paid
            // warp past discovery period
        vm.warp(block.timestamp + court.DISCOVERY_PERIOD() + 1);
        assertEq(petition.feePaidDefendant, false);
        vm.prank(petition.defendant);
        vm.expectRevert(Court.Court__ArbitrationFeeNotPaid.selector);
        court.requestDefaultJudgement(petition.petitionId);
        // wrong phase
        vm.prank(petition.plaintiff);
        court.requestDefaultJudgement(petition.petitionId);
        vm.expectRevert(Court.Court__OnlyDuringDiscovery.selector);
        vm.prank(petition.plaintiff);
        court.requestDefaultJudgement(petition.petitionId);
    }

    ////////////////
    ///   JURY   ///
    ////////////////

    function test_jury_selection() public {
        Court.Petition memory p = court.getPetition(petitionId_MATIC);
        // buyer pays
        vm.pauseGasMetering();
        test_payArbitrationFee();
        vm.recordLogs();
        vm.prank(p.defendant);
        court.payArbitrationFee{value: p.arbitrationFee}(petitionId_MATIC, evidence1);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[2].data));
        // uint256 requestId = uint(entries[2].topics[1]);
        vm.resumeGasMetering();
        vm.expectEmit(true, false, false, true);
        emit JuryDrawn(p.petitionId, false);
        vrf.fulfillRandomWords(requestId, address(court));
        Court.Jury memory jury = court.getJury(p.petitionId);
        for(uint i; i < jury.drawnJurors.length; ++i) {
            // emit log_address(jury.drawnJurors[i]);
            for(uint j; j < jury.drawnJurors.length; ++j) {
                if(i != j) {
                    assertTrue(jury.drawnJurors[i] != jury.drawnJurors[j]);
                }
            }
        }
    }

    function test_acceptCase() public {
        vm.pauseGasMetering();
        _petitionWithDrawnJury(petitionId_ERC20);
        vm.resumeGasMetering();
        Court.Petition memory p = court.getPetition(petitionId_ERC20);
        Court.Jury memory jury = court.getJury(p.petitionId);
        address juror_one = jury.drawnJurors[0];
        uint256 jurorStake = court.jurorFlatFee();
        uint256 stakeBefore = court.getJurorStakeHeld(juror_one, p.petitionId);
        vm.expectEmit(true, false, false, true);
        emit JurorConfirmed(p.petitionId, juror_one);
        vm.prank(juror_one);
        court.acceptCase{value: jurorStake}(p.petitionId);
        jury = court.getJury(p.petitionId);
        bool isConfirmed;
        for(uint i; i < jury.confirmedJurors.length; ++i) {
            if(juror_one == jury.confirmedJurors[i]) isConfirmed = true;
        }
        assertEq(isConfirmed, true);
        assertEq(court.getJurorStakeHeld(juror_one, p.petitionId), stakeBefore + jurorStake);
    }

    function test_acceptCase_revert() public {
        vm.pauseGasMetering();
        _petitionWithDrawnJury(petitionId_ERC20);
        vm.resumeGasMetering();
        Court.Petition memory p = court.getPetition(petitionId_ERC20);
        Court.Jury memory jury = court.getJury(p.petitionId);
        uint256 jurorStake = court.jurorFlatFee();
        // not drawn juror 
        vm.expectRevert(Court.Court__NotDrawnJuror.selector);
        vm.prank(alice); // alice is buyer, so cannot possibly be drawn for jury
        court.acceptCase{value: jurorStake}(p.petitionId);
        // jurorStatus != Active
            // pause a juror from drawn jurors
        vm.prank(jury.drawnJurors[0]);
        juryPool.pauseJuror();
        vm.expectRevert(Court.Court__InvalidJuror.selector);
        vm.prank(jury.drawnJurors[0]);
        court.acceptCase{value: jurorStake}(p.petitionId);
        // already confirmed
            // accept case
        vm.prank(jury.drawnJurors[1]);
        court.acceptCase{value: jurorStake}(p.petitionId);
        vm.expectRevert(Court.Court__AlreadyConfirmedJuror.selector);
        vm.prank(jury.drawnJurors[1]);
        court.acceptCase{value: jurorStake}(p.petitionId);
        // insufficient stake 
        vm.expectRevert(Court.Court__InsufficientJurorStake.selector);
        vm.prank(jury.drawnJurors[2]);
        court.acceptCase{value: jurorStake - 1}(p.petitionId);
        // seats already filled
            // two more jurors accept
        vm.prank(jury.drawnJurors[2]);
        court.acceptCase{value: jurorStake}(p.petitionId);
        vm.prank(jury.drawnJurors[3]);
        court.acceptCase{value: jurorStake}(p.petitionId);
        jury = court.getJury(p.petitionId);
        assertEq(jury.confirmedJurors.length, court.jurorsNeeded(p.petitionId));
        vm.expectRevert(Court.Court__JurorSeatsFilled.selector);
        vm.prank(jury.drawnJurors[4]);
        court.acceptCase{value: jurorStake}(p.petitionId);
    }

    function test_acceptCase_phase_change_when_jury_seats_filled() public {
        vm.pauseGasMetering();
        _petitionWithDrawnJury(petitionId_ERC20);
        vm.resumeGasMetering();
        Court.Petition memory p = court.getPetition(petitionId_ERC20);
        Court.Jury memory jury = court.getJury(p.petitionId);
        uint256 jurorStake = court.jurorFlatFee();
        vm.prank(jury.drawnJurors[0]);
        court.acceptCase{value: jurorStake}(p.petitionId);
        vm.prank(jury.drawnJurors[1]);
        court.acceptCase{value: jurorStake}(p.petitionId);
        vm.expectEmit(true, false, false, true);
        emit JurorConfirmed(p.petitionId, jury.drawnJurors[2]);
        vm.expectEmit(false, false, false, true);
        emit VotingInitiated(p.petitionId);
        vm.prank(jury.drawnJurors[2]);
        court.acceptCase{value: jurorStake}(p.petitionId);
        p = court.getPetition(petitionId_ERC20);
        assertEq(uint(p.phase), uint(Court.Phase.Voting));
    }

    function test_commitVote() public {
        vm.pauseGasMetering();
        _petitionWithConfirmedJury(petitionId_MATIC);
        vm.resumeGasMetering();
        Court.Petition memory p = court.getPetition(petitionId_MATIC);
        Court.Jury memory jury = court.getJury(p.petitionId);
        // assertEq(jury.confirmedJurors.length, court.jurorsNeeded(p.petitionId));
        bool vote = true;
        bytes32 commit = keccak256(abi.encodePacked(vote, "someSalt"));
        vm.expectEmit(true, true, false, true);
        emit VoteCommitted(p.petitionId, jury.confirmedJurors[0], commit);
        vm.prank(jury.confirmedJurors[0]);
        court.commitVote(p.petitionId, commit);
        assertEq(court.getCommit(jury.confirmedJurors[0], p.petitionId), commit);
    }

    function test_commitVote_revert() public {
        vm.pauseGasMetering();
        _petitionWithConfirmedJury(petitionId_MATIC);
        vm.resumeGasMetering();
        Court.Petition memory p = court.getPetition(petitionId_MATIC);
        Court.Jury memory jury = court.getJury(p.petitionId);
        // invalid commit
        bytes32 invalidCommit = 0x0;
        vm.expectRevert(Court.Court__InvalidCommit.selector);
        vm.prank(jury.confirmedJurors[0]);
        court.commitVote(p.petitionId, invalidCommit);
        // duplicate commit
        bool vote = true;
        bytes32 commit = keccak256(abi.encodePacked(vote, "someSalt"));
        vm.prank(jury.confirmedJurors[0]);
        court.commitVote(p.petitionId, commit);
        vm.expectRevert(Court.Court__JurorHasAlreadyCommmitedVote.selector);
        vm.prank(jury.confirmedJurors[0]);
        court.commitVote(p.petitionId, commit);
        // invalid juror
        vm.expectRevert(Court.Court__InvalidJuror.selector);
        vm.prank(p.plaintiff); // plaintiff cannot possibly be juror
        court.commitVote(p.petitionId, commit);
    }

    function test_allVotesCommitted() public {
        vm.pauseGasMetering();
        _petitionWithConfirmedJury(petitionId_MATIC);
        vm.resumeGasMetering();
        Court.Petition memory p = court.getPetition(petitionId_MATIC);
        Court.Jury memory jury = court.getJury(p.petitionId);
        bool vote = true;
        bytes32 commit = keccak256(abi.encodePacked(vote, "someSalt"));
        vm.prank(jury.confirmedJurors[0]);
        court.commitVote(p.petitionId, commit);
        vm.prank(jury.confirmedJurors[1]);
        court.commitVote(p.petitionId, commit);
        vm.expectEmit(true, true, false, true);
        emit VoteCommitted(p.petitionId, jury.confirmedJurors[2], commit);
        vm.expectEmit(true, false, false, false);
        emit RulingInitiated(p.petitionId);
        vm.prank(jury.confirmedJurors[2]);
        court.commitVote(p.petitionId, commit);
        p = court.getPetition(petitionId_MATIC);
        assertEq(uint(p.phase), uint(Court.Phase.Ruling));
        assertEq(p.rulingStart, block.timestamp);
    }

    function test_revealVote() public {
        vm.pauseGasMetering();
        _petitionWithCommittedVotes(petitionId_ERC20);
        vm.resumeGasMetering();
        Court.Petition memory p = court.getPetition(petitionId_ERC20);
        Court.Jury memory jury = court.getJury(p.petitionId);
        uint256 juror0_stake = court.getJurorStakeHeld(jury.confirmedJurors[0], p.petitionId); 
        uint256 juror0_balBefore = jury.confirmedJurors[0].balance;
        vm.expectEmit(true, true, false, true);
        emit VoteRevealed(p.petitionId, jury.confirmedJurors[0], juror0_vote);
        vm.prank(jury.confirmedJurors[0]);
        court.revealVote(p.petitionId, juror0_vote, "someSalt");
        assertEq(court.hasRevealedVote(jury.confirmedJurors[0], p.petitionId), true);
        assertEq(court.getVote(jury.confirmedJurors[0], p.petitionId), juror0_vote);
        // juror stake as been returned 
        assertEq(court.getJurorStakeHeld(jury.confirmedJurors[0], p.petitionId), 0);
        assertEq(jury.confirmedJurors[0].balance, juror0_balBefore + juror0_stake);
    }

    function test_revealVote_revert() public {
        vm.pauseGasMetering();
        _petitionWithConfirmedJury(petitionId_MATIC);
        vm.resumeGasMetering();
        Court.Petition memory p = court.getPetition(petitionId_MATIC);
        Court.Jury memory jury = court.getJury(p.petitionId);
        bytes32 commit = keccak256(abi.encodePacked(juror0_vote, "someSalt"));
        vm.prank(jury.confirmedJurors[0]);
        court.commitVote(p.petitionId, commit);
        // wrong phase (all votes not committed)
        vm.expectRevert(Court.Court__CannotRevealBeforeAllVotesCommitted.selector);
        vm.prank(jury.confirmedJurors[0]);
        court.revealVote(p.petitionId, juror0_vote, "someSalt");
            // remaining jurors commit
        vm.prank(jury.confirmedJurors[1]);
        court.commitVote(p.petitionId, commit);
        commit = keccak256(abi.encodePacked(juror2_vote, "someSalt"));
        vm.prank(jury.confirmedJurors[2]);
        court.commitVote(p.petitionId, commit);
        // invalid juror
        vm.expectRevert(Court.Court__InvalidJuror.selector);
        vm.prank(alice);
        court.revealVote(p.petitionId, juror0_vote, "someSalt");
        // reveal does not match commit
        vm.expectRevert(Court.Court__RevealDoesNotMatchCommit.selector);
        vm.prank(jury.confirmedJurors[0]);
        court.revealVote(p.petitionId, juror0_vote, "WRONG_SALT"); // incorrect salt
        vm.expectRevert(Court.Court__RevealDoesNotMatchCommit.selector);
        vm.prank(jury.confirmedJurors[0]);
        court.revealVote(p.petitionId, !juror0_vote, "someSalt"); // incorrect vote
        // already revealed 
        vm.prank(jury.confirmedJurors[0]);
        court.revealVote(p.petitionId, juror0_vote, "someSalt");
        vm.expectRevert(Court.Court__AlreadyRevealed.selector);
        vm.prank(jury.confirmedJurors[0]);
        court.revealVote(p.petitionId, juror0_vote, "someSalt");
    }

    function test_revealVote_renderVerdict() public {
        vm.pauseGasMetering();
        _petitionWithCommittedVotes(petitionId_ERC20);
        Court.Petition memory p = court.getPetition(petitionId_ERC20);
        Court.Jury memory jury = court.getJury(p.petitionId);
        vm.prank(jury.confirmedJurors[0]);
        court.revealVote(p.petitionId, juror0_vote, "someSalt");
        vm.prank(jury.confirmedJurors[1]);
        court.revealVote(p.petitionId, juror1_vote, "someSalt");
        vm.resumeGasMetering();

        uint256 jurorFee = p.arbitrationFee / court.jurorsNeeded(p.petitionId);
        uint256 juryReservesBefore = juryPool.getJuryReserves();
        uint256 juror0_feesOwedBefore = court.getJurorFeesOwed(jury.confirmedJurors[0]);
        uint256 juror1_feesOwedBefore = court.getJurorFeesOwed(jury.confirmedJurors[1]);
        uint256 juror2_feesOwedBefore = court.getJurorFeesOwed(jury.confirmedJurors[2]); // minority vote, so should NOT change
        vm.expectEmit(true, true, false, true);
        emit VoteRevealed(p.petitionId, jury.confirmedJurors[2], juror2_vote);
        vm.expectEmit(true, false, false, true);
        emit VerdictReached(p.petitionId, true, 2);
        vm.prank(jury.confirmedJurors[2]);
        court.revealVote(p.petitionId, juror2_vote, "someSalt");
        p = court.getPetition(petitionId_ERC20);
        assertEq(uint(p.phase), uint(Court.Phase.Verdict));
        assertEq(p.petitionGranted, true);
        assertEq(p.verdictRenderedDate, block.timestamp);
        // juror fees paid to majority voters
        assertEq(court.getJurorFeesOwed(jury.confirmedJurors[0]), juror0_feesOwedBefore + jurorFee);
        assertEq(court.getJurorFeesOwed(jury.confirmedJurors[1]), juror1_feesOwedBefore + jurorFee);
        assertEq(court.getJurorFeesOwed(jury.confirmedJurors[2]), juror2_feesOwedBefore); // minoroty vote, no fee owed
        assertEq(juryPool.getJuryReserves(), juryReservesBefore + jurorFee); // minority voter's fee has been added to jury reserves
    }

    function test_claimJurorFees() public {
        vm.pauseGasMetering();
        _petitionWithRevealedVotes(petitionId_MATIC);
        vm.resumeGasMetering();
        Court.Petition memory p = court.getPetition(petitionId_MATIC);
        Court.Jury memory jury = court.getJury(p.petitionId);
        uint256 feeOwed = court.getJurorFeesOwed(jury.confirmedJurors[0]);
        uint256 jurorBalBefore = jury.confirmedJurors[0].balance;
        vm.expectEmit(true, false, false, true);
        emit JurorFeesClaimed(jury.confirmedJurors[0], feeOwed);
        vm.prank(jury.confirmedJurors[0]);
        court.claimJurorFees();
        assertEq(jury.confirmedJurors[0].balance, jurorBalBefore + feeOwed);
        assertEq(court.getJurorFeesOwed(jury.confirmedJurors[0]), 0);
    }

    function test_claimJurorFees_revert() public {
        // no fees owed
        assertEq(court.getJurorFeesOwed(alice), 0);
        vm.expectRevert(Court.Court__NoJurorFeesOwed.selector);
        vm.prank(alice);
        court.claimJurorFees();
    }

    ///////////////////////////
    ///   JURY EXCEPTIONS   ///
    ///////////////////////////
    
    function test_drawAdditionalJurors() public {
        vm.pauseGasMetering();
        _petitionWithDrawnJury(petitionId_ERC20);
        vm.resumeGasMetering();
        Court.Petition memory p = court.getPetition(petitionId_ERC20);
        Court.Jury memory jury = court.getJury(p.petitionId);
        uint256 numDrawnJurorsBefore = jury.drawnJurors.length;
        uint256 jurorStake = court.jurorFlatFee();
        address juror_one = jury.drawnJurors[0];
        vm.prank(juror_one);
        court.acceptCase{value: jurorStake}(p.petitionId);
        address juror_two = jury.drawnJurors[1];
        vm.prank(juror_two);
        court.acceptCase{value: jurorStake}(p.petitionId);
            // time passes, but not enough jurors have confirmed
        vm.warp(block.timestamp + court.JURY_SELECTION_PERIOD() + 1);
            // draw more jurors
        vm.expectEmit(true, false, false, false);
        emit AdditionalJurorDrawingInitiated(p.petitionId, 42);
        vm.recordLogs();
        court.drawAdditionalJurors(p.petitionId);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[1].data));
        vrf.fulfillRandomWords(requestId, address(court));
        jury = court.getJury(p.petitionId);
        // number of drawn jurors has increased
        assertEq(jury.drawnJurors.length, numDrawnJurorsBefore + court.jurorsNeeded(p.petitionId) * 2);
        // no duplicates
        for(uint i; i < jury.drawnJurors.length; ++i) {
            for(uint j; j < jury.drawnJurors.length; ++j) {
                if(i != j) assertFalse(jury.drawnJurors[i] == jury.drawnJurors[j]);
            }
        }
    }

    function test_drawAdditionalJurors_revert() public {
        Court.Petition memory p = court.getPetition(petitionId_ERC20);
        // wrong phase 
        assertEq(uint(p.phase), uint(Court.Phase.Discovery));
        vm.expectRevert(Court.Court__OnlyDuringJurySelection.selector);
        court.drawAdditionalJurors(p.petitionId);
        // jury selection period not over
        _petitionWithDrawnJury(p.petitionId);
        vm.expectRevert(Court.Court__InitialSelectionPeriodStillOpen.selector);
        court.drawAdditionalJurors(p.petitionId);
        // already redrawn
            // time passes, but not enough jurors have confirmed
        vm.warp(block.timestamp + court.JURY_SELECTION_PERIOD() + 1);
            // additional drawing
        vm.recordLogs();
        court.drawAdditionalJurors(p.petitionId);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[1].data));
        vrf.fulfillRandomWords(requestId, address(court));
        vm.expectRevert(Court.Court__JuryAlreadyRedrawn.selector);
        court.drawAdditionalJurors(p.petitionId);
    }

    function test_removeJurorNoCommit() public {
        vm.pauseGasMetering();
        _petitionWithConfirmedJury(petitionId_MATIC);
        Court.Petition memory petition = court.getPetition(petitionId_MATIC);
            // 2 jurors commit votes
        Court.Jury memory jury = court.getJury(petition.petitionId);
        bytes32 commit = keccak256(abi.encodePacked(juror0_vote, "someSalt"));
        vm.prank(jury.confirmedJurors[0]);
        court.commitVote(petition.petitionId, commit);
        commit = keccak256(abi.encodePacked(juror1_vote, "someSalt"));
        vm.prank(jury.confirmedJurors[1]);
        court.commitVote(petition.petitionId, commit);
        vm.resumeGasMetering();
            // voting period passes
        vm.warp(block.timestamp + court.VOTING_PERIOD() + 1);
        address delinquentJuror = jury.confirmedJurors[2];
        assertEq(uint(court.getCommit(delinquentJuror, petition.petitionId)), 0); // juror[2] has not voted
        uint256 confirmedJurorsLengthBefore = jury.confirmedJurors.length;
        uint256 drawnJurorsLengthBefore = jury.drawnJurors.length;
        uint256 stakeForfeit = court.getJurorStakeHeld(delinquentJuror, petition.petitionId);
        uint256 juryPoolBalBefore = juryPool.getJuryReserves();
        vm.expectEmit(true, true, false, true);
        emit JurorRemoved(petition.petitionId, delinquentJuror, stakeForfeit);
        court.removeJurorNoCommit(petition.petitionId, delinquentJuror);    
        // juror stake has been forfeited and transfered to jury pool fund
        assertEq(court.getJurorStakeHeld(delinquentJuror, petition.petitionId), 0);
        assertEq(juryPool.getJuryReserves(), juryPoolBalBefore + stakeForfeit);
        // juror has been removed from jury
        jury = court.getJury(petition.petitionId);
        assertEq(jury.confirmedJurors.length, confirmedJurorsLengthBefore - 1);
        assertEq(jury.drawnJurors.length, drawnJurorsLengthBefore - 1);
        assertEq(court.isConfirmedJuror(petition.petitionId, delinquentJuror), false);
        for(uint i; i < jury.drawnJurors.length; ++i) {
            assertFalse(jury.drawnJurors[i] == delinquentJuror);
        }
        // new voting period has been initiated
        petition = court.getPetition(petition.petitionId);
        assertEq(petition.votingStart, block.timestamp);
    }

    // function test_removeJurorNoCommit_revert() public {}

    // function test_removeJurorNoCommit_new_juror_can_confirm_and_vote() public {}

    function test_delinquentReveal_majority() public {
        vm.pauseGasMetering();
        _petitionWithCommittedVotes(petitionId_MATIC);
            // juror0 and juror1 both vote 'true' and reveal --- there is a majority even without juror2
        Court.Petition memory petition = court.getPetition(petitionId_MATIC);
        Court.Jury memory jury = court.getJury(petition.petitionId);
        vm.prank(jury.confirmedJurors[0]);
        court.revealVote(petition.petitionId, juror0_vote, "someSalt");
        vm.prank(jury.confirmedJurors[1]);
        court.revealVote(petition.petitionId, juror1_vote, "someSalt");
            // ruling period passes
        vm.warp(block.timestamp + court.RULING_PERIOD() + 1);
        vm.resumeGasMetering();
        uint256 juror0_FeesOwedBefore = court.getJurorFeesOwed(jury.confirmedJurors[0]);
        uint256 juror1_FeesOwedBefore = court.getJurorFeesOwed(jury.confirmedJurors[1]);
        uint256 juryPoolReservesBefore = juryPool.getJuryReserves();
        address delinquentJuror = jury.confirmedJurors[2];
        assertEq(court.getJurorStakeHeld(delinquentJuror, petition.petitionId), court.jurorFlatFee());
        vm.expectEmit(true, false, false, true);
        emit VerdictReached(petition.petitionId, true, 2);
        vm.expectEmit(true, false, false, true);
        emit DelinquentReveal(petition.petitionId, false);
        court.delinquentReveal(petition.petitionId);
        // juror2 has forfeitted stake
        assertEq(court.getJurorStakeHeld(delinquentJuror, petition.petitionId), 0);
        assertEq(juryPool.getJuryReserves(), juryPoolReservesBefore + court.jurorFlatFee());
        // verdict has been rendered 
        petition = court.getPetition(petition.petitionId);
        assertEq(petition.verdictRenderedDate, block.timestamp);
        assertEq(uint(petition.phase), uint(Court.Phase.Verdict));
        assertEq(petition.petitionGranted, true);
        // jurors 0 & 1 fees have been allocated
        assertEq(court.getJurorFeesOwed(jury.confirmedJurors[0]), juror0_FeesOwedBefore + court.jurorFlatFee());
        assertEq(court.getJurorFeesOwed(jury.confirmedJurors[1]), juror1_FeesOwedBefore + court.jurorFlatFee());
    }

    function test_delinquentReveal_no_majority() public {
        vm.pauseGasMetering();
        _petitionWithCommittedVotes(petitionId_MATIC);
            // juror1 and juror2 both reveal (true and false) - case is now deadlocked
        Court.Petition memory petition = court.getPetition(petitionId_MATIC);
        Court.Jury memory jury = court.getJury(petition.petitionId);
        vm.prank(jury.confirmedJurors[1]);
        court.revealVote(petition.petitionId, juror1_vote, "someSalt");
        vm.prank(jury.confirmedJurors[2]);
        court.revealVote(petition.petitionId, juror2_vote, "someSalt");
            // ruling period passes
        vm.warp(block.timestamp + court.RULING_PERIOD() + 1);
        vm.resumeGasMetering();

        address delinquentJuror = jury.confirmedJurors[0];
        uint256 deliquentJurorStakeBefore = court.getJurorStakeHeld(delinquentJuror, petition.petitionId);
        uint256 juror1_reimbursementBefore = court.getJurorFeeReimbursementOwed(jury.confirmedJurors[1]);
        uint256 juror2_reimbursementBefore = court.getJurorFeeReimbursementOwed(jury.confirmedJurors[2]);
        uint256 juryPoolReservesBefore = juryPool.getJuryReserves();
        vm.expectEmit(true, true, false, true);
        emit JurorFeeReimbursementOwed(
            petition.petitionId, 
            jury.confirmedJurors[1], 
            court.jurorFlatFee()
        );
        vm.expectEmit(true, true, false, true);
        emit JurorFeeReimbursementOwed(
            petition.petitionId, 
            jury.confirmedJurors[2], 
            court.jurorFlatFee()
        );
        vm.expectEmit(true, false, false, false);
        emit CaseRestarted(petition.petitionId, 42);
        vm.expectEmit(true, false, false, true);
        emit DelinquentReveal(petition.petitionId, true);
        vm.recordLogs();
        court.delinquentReveal(petition.petitionId);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[4].data));
        vrf.fulfillRandomWords(requestId, address(court));
        // juror reimbursement for revealing jurors has been recorder 
        assertEq(court.getJurorFeeReimbursementOwed(jury.confirmedJurors[1]), juror1_reimbursementBefore + court.jurorFlatFee());
        assertEq(court.getJurorFeeReimbursementOwed(jury.confirmedJurors[2]), juror2_reimbursementBefore + court.jurorFlatFee());
        // delinquent juror has lost stake
        assertEq(court.getJurorStakeHeld(delinquentJuror, petition.petitionId), deliquentJurorStakeBefore - court.jurorFlatFee());
        // forfettied stake has been transferred to pool reserves
        assertEq(juryPool.getJuryReserves(), juryPoolReservesBefore + court.jurorFlatFee());
        // case has been restarted (with arbitration fees still in place)
        petition = court.getPetition(petition.petitionId);
        assertEq(uint(petition.phase), uint(Court.Phase.JurySelection));
        assertEq(petition.selectionStart, block.timestamp);
        assertEq(court.getFeesHeld(petition.petitionId), petition.arbitrationFee * 2);
    }

    function test_delinquentReveal_revert() public {
        vm.pauseGasMetering();
        _petitionWithConfirmedJury(petitionId_ERC20);
        Court.Petition memory petition = court.getPetition(petitionId_ERC20);
        Court.Jury memory jury = court.getJury(petition.petitionId);
        vm.resumeGasMetering();
        // not all votes committed
            // 2 jurors commit
        bytes32 commit = keccak256(abi.encodePacked(juror0_vote, "someSalt"));
        vm.prank(jury.confirmedJurors[0]);
        court.commitVote(petition.petitionId, commit);
        commit = keccak256(abi.encodePacked(juror1_vote, "someSalt"));
        vm.prank(jury.confirmedJurors[1]);
        court.commitVote(petition.petitionId, commit);
        vm.expectRevert(Court.Court__OnlyDuringRuling.selector);
        court.delinquentReveal(petition.petitionId);
        // ruling period still active
            // last juror commits
        commit = keccak256(abi.encodePacked(juror2_vote, "someSalt"));
        vm.prank(jury.confirmedJurors[2]);
        court.commitVote(petition.petitionId, commit);
        petition = court.getPetition(petition.petitionId);
        assertEq(uint(petition.phase), uint(Court.Phase.Ruling));
        vm.expectRevert(Court.Court__RulingPeriodStillActive.selector);
        court.delinquentReveal(petition.petitionId);
        // no delinquent reveals
            // ruling period passes
        vm.warp(block.timestamp + court.RULING_PERIOD() + 1);
            // jurors reveal
        vm.prank(jury.confirmedJurors[0]);
        court.revealVote(petition.petitionId, juror0_vote, "someSalt");
        vm.prank(jury.confirmedJurors[1]);
        court.revealVote(petition.petitionId, juror1_vote, "someSalt");
        vm.prank(jury.confirmedJurors[2]);
        court.revealVote(petition.petitionId, juror2_vote, "someSalt");
        vm.expectRevert(Court.Court__OnlyDuringRuling.selector);
        court.delinquentReveal(petition.petitionId);
    }

    ///////////////////////////////
    ///   GOVERNANCE & CONFIG   ///
    ///////////////////////////////

    function test_setJurorFlatFee() public {
        uint256 newFlatFee = 100 ether;
        vm.prank(admin1);
        bytes memory data = abi.encodeWithSignature("setJurorFlatFee(uint256)", newFlatFee);
        uint256 txIndex = governor.proposeTransaction(address(court), 0, data);
        util_executeGovernorTx(txIndex);
        assertEq(court.jurorFlatFee(), newFlatFee);
    }

}
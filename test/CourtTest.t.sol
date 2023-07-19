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
        Court.Petition memory p = court.getPetition(petitionId_MATIC);
        // buyer pays
        vm.pauseGasMetering();
        test_payArbitrationFee();
        vm.resumeGasMetering();
        vm.prank(buyer);
        court.submitAdditionalEvidence(p.petitionId, additionalEvidence);
        p = court.getPetition(petitionId_MATIC);
        assertEq(p.evidence[2], additionalEvidence[0]);
        assertEq(p.evidence[3], additionalEvidence[1]);
    }

    // function test_submitAdditionalEvidence_revert() public {
    //     Court.Petition memory p = court.getPetition(petitionId_MATIC);
    //     // fee not paid
    //     assertEq(p.feePaidDefendant, false);
    //     vm.expectRevert(Court.Court__ArbitrationFeeNotPaid.selector);
    //     vm.prank(p.defendant);
    //     court.submitAdditionalEvidence(p.petitionId, additionalEvidence);
    //     // wrong phase

    // }

    function test_reclaimArbitrationFee() public {
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

    function test_reclaimArbitrationFee_revert() public {
        vm.pauseGasMetering();
        _petitionWithRevealedVotes(petitionId_MATIC);
        vm.resumeGasMetering();
        Court.Petition memory p = court.getPetition(petitionId_MATIC);
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
        // wrong phase 
        vm.expectRevert(Court.Court__ArbitrationFeeCannotBeReclaimed.selector);
        court.reclaimArbitrationFee(petitionId_ERC20);
    }

    // function test_appeal() public {
        
    // }

    function test_dismissUnpaidCase() public {
        Court.Petition memory p = court.getPetition(petitionId_MATIC);
        vm.warp(block.timestamp + p.discoveryStart + court.DISCOVERY_PERIOD() + 1);
        vm.expectEmit(true, false, false, false);
        emit CaseDismissed(p.petitionId);
        court.dismissUnpaidCase(p.petitionId);
        p = court.getPetition(petitionId_MATIC);
        assertEq(uint(p.phase), uint(Court.Phase.Dismissed));
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

    // test (and implement) juror redraw (later)//////

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
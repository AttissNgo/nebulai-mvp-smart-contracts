// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/Interfaces/IEscrow.sol";
import "forge-std/console.sol";

contract CourtJuryTest is Test, TestSetup {

    event JuryDrawn(uint256 indexed petitionId, bool isRedraw);
    event JurorConfirmed(uint256 indexed petitionId, address jurorAddress);
    event VotingInitiated(uint256 indexed petitionId);
    event VoteCommitted(uint256 indexed petitionId, address indexed juror, bytes32 commit);
    event RulingInitiated(uint256 indexed petitionId);
    event VoteRevealed(uint256 indexed petitionId, address indexed juror, bool vote);
    event VerdictReached(uint256 indexed petitionId, bool verdict, uint256 majorityVotes);
    event JurorFeesClaimed(address indexed juror, uint256 amount);
    event AdditionalJurorDrawingInitiated(uint256 indexed petitionId, uint256 requestId);
    event AdditionalJurorsAssigned(uint256 indexed petitionId, address[] assignedJurors);
    event JurorRemoved(uint256 indexed petitionId, address indexed juror);
    event DelinquentReveal(uint256 indexed petitionId, bool deadlocked);
    event ArbiterAssigned(uint256 indexed petitionId, address indexed arbiter);
    event ArbiterVote(uint256 indexed petitionId, address indexed arbiter, bool vote);

    function setUp() public {
        _setUp();
        _whitelistUsers();
        _registerJurors();
        _initializeTestProjects();
        _initializeArbitrationProjects();
    }

    function test_selectJury() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_discovery_MATIC));
        vm.prank(petition.plaintiff);
        court.payArbitrationFee{value: petition.arbitrationFee}(petition.petitionId, evidence1);
        vm.recordLogs();
        vm.prank(petition.defendant);
        court.payArbitrationFee{value: petition.arbitrationFee}(petition.petitionId, evidence2);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[2].data));
        vm.expectEmit(true, false, false, true);
        emit JuryDrawn(petition.petitionId, false);
        vrf.fulfillRandomWords(requestId, address(court));

        // jury drawn
        Court.Jury memory jury = court.getJury(petition.petitionId);
        assertEq(jury.confirmedJurors.length, 0);
        for(uint i; i < jury.drawnJurors.length; ++i) {
            for(uint j; j < jury.drawnJurors.length; ++j) {
                if(i != j) {
                    assertFalse(jury.drawnJurors[i] == jury.drawnJurors[j]);
                    assertFalse(jury.drawnJurors[i] == petition.plaintiff);
                    assertFalse(jury.drawnJurors[i] == petition.defendant);
                    assertTrue(juryPool.isEligible(jury.drawnJurors[i]));
                }
            }
        }
    }

    function test_acceptCase() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_jurySelection_MATIC));
        Court.Jury memory jury = court.getJury(petition.petitionId);
        assertEq(jury.confirmedJurors.length, 0);
        assertEq(court.getJurorStakeHeld(jury.drawnJurors[0], petition.petitionId), 0);
        uint256 courtBalBefore = address(court).balance;

        uint256 stake = court.jurorFlatFee();
        vm.expectEmit(true, false, false, true);
        emit JurorConfirmed(petition.petitionId, jury.drawnJurors[0]);
        vm.prank(jury.drawnJurors[0]);
        court.acceptCase{value: stake}(petition.petitionId);

        jury = court.getJury(petition.petitionId);
        assertEq(jury.confirmedJurors[0], jury.drawnJurors[0]);
        assertEq(court.getJurorStakeHeld(jury.confirmedJurors[0], petition.petitionId), stake);
        assertEq(address(court).balance, courtBalBefore + stake);
    }

    function test_acceptCase_revert() public {
        uint256 stake = court.jurorFlatFee();
        // all seats filled
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_confirmedJury_MATIC));
        Court.Jury memory jury = court.getJury(petition.petitionId);
        vm.expectRevert(Court.Court__JurorSeatsFilled.selector);
        vm.prank(jury.drawnJurors[jury.drawnJurors.length - 1]);
        court.acceptCase{value: stake}(petition.petitionId);
        // already accepted
        petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_jurySelection_ERC20));
        jury = court.getJury(petition.petitionId);
        vm.prank(jury.drawnJurors[0]);
        court.acceptCase{value: stake}(petition.petitionId);
        vm.expectRevert(Court.Court__AlreadyConfirmedJuror.selector);
        vm.prank(jury.drawnJurors[0]);
        court.acceptCase{value: stake}(petition.petitionId);  
        // insufficient stake 
        vm.expectRevert(Court.Court__InsufficientJurorStake.selector);
        vm.prank(jury.drawnJurors[1]);
        court.acceptCase{value: stake - 1}(petition.petitionId);  
        // not active juror
        vm.prank(jury.drawnJurors[1]);
        juryPool.pauseJuror();
        vm.expectRevert(Court.Court__InvalidJuror.selector);
        vm.prank(jury.drawnJurors[1]);
        court.acceptCase{value: stake}(petition.petitionId);  
    }

    function test_juryAssembled() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_jurySelection_MATIC));
        Court.Jury memory jury = court.getJury(petition.petitionId);
        uint256 jurorsNeeded = court.jurorsNeeded(petition.petitionId);
        uint256 stake = court.jurorFlatFee();
        for(uint i; i < jury.drawnJurors.length; ++i) {
            if(court.getJury(petition.petitionId).confirmedJurors.length == jurorsNeeded - 1) {
                vm.expectEmit(true, false, false, false);
                emit VotingInitiated(petition.petitionId);
            }
            vm.prank(jury.drawnJurors[i]);
            court.acceptCase{value: stake}(petition.petitionId);
            jury = court.getJury(petition.petitionId);
            if(jury.confirmedJurors.length == jurorsNeeded) break;
        }
        petition = court.getPetition(petition.petitionId);
        assertEq(uint(petition.phase), uint(Phase.Voting));
    }

    function test_commitVote() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_confirmedJury_MATIC));
        Court.Jury memory jury = court.getJury(petition.petitionId);
        assertEq(court.getCommit(jury.confirmedJurors[0], petition.petitionId), 0x0);
        
        bytes32 commit = keccak256(abi.encodePacked(true, "someSalt"));
        vm.expectEmit(true, true, false, true);
        emit VoteCommitted(petition.petitionId, jury.confirmedJurors[0], commit);
        vm.prank(jury.confirmedJurors[0]);
        court.commitVote(petition.petitionId, commit);
        
        assertEq(court.getCommit(jury.confirmedJurors[0], petition.petitionId), commit);
    }

    function test_commitVote_revert() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_confirmedJury_MATIC));
        Court.Jury memory jury = court.getJury(petition.petitionId);
        bytes32 commit = keccak256(abi.encodePacked(true, "someSalt"));
        // not juror
        vm.expectRevert(Court.Court__InvalidJuror.selector);
        vm.prank(petition.plaintiff); // cannot be juror
        court.commitVote(petition.petitionId, commit);
        // already committed
        vm.prank(jury.confirmedJurors[0]);
        court.commitVote(petition.petitionId, commit);
        vm.expectRevert(Court.Court__JurorHasAlreadyCommmitedVote.selector);
        vm.prank(jury.confirmedJurors[0]);
        court.commitVote(petition.petitionId, commit);
        // invalid commit
        vm.expectRevert(Court.Court__InvalidCommit.selector);
        vm.prank(jury.confirmedJurors[1]);
        court.commitVote(petition.petitionId, 0x0);
        // cannot commit at wrong phase as there will be no confirmed jurors
        petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_jurySelection_ERC20));
        vm.expectRevert(Court.Court__InvalidJuror.selector);
        vm.prank(jury.drawnJurors[1]);
        court.commitVote(petition.petitionId, commit);
    }

    function test_allVotesCommitted() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_confirmedJury_MATIC));
        Court.Jury memory jury = court.getJury(petition.petitionId);
        bytes32 commit = keccak256(abi.encodePacked(true, "someSalt"));
        vm.prank(jury.confirmedJurors[0]);
        court.commitVote(petition.petitionId, commit);
        vm.prank(jury.confirmedJurors[1]);
        court.commitVote(petition.petitionId, commit);

        vm.expectEmit(true, false, false, false);
        emit RulingInitiated(petition.petitionId);
        vm.prank(jury.confirmedJurors[2]);
        court.commitVote(petition.petitionId, commit);
        
        petition = court.getPetition(petition.petitionId);
        assertEq(uint(petition.phase), uint(Phase.Ruling));
        assertEq(petition.rulingStart, block.timestamp);
    }

    function test_revealVote() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_committedVotes_ERC20));
        Court.Jury memory jury = court.getJury(petition.petitionId);
        address juror = jury.confirmedJurors[0];
        vm.expectRevert(Court.Court__VoteHasNotBeenRevealed.selector);
        court.getVote(juror, petition.petitionId);
        assertEq(court.hasRevealedVote(juror, petition.petitionId), false);
        assertEq(court.getJurorStakeHeld(juror, petition.petitionId), court.jurorFlatFee());
        uint256 jurorBalBefore = juror.balance;

        vm.expectEmit(true, true, false, true);
        emit VoteRevealed(petition.petitionId, juror, true);
        vm.prank(juror);
        court.revealVote(petition.petitionId, true, "someSalt");

        assertEq(court.getVote(juror, petition.petitionId), true);
        assertEq(court.hasRevealedVote(juror, petition.petitionId), true);
        assertEq(court.getJurorStakeHeld(juror, petition.petitionId), 0);
        assertEq(juror.balance, jurorBalBefore + court.jurorFlatFee());
    }

    function test_revealVote_revert() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_committedVotes_ERC20));
        Court.Jury memory jury = court.getJury(petition.petitionId);
        address juror = jury.confirmedJurors[0];
        // invalid juror
        vm.expectRevert(Court.Court__InvalidJuror.selector);
        vm.prank(petition.plaintiff);
        court.revealVote(petition.petitionId, true, "someSalt");
        // reveal doesn't match commit
        vm.expectRevert(Court.Court__RevealDoesNotMatchCommit.selector);
        vm.prank(juror);
        court.revealVote(petition.petitionId, false, "someSalt"); // incorrect vote
        vm.expectRevert(Court.Court__RevealDoesNotMatchCommit.selector);
        vm.prank(juror);
        court.revealVote(petition.petitionId, true, "WRONG_Salt"); // incorrect salt
        // already revealed
        vm.prank(juror);
        court.revealVote(petition.petitionId, true, "someSalt");
        vm.expectRevert(Court.Court__AlreadyRevealed.selector);
        vm.prank(juror);
        court.revealVote(petition.petitionId, true, "someSalt");
        // wrong phase
        petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_confirmedJury_MATIC));
        jury = court.getJury(petition.petitionId);
        juror = jury.confirmedJurors[0];
        vm.expectRevert(Court.Court__CannotRevealBeforeAllVotesCommitted.selector);
        vm.prank(juror);
        court.revealVote(petition.petitionId, true, "someSalt");
    }

    function test_renderVerdict() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_committedVotes_ERC20));
        Court.Jury memory jury = court.getJury(petition.petitionId);
        uint256 juror0FeesBefore = court.getJurorFeesOwed(jury.confirmedJurors[0]);
        uint256 juror1FeesBefore = court.getJurorFeesOwed(jury.confirmedJurors[1]);
        uint256 juror2FeesBefore = court.getJurorFeesOwed(jury.confirmedJurors[2]);
        uint256 juryReserveBefore = juryPool.getJuryReserve();
        uint256 juryPoolBalBefore = address(juryPool).balance;
        assertEq(court.getFeesHeld(petition.petitionId), petition.arbitrationFee * 2);

        vm.prank(jury.confirmedJurors[0]);
        court.revealVote(petition.petitionId, true, "someSalt");
        vm.prank(jury.confirmedJurors[1]);
        court.revealVote(petition.petitionId, true, "someSalt");
        vm.expectEmit(true, false, false, true);
        emit VerdictReached(petition.petitionId, true, 2);
        vm.prank(jury.confirmedJurors[2]);
        court.revealVote(petition.petitionId, false, "someSalt");

        petition = court.getPetition(petition.petitionId);
        assertEq(uint(petition.phase), uint(Phase.Verdict));
        assertEq(petition.petitionGranted, true);
        assertEq(petition.verdictRenderedDate, block.timestamp);
        // juror fees owed recorded correctly
        uint256 jurorFee = petition.arbitrationFee / court.jurorsNeeded(petition.petitionId);
        assertEq(court.getJurorFeesOwed(jury.confirmedJurors[0]), juror0FeesBefore + jurorFee);
        assertEq(court.getJurorFeesOwed(jury.confirmedJurors[1]), juror1FeesBefore + jurorFee);
        assertEq(court.getJurorFeesOwed(jury.confirmedJurors[2]), juror2FeesBefore); // minority vote, nothing owed
        // minority juror's fee transferred to to jury reserve
        assertEq(juryPool.getJuryReserve(), juryReserveBefore + jurorFee);
        assertEq(address(juryPool).balance, juryPoolBalBefore + jurorFee);
        // fees held now only represents winner's fee - loser's fee has been distributed to jurors and jury reserve
        assertEq(court.getFeesHeld(petition.petitionId), petition.arbitrationFee);

        /////////
        // test with full majority
        /////////
        petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_confirmedJury_MATIC));
        jury = court.getJury(petition.petitionId);
        juror0FeesBefore = court.getJurorFeesOwed(jury.confirmedJurors[0]);
        juror1FeesBefore = court.getJurorFeesOwed(jury.confirmedJurors[1]);
        juror2FeesBefore = court.getJurorFeesOwed(jury.confirmedJurors[2]);
        juryReserveBefore = juryPool.getJuryReserve();
        juryPoolBalBefore = address(juryPool).balance;
        assertEq(court.getFeesHeld(petition.petitionId), petition.arbitrationFee * 2);

        bool[3] memory voteInputs = [false, false, false];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customRuling(id_arbitration_confirmedJury_MATIC, votes, true);
        
        petition = court.getPetition(petition.petitionId);
        // juror fees owed recorded correctly
        assertEq(court.getJurorFeesOwed(jury.confirmedJurors[0]), juror0FeesBefore + jurorFee);
        assertEq(court.getJurorFeesOwed(jury.confirmedJurors[1]), juror1FeesBefore + jurorFee);
        assertEq(court.getJurorFeesOwed(jury.confirmedJurors[2]), juror2FeesBefore + jurorFee); 
        // no transfer to jury reserve
        assertEq(juryPool.getJuryReserve(), juryReserveBefore);
        assertEq(address(juryPool).balance, juryPoolBalBefore);
        // fees held now only represents winner's fee - loser's fee has been distributed to jurors
        assertEq(court.getFeesHeld(petition.petitionId), petition.arbitrationFee);
    }

    function test_claimJurorFees() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_committedVotes_ERC20));
        Court.Jury memory jury = court.getJury(petition.petitionId);
        uint256 juror0BalBefore = jury.confirmedJurors[0].balance;
        uint256 juror1BalBefore = jury.confirmedJurors[1].balance;

        vm.prank(jury.confirmedJurors[0]);
        court.revealVote(petition.petitionId, true, "someSalt");
        vm.prank(jury.confirmedJurors[1]);
        court.revealVote(petition.petitionId, true, "someSalt");
        vm.expectEmit(true, false, false, true);
        emit VerdictReached(petition.petitionId, true, 2);
        vm.prank(jury.confirmedJurors[2]);
        court.revealVote(petition.petitionId, false, "someSalt");

        uint256 jurorFee = petition.arbitrationFee / court.jurorsNeeded(petition.petitionId);
        uint256 stake = petition.arbitrationFee / court.jurorsNeeded(petition.petitionId);
        vm.expectEmit(true, false, false, true);
        emit JurorFeesClaimed(jury.confirmedJurors[0], jurorFee);
        vm.prank(jury.confirmedJurors[0]);
        court.claimJurorFees();
        assertEq(court.getJurorFeesOwed(jury.confirmedJurors[0]), 0);
        assertEq(jury.confirmedJurors[0].balance, juror0BalBefore + jurorFee + stake);

        vm.expectEmit(true, false, false, true);
        emit JurorFeesClaimed(jury.confirmedJurors[1], jurorFee);
        vm.prank(jury.confirmedJurors[1]);
        court.claimJurorFees();
        assertEq(court.getJurorFeesOwed(jury.confirmedJurors[1]), 0);
        assertEq(jury.confirmedJurors[1].balance, juror1BalBefore + jurorFee + stake);

        vm.expectRevert(Court.Court__NoJurorFeesOwed.selector);
        vm.prank(jury.confirmedJurors[2]); // minority - nothing owed
        court.claimJurorFees();
    }

    ///////////////////////////
    ///   JURY EXCEPTIONS   ///
    ///////////////////////////

    function test_drawAdditionalJurors() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_jurySelection_MATIC));
        Court.Jury memory jury = court.getJury(petition.petitionId);
        assertEq(jury.drawnJurors.length, court.jurorsNeeded(petition.petitionId) * 3);
        assertEq(jury.confirmedJurors.length, 0);
        vm.warp(block.timestamp + court.JURY_SELECTION_PERIOD() + 1);
        
        vm.expectEmit(true, false, false, false);
        emit AdditionalJurorDrawingInitiated(petition.petitionId, 42 /* cannot be known */);
        vm.recordLogs();
        court.drawAdditionalJurors(petition.petitionId);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[1].data));
        vrf.fulfillRandomWords(requestId, address(court));

        jury = court.getJury(petition.petitionId);
        assertEq(jury.drawnJurors.length, court.jurorsNeeded(petition.petitionId) * 5);
        for(uint i; i < jury.drawnJurors.length; ++i) {
            for(uint j; j < jury.drawnJurors.length; ++j) {
                if(i != j) {
                    assertTrue(jury.drawnJurors[i] != jury.drawnJurors[j]);
                }
            }
        }
    }

    function test_drawAdditionalJurors_revert() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_discovery_ERC20));
        // wrong phase
        vm.expectRevert(Court.Court__OnlyDuringJurySelection.selector);
        court.drawAdditionalJurors(petition.petitionId);
        // initial selection still open
        petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_jurySelection_MATIC));
        vm.expectRevert(Court.Court__InitialSelectionPeriodStillOpen.selector);
        court.drawAdditionalJurors(petition.petitionId);
        // already redrawn
        vm.warp(block.timestamp + court.JURY_SELECTION_PERIOD() + 1);
        vm.recordLogs();
        court.drawAdditionalJurors(petition.petitionId);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[1].data));
        vrf.fulfillRandomWords(requestId, address(court));
        vm.expectRevert(Court.Court__JuryAlreadyRedrawn.selector);
        court.drawAdditionalJurors(petition.petitionId);
    }

    function test_assignAdditionalJurors() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_jurySelection_MATIC));
        vm.warp(block.timestamp + court.JURY_SELECTION_PERIOD() + 1);
        vm.recordLogs();
        court.drawAdditionalJurors(petition.petitionId);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[1].data));
        vrf.fulfillRandomWords(requestId, address(court));

        address assignedJuror1 = vm.addr(10000001);
        address assignedJuror2 = vm.addr(10000002);
        address assignedJuror3 = vm.addr(10000003);
        address[3] memory ringers = [assignedJuror1, assignedJuror2, assignedJuror3];
        uint256 stake = juryPool.minimumStake();
        for(uint i; i < ringers.length; ++i) {
            vm.deal(ringers[i], 10000 ether);
            vm.prank(admin1);
            whitelist.approveAddress(ringers[i]);
            vm.prank(ringers[i]);
            juryPool.registerAsJuror{value: stake}();
        }
        address[] memory assignedJurors = new address[](ringers.length);
        for(uint i; i < assignedJurors.length; ++i) {
            assignedJurors[i] = ringers[i];
        } 
        vm.expectEmit(true, false, false, true);
        emit AdditionalJurorsAssigned(petition.petitionId, assignedJurors);
        vm.prank(admin1);
        court.assignAdditionalJurors(petition.petitionId, assignedJurors);

        Court.Jury memory jury = court.getJury(petition.petitionId);
        assertEq(jury.drawnJurors.length, assignedJurors.length + (court.jurorsNeeded(petition.petitionId) * 5));
        uint256 jurorFee = court.jurorFlatFee();
        for(uint i; i < assignedJurors.length; ++i) {
            vm.prank(assignedJurors[i]);
            court.acceptCase{value: jurorFee}(petition.petitionId);
            assertEq(court.isConfirmedJuror(petition.petitionId, assignedJurors[i]), true);
        }
    }

    function test_assignAdditionalJurors_revert() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_discovery_MATIC));
        address[] memory additionalJurors = new address[](1);
        additionalJurors[0] = admin1;
        // wrong phase
        vm.expectRevert(Court.Court__OnlyDuringJurySelection.selector);
        vm.prank(admin1);
        court.assignAdditionalJurors(petition.petitionId, additionalJurors);
        // selection period still open
        petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_jurySelection_MATIC));
        vm.expectRevert(Court.Court__InitialSelectionPeriodStillOpen.selector);
        vm.prank(admin1);
        court.assignAdditionalJurors(petition.petitionId, additionalJurors);
        // jury not redrawn
        vm.warp(block.timestamp + court.JURY_SELECTION_PERIOD() + 1);
        vm.expectRevert(Court.Court__JuryNotRedrawn.selector);
        vm.prank(admin1);
        court.assignAdditionalJurors(petition.petitionId, additionalJurors);
        // not admin
        vm.recordLogs();
        court.drawAdditionalJurors(petition.petitionId);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[1].data));
        vrf.fulfillRandomWords(requestId, address(court));
        vm.expectRevert(Court.Court__OnlyAdmin.selector);
        vm.prank(carlos);
        court.assignAdditionalJurors(petition.petitionId, additionalJurors);
        // invalid juror - confirmed juror
        Court.Jury memory jury = court.getJury(petition.petitionId);
        uint256 jurorFee = court.jurorFlatFee();
        vm.prank(jury.drawnJurors[0]);
        court.acceptCase{value: jurorFee}(petition.petitionId);
        jury = court.getJury(petition.petitionId);
        additionalJurors[0] = jury.confirmedJurors[0];
        vm.expectRevert(Court.Court__InvalidJuror.selector);
        vm.prank(admin1);
        court.assignAdditionalJurors(petition.petitionId, additionalJurors);
        // invalid juror - ineligible
        uint256 stake = juryPool.getJurorStake(admin1);
        vm.prank(admin1);
        juryPool.withdrawStake(stake);
        additionalJurors[0] = admin1;
        vm.expectRevert(Court.Court__InvalidJuror.selector);
        vm.prank(admin1);
        court.assignAdditionalJurors(petition.petitionId, additionalJurors);
        // invalid juror - plaintiff or defendant
        additionalJurors[0] = petition.plaintiff;
        vm.expectRevert(Court.Court__InvalidJuror.selector);
        vm.prank(admin1);
        court.assignAdditionalJurors(petition.petitionId, additionalJurors);
    }

    function test_delinquentCommit() public {
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_confirmedJury_MATIC));
        Court.Jury memory jury = court.getJury(petition.petitionId);
        address juror1 = jury.confirmedJurors[1];
        address juror2 = jury.confirmedJurors[2];
        uint256 stake = court.jurorFlatFee();
            // juror 0 votes
        bytes32 commit = keccak256(abi.encodePacked(true, "someSalt"));
        vm.prank(jury.confirmedJurors[0]);
        court.commitVote(petition.petitionId, commit);
        vm.warp(block.timestamp + court.VOTING_PERIOD() + 1);
            // jurors 1 & 2 have not voted
        assertEq(court.getCommit(juror1, petition.petitionId), 0x0);
        assertEq(court.getCommit(juror2, petition.petitionId), 0x0);
        uint256 drawnJurorsBefore = jury.drawnJurors.length;
        uint256 confirmedJurorsBefore = jury.confirmedJurors.length;
        assertEq(court.getJurorStakeHeld(juror1, petition.petitionId), stake);
        assertEq(court.getJurorStakeHeld(juror2, petition.petitionId), stake);
        uint256 juryReserveBefore = juryPool.getJuryReserve();
        
        vm.expectEmit(true, true, false, false);
        emit JurorRemoved(petition.petitionId, juror1);
        vm.expectEmit(true, true, false, false);
        emit JurorRemoved(petition.petitionId, juror2);
        court.delinquentCommit(petition.petitionId);

        // jurors removed
        jury = court.getJury(petition.petitionId);
        assertEq(jury.drawnJurors.length, drawnJurorsBefore - 2);
        for(uint i; i < jury.drawnJurors.length; ++i) {
            assertTrue(jury.drawnJurors[i] != juror1);
            assertTrue(jury.drawnJurors[i] != juror2);
        }
        assertEq(jury.confirmedJurors.length, confirmedJurorsBefore - 2);
        assertEq(court.isConfirmedJuror(petition.petitionId, juror1), false);
        assertEq(court.isConfirmedJuror(petition.petitionId, juror2), false);
        // stakes transferred to jury pool
        assertEq(court.getJurorStakeHeld(juror1, petition.petitionId), 0);
        assertEq(court.getJurorStakeHeld(juror2, petition.petitionId), 0);
        assertEq(juryPool.getJuryReserve(), juryReserveBefore + stake + stake);
        // voting period restarted
        petition = court.getPetition(petition.petitionId);
        assertEq(petition.votingStart, block.timestamp);
    }

    function test_delinquentCommit_revert() public {
        // voting period still active
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_confirmedJury_MATIC));
        vm.expectRevert(Court.Court__VotingPeriodStillActive.selector);
        court.delinquentCommit(petition.petitionId);
        // no delinquent commits
        Court.Jury memory jury = court.getJury(petition.petitionId);
        bytes32 commit = keccak256(abi.encodePacked(true, "someSalt"));
        for(uint i; i < jury.confirmedJurors.length; ++i) {
            vm.prank(jury.confirmedJurors[i]);
            court.commitVote(petition.petitionId, commit);
        }
        vm.warp(block.timestamp + court.VOTING_PERIOD() + 1);
        vm.expectRevert(Court.Court__NoDelinquentCommits.selector);
        court.delinquentCommit(petition.petitionId);
    }

    function test_delinquentReveal_majority() public {
        vm.pauseGasMetering();
        bool[3] memory voteInputs = [false, true, true];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customRuling(id_arbitration_confirmedJury_MATIC, votes, false);
        vm.resumeGasMetering();
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_confirmedJury_MATIC));
        Court.Jury memory jury = court.getJury(petition.petitionId);
            // juror0 will be removed, resulting in a majority decision
        address juror0 = jury.confirmedJurors[0];
        address juror1 = jury.confirmedJurors[1];
        address juror2 = jury.confirmedJurors[2];
        vm.prank(juror1);
        court.revealVote(petition.petitionId, true, "someSalt");
        vm.prank(juror2);
        court.revealVote(petition.petitionId, true, "someSalt");
        assertTrue(court.hasRevealedVote(juror1, petition.petitionId));
        assertTrue(court.hasRevealedVote(juror2, petition.petitionId));
        uint256 stake = court.jurorFlatFee();
        uint256 drawnJurorsBefore = jury.drawnJurors.length;
        uint256 confirmedJurorsBefore = jury.confirmedJurors.length;
        assertEq(court.getJurorStakeHeld(juror0, petition.petitionId), stake);
        uint256 juryReserveBefore = juryPool.getJuryReserve();

        vm.warp(block.timestamp + court.VOTING_PERIOD() + 1);
        vm.expectEmit(true, false, false, true);
        emit VerdictReached(petition.petitionId, true, 2);
        vm.expectEmit(true, false, false, true);
        emit DelinquentReveal(petition.petitionId, false);
        court.delinquentReveal(petition.petitionId);

        // juror removed
        jury = court.getJury(petition.petitionId);
        assertEq(jury.drawnJurors.length, drawnJurorsBefore - 1);
        for(uint i; i < jury.drawnJurors.length; ++i) {
            assertFalse(jury.drawnJurors[i] == juror0);
        }
        assertEq(jury.confirmedJurors.length, confirmedJurorsBefore - 1);
        assertEq(court.isConfirmedJuror(petition.petitionId, juror0), false);
        // stake forfeitted
        assertEq(court.getJurorStakeHeld(juror0, petition.petitionId), 0);
        assertEq(juryPool.getJuryReserve(), juryReserveBefore + stake);
        
        // verdict rendered (majority)
        petition = court.getPetition(petition.petitionId);
        assertEq(uint(petition.phase), uint(Phase.Verdict));
        assertEq(petition.petitionGranted, true);
    }

    function test_delinquentReveal_tie() public {
        vm.pauseGasMetering();
        bool[3] memory voteInputs = [false, false, true];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customRuling(id_arbitration_confirmedJury_MATIC, votes, false);
        vm.resumeGasMetering();
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_confirmedJury_MATIC));
        Court.Jury memory jury = court.getJury(petition.petitionId);
            // juror0 will be removed, resulting in a majority decision
        address juror0 = jury.confirmedJurors[0];
        address juror1 = jury.confirmedJurors[1];
        address juror2 = jury.confirmedJurors[2];
        vm.prank(juror1);
        court.revealVote(petition.petitionId, false, "someSalt");
        vm.prank(juror2);
        court.revealVote(petition.petitionId, true, "someSalt");
        assertTrue(court.hasRevealedVote(juror1, petition.petitionId));
        assertTrue(court.hasRevealedVote(juror2, petition.petitionId));
        uint256 stake = court.jurorFlatFee();
        uint256 drawnJurorsBefore = jury.drawnJurors.length;
        uint256 confirmedJurorsBefore = jury.confirmedJurors.length;
        assertEq(court.getJurorStakeHeld(juror0, petition.petitionId), stake);
        uint256 juryReserveBefore = juryPool.getJuryReserve();

        vm.warp(block.timestamp + court.VOTING_PERIOD() + 1);
        // vm.expectEmit(true, false, false, true);
        // emit VerdictReached(petition.petitionId, true, 2);
        vm.expectEmit(true, false, false, true);
        emit DelinquentReveal(petition.petitionId, true);
        court.delinquentReveal(petition.petitionId);

        // juror removed
        jury = court.getJury(petition.petitionId);
        assertEq(jury.drawnJurors.length, drawnJurorsBefore - 1);
        for(uint i; i < jury.drawnJurors.length; ++i) {
            assertFalse(jury.drawnJurors[i] == juror0);
        }
        assertEq(jury.confirmedJurors.length, confirmedJurorsBefore - 1);
        assertEq(court.isConfirmedJuror(petition.petitionId, juror0), false);
        // stake forfeitted
        assertEq(court.getJurorStakeHeld(juror0, petition.petitionId), 0);
        assertEq(juryPool.getJuryReserve(), juryReserveBefore + stake);
        
        // no verdict rendered (tie)
        petition = court.getPetition(petition.petitionId);
        assertEq(uint(petition.phase), uint(Phase.Ruling));
        assertEq(petition.petitionGranted, false);
        assertEq(court.votesTied(petition.petitionId), true);
    }

    function test_delinquentReveal_revert() public {
        // wrong phase
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_confirmedJury_MATIC));
        vm.expectRevert(Court.Court__OnlyDuringRuling.selector);
        court.delinquentReveal(petition.petitionId);
        // ruling period still active
        vm.pauseGasMetering();
        bool[3] memory voteInputs = [false, false, true];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customRuling(id_arbitration_confirmedJury_MATIC, votes, false);
        vm.resumeGasMetering();
        petition = court.getPetition(petition.petitionId);
        assertTrue(block.timestamp < petition.rulingStart + court.RULING_PERIOD());
        vm.expectRevert(Court.Court__RulingPeriodStillActive.selector);
        court.delinquentReveal(petition.petitionId);
    }

    function test_assignArbiter() public {
        vm.pauseGasMetering();
        bool[3] memory voteInputs = [false, false, true];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customRuling(id_arbitration_confirmedJury_MATIC, votes, false);
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_confirmedJury_MATIC));
        Court.Jury memory jury = court.getJury(petition.petitionId);
        // juror0 will be removed, resulting in a tie
        address juror1 = jury.confirmedJurors[1];
        address juror2 = jury.confirmedJurors[2];
        vm.prank(juror1);
        court.revealVote(petition.petitionId, false, "someSalt");
        vm.prank(juror2);
        court.revealVote(petition.petitionId, true, "someSalt");
        vm.resumeGasMetering();
        vm.warp(block.timestamp + court.RULING_PERIOD() + 1);
        court.delinquentReveal(petition.petitionId);
        assertEq(court.arbiter(petition.petitionId), address(0));

        address arbiter = jury.drawnJurors[jury.drawnJurors.length -1]; // we know this juror is eligible
        vm.expectEmit(true, true, false, false);
        emit ArbiterAssigned(petition.petitionId, arbiter);
        vm.prank(admin1);
        court.assignArbiter(petition.petitionId, arbiter);

        assertEq(court.arbiter(petition.petitionId), arbiter);
    }

    function test_assignArbiter_revert() public {
        // case not deadlocked
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_confirmedJury_MATIC));
        vm.expectRevert(Court.Court__CaseNotDeadlocked.selector);
        vm.prank(admin1);
        court.assignArbiter(petition.petitionId, admin1);

        vm.pauseGasMetering();
        bool[3] memory voteInputs = [false, false, true];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customRuling(id_arbitration_confirmedJury_MATIC, votes, false);
        Court.Jury memory jury = court.getJury(petition.petitionId);
        address juror1 = jury.confirmedJurors[1];
        address juror2 = jury.confirmedJurors[2];
        vm.prank(juror1);
        court.revealVote(petition.petitionId, false, "someSalt");
        vm.prank(juror2);
        court.revealVote(petition.petitionId, true, "someSalt");
        vm.resumeGasMetering();
        vm.warp(block.timestamp + court.RULING_PERIOD() + 1);
        court.delinquentReveal(petition.petitionId);

        // not admin
        vm.expectRevert(Court.Court__OnlyAdmin.selector);
        vm.prank(alice);
        court.assignArbiter(petition.petitionId, admin1);
        // invalid arbiter - litigant
        vm.expectRevert(Court.Court__InvalidArbiter.selector);
        vm.prank(admin1);
        court.assignArbiter(petition.petitionId, petition.defendant);
        // invalid arbiter - ineligible juror
        vm.prank(admin1);
        juryPool.pauseJuror();
        vm.expectRevert(Court.Court__InvalidArbiter.selector);
        vm.prank(admin1);
        court.assignArbiter(petition.petitionId, admin1);
        // invalid arbiter - confirmed juror (no double votes)
        vm.expectRevert(Court.Court__InvalidArbiter.selector);
        vm.prank(admin1);
        court.assignArbiter(petition.petitionId, jury.confirmedJurors[2]);
        // wrong phase
        vm.prank(admin1);
        court.assignArbiter(petition.petitionId, admin2);
        vm.prank(admin2);
        court.breakTie(petition.petitionId, false);
        vm.expectRevert(Court.Court__OnlyDuringRuling.selector);
        vm.prank(admin1);
        court.assignArbiter(petition.petitionId, admin2);
    }

    function test_breakTie() public {
        vm.pauseGasMetering();
        bool[3] memory voteInputs = [false, false, true];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customRuling(id_arbitration_confirmedJury_MATIC, votes, false);
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_confirmedJury_MATIC));
        Court.Jury memory jury = court.getJury(petition.petitionId);
        address juror1 = jury.confirmedJurors[1];
        address juror2 = jury.confirmedJurors[2];
        vm.prank(juror1);
        court.revealVote(petition.petitionId, false, "someSalt");
        vm.prank(juror2);
        court.revealVote(petition.petitionId, true, "someSalt");
        vm.warp(block.timestamp + court.RULING_PERIOD() + 1);
        court.delinquentReveal(petition.petitionId);
        address arbiter = jury.drawnJurors[jury.drawnJurors.length -1]; // we know this juror is eligible
        vm.prank(admin1);
        court.assignArbiter(petition.petitionId, arbiter);
        vm.resumeGasMetering();
        assertTrue(court.votesTied(petition.petitionId));
        assertEq(uint(petition.phase), uint(Phase.Ruling));
        uint256 jurorFee = court.jurorFlatFee();
        // uint256 juror1BalBefore = juror1.balance;
        uint256 juror2FeesOwedBefore = court.getJurorFeesOwed(juror2);
        uint256 juryReserveBefore = juryPool.getJuryReserve();

        vm.expectEmit(true, true, false, true);
        emit ArbiterVote(petition.petitionId, arbiter, true);
        vm.prank(arbiter);
        court.breakTie(petition.petitionId, true);

        // verdict rendered
        petition = court.getPetition(petition.petitionId);
        assertEq(uint(petition.phase), uint(Phase.Verdict));
        assertEq(petition.petitionGranted, true);
        // majority (juror2) paid
        assertEq(court.getJurorFeesOwed(juror2), juror2FeesOwedBefore + jurorFee);
        // minority (juror1) fee + forfeitted fee (juror0) transferred
        assertEq(juryPool.getJuryReserve(), juryReserveBefore + jurorFee + jurorFee);
    }

    function test_breakTie_revert() public {
        // wrong phase - case tested in test_assignArbiter_revert()
        // not arbiter
        bool[3] memory voteInputs = [false, false, true];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customRuling(id_arbitration_confirmedJury_MATIC, votes, false);
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(id_arbitration_confirmedJury_MATIC));
        vm.expectRevert(Court.Court__InvalidArbiter.selector);
        vm.prank(admin1);
        court.breakTie(petition.petitionId, true);
    }

}
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/Interfaces/IEscrow.sol";
import "forge-std/console.sol";

contract MediationServicePanelTest is Test, TestSetup {

    event PanelDrawn(uint256 indexed disputeId, bool isRedraw);
    event MediatorConfirmed(uint256 indexed disputeId, address mediatorAddress);
    event VotingInitiated(uint256 indexed disputeId);
    event VoteCommitted(uint256 indexed disputeId, address indexed mediator, bytes32 commit);
    event RevealInitiated(uint256 indexed disputeId);
    event VoteRevealed(uint256 indexed disputeId, address indexed mediator, bool vote);
    event DecisionReached(uint256 indexed disputeId, bool decision, uint256 majorityVotes);
    event MediatorFeesClaimed(address indexed mediator, uint256 amount);
    event AdditionalMediatorDrawingInitiated(uint256 indexed disputeId, uint256 requestId);
    event AdditionalMediatorsAssigned(uint256 indexed disputeId, address[] assignedMediators);
    event MediatorRemoved(uint256 indexed disputeId, address indexed mediator);
    event RevealOverdue(uint256 indexed disputeId, bool deadlocked);
    event ArbiterAssigned(uint256 indexed disputeId, address indexed arbiter);
    event ArbiterVote(uint256 indexed disputeId, address indexed arbiter, bool vote);

    function setUp() public {
        _setUp();
        _whitelistUsers();
        _registerMediators();
        _initializeTestProjects();
        _initializeMediationProjects();
    }

    function test_selectPanel() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_disclosure_MATIC));
        vm.prank(dispute.claimant);
        mediationService.payMediationFee{value: dispute.mediationFee}(dispute.disputeId, evidence1);
        vm.recordLogs();
        vm.prank(dispute.respondent);
        mediationService.payMediationFee{value: dispute.mediationFee}(dispute.disputeId, evidence2);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[2].data));
        vm.expectEmit(true, false, false, true);
        emit PanelDrawn(dispute.disputeId, false);
        vrf.fulfillRandomWords(requestId, address(mediationService));

        // panel drawn
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        assertEq(panel.confirmedMediators.length, 0);
        for(uint i; i < panel.drawnMediators.length; ++i) {
            for(uint j; j < panel.drawnMediators.length; ++j) {
                if(i != j) {
                    assertFalse(panel.drawnMediators[i] == panel.drawnMediators[j]);
                    assertFalse(panel.drawnMediators[i] == dispute.claimant);
                    assertFalse(panel.drawnMediators[i] == dispute.respondent);
                    assertTrue(mediatorPool.isEligible(panel.drawnMediators[i]));
                }
            }
        }
    }

    function test_acceptCase() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_panelSelection_MATIC));
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        assertEq(panel.confirmedMediators.length, 0);
        assertEq(mediationService.getMediatorStakeHeld(panel.drawnMediators[0], dispute.disputeId), 0);
        uint256 mediationServiceBalBefore = address(mediationService).balance;

        uint256 stake = mediationService.mediatorFlatFee();
        vm.expectEmit(true, false, false, true);
        emit MediatorConfirmed(dispute.disputeId, panel.drawnMediators[0]);
        vm.prank(panel.drawnMediators[0]);
        mediationService.acceptCase{value: stake}(dispute.disputeId);

        panel = mediationService.getPanel(dispute.disputeId);
        assertEq(panel.confirmedMediators[0], panel.drawnMediators[0]);
        assertEq(mediationService.getMediatorStakeHeld(panel.confirmedMediators[0], dispute.disputeId), stake);
        assertEq(address(mediationService).balance, mediationServiceBalBefore + stake);
    }

    function test_acceptCase_revert() public {
        uint256 stake = mediationService.mediatorFlatFee();
        // all seats filled
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_confirmedPanel_MATIC));
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        vm.expectRevert(MediationService.MediationService__MediatorSeatsFilled.selector);
        vm.prank(panel.drawnMediators[panel.drawnMediators.length - 1]);
        mediationService.acceptCase{value: stake}(dispute.disputeId);
        // already accepted
        dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_panelSelection_ERC20));
        panel = mediationService.getPanel(dispute.disputeId);
        vm.prank(panel.drawnMediators[0]);
        mediationService.acceptCase{value: stake}(dispute.disputeId);
        vm.expectRevert(MediationService.MediationService__AlreadyConfirmedMediator.selector);
        vm.prank(panel.drawnMediators[0]);
        mediationService.acceptCase{value: stake}(dispute.disputeId);  
        // insufficient stake 
        vm.expectRevert(MediationService.MediationService__InsufficientMediatorStake.selector);
        vm.prank(panel.drawnMediators[1]);
        mediationService.acceptCase{value: stake - 1}(dispute.disputeId);  
        // not active mediator
        vm.prank(panel.drawnMediators[1]);
        mediatorPool.pauseMediator();
        vm.expectRevert(MediationService.MediationService__InvalidMediator.selector);
        vm.prank(panel.drawnMediators[1]);
        mediationService.acceptCase{value: stake}(dispute.disputeId);  
    }

    function test_panelAssembled() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_panelSelection_MATIC));
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        uint256 mediatorsNeeded = mediationService.mediatorsNeeded(dispute.disputeId);
        uint256 stake = mediationService.mediatorFlatFee();
        for(uint i; i < panel.drawnMediators.length; ++i) {
            if(mediationService.getPanel(dispute.disputeId).confirmedMediators.length == mediatorsNeeded - 1) {
                vm.expectEmit(true, false, false, false);
                emit VotingInitiated(dispute.disputeId);
            }
            vm.prank(panel.drawnMediators[i]);
            mediationService.acceptCase{value: stake}(dispute.disputeId);
            panel = mediationService.getPanel(dispute.disputeId);
            if(panel.confirmedMediators.length == mediatorsNeeded) break;
        }
        dispute = mediationService.getDispute(dispute.disputeId);
        assertEq(uint(dispute.phase), uint(Phase.Voting));
    }

    function test_commitVote() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_confirmedPanel_MATIC));
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        assertEq(mediationService.getCommit(panel.confirmedMediators[0], dispute.disputeId), 0x0);
        
        bytes32 commit = keccak256(abi.encodePacked(true, "someSalt"));
        vm.expectEmit(true, true, false, true);
        emit VoteCommitted(dispute.disputeId, panel.confirmedMediators[0], commit);
        vm.prank(panel.confirmedMediators[0]);
        mediationService.commitVote(dispute.disputeId, commit);
        
        assertEq(mediationService.getCommit(panel.confirmedMediators[0], dispute.disputeId), commit);
    }

    function test_commitVote_revert() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_confirmedPanel_MATIC));
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        bytes32 commit = keccak256(abi.encodePacked(true, "someSalt"));
        // not mediator
        vm.expectRevert(MediationService.MediationService__InvalidMediator.selector);
        vm.prank(dispute.claimant); // cannot be mediator
        mediationService.commitVote(dispute.disputeId, commit);
        // already committed
        vm.prank(panel.confirmedMediators[0]);
        mediationService.commitVote(dispute.disputeId, commit);
        vm.expectRevert(MediationService.MediationService__MediatorHasAlreadyCommmitedVote.selector);
        vm.prank(panel.confirmedMediators[0]);
        mediationService.commitVote(dispute.disputeId, commit);
        // invalid commit
        vm.expectRevert(MediationService.MediationService__InvalidCommit.selector);
        vm.prank(panel.confirmedMediators[1]);
        mediationService.commitVote(dispute.disputeId, 0x0);
        // cannot commit at wrong phase as there will be no confirmed mediators
        dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_panelSelection_ERC20));
        vm.expectRevert(MediationService.MediationService__InvalidMediator.selector);
        vm.prank(panel.drawnMediators[1]);
        mediationService.commitVote(dispute.disputeId, commit);
    }

    function test_allVotesCommitted() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_confirmedPanel_MATIC));
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        bytes32 commit = keccak256(abi.encodePacked(true, "someSalt"));
        vm.prank(panel.confirmedMediators[0]);
        mediationService.commitVote(dispute.disputeId, commit);
        vm.prank(panel.confirmedMediators[1]);
        mediationService.commitVote(dispute.disputeId, commit);

        vm.expectEmit(true, false, false, false);
        emit RevealInitiated(dispute.disputeId);
        vm.prank(panel.confirmedMediators[2]);
        mediationService.commitVote(dispute.disputeId, commit);
        
        dispute = mediationService.getDispute(dispute.disputeId);
        assertEq(uint(dispute.phase), uint(Phase.Reveal));
        assertEq(dispute.revealStart, block.timestamp);
    }

    function test_revealVote() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_committedVotes_ERC20));
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        address mediator = panel.confirmedMediators[0];
        vm.expectRevert(MediationService.MediationService__VoteHasNotBeenRevealed.selector);
        mediationService.getVote(mediator, dispute.disputeId);
        assertEq(mediationService.hasRevealedVote(mediator, dispute.disputeId), false);
        assertEq(mediationService.getMediatorStakeHeld(mediator, dispute.disputeId), mediationService.mediatorFlatFee());
        uint256 mediatorBalBefore = mediator.balance;

        vm.expectEmit(true, true, false, true);
        emit VoteRevealed(dispute.disputeId, mediator, true);
        vm.prank(mediator);
        mediationService.revealVote(dispute.disputeId, true, "someSalt");

        assertEq(mediationService.getVote(mediator, dispute.disputeId), true);
        assertEq(mediationService.hasRevealedVote(mediator, dispute.disputeId), true);
        assertEq(mediationService.getMediatorStakeHeld(mediator, dispute.disputeId), 0);
        assertEq(mediator.balance, mediatorBalBefore + mediationService.mediatorFlatFee());
    }

    function test_revealVote_revert() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_committedVotes_ERC20));
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        address mediator = panel.confirmedMediators[0];
        // invalid mediator
        vm.expectRevert(MediationService.MediationService__InvalidMediator.selector);
        vm.prank(dispute.claimant);
        mediationService.revealVote(dispute.disputeId, true, "someSalt");
        // reveal doesn't match commit
        vm.expectRevert(MediationService.MediationService__RevealDoesNotMatchCommit.selector);
        vm.prank(mediator);
        mediationService.revealVote(dispute.disputeId, false, "someSalt"); // incorrect vote
        vm.expectRevert(MediationService.MediationService__RevealDoesNotMatchCommit.selector);
        vm.prank(mediator);
        mediationService.revealVote(dispute.disputeId, true, "WRONG_Salt"); // incorrect salt
        // already revealed
        vm.prank(mediator);
        mediationService.revealVote(dispute.disputeId, true, "someSalt");
        vm.expectRevert(MediationService.MediationService__AlreadyRevealed.selector);
        vm.prank(mediator);
        mediationService.revealVote(dispute.disputeId, true, "someSalt");
        // wrong phase
        dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_confirmedPanel_MATIC));
        panel = mediationService.getPanel(dispute.disputeId);
        mediator = panel.confirmedMediators[0];
        vm.expectRevert(MediationService.MediationService__CannotRevealBeforeAllVotesCommitted.selector);
        vm.prank(mediator);
        mediationService.revealVote(dispute.disputeId, true, "someSalt");
    }

    function test_renderDecision() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_committedVotes_ERC20));
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        uint256 mediator0FeesBefore = mediationService.getMediatorFeesOwed(panel.confirmedMediators[0]);
        uint256 mediator1FeesBefore = mediationService.getMediatorFeesOwed(panel.confirmedMediators[1]);
        uint256 mediator2FeesBefore = mediationService.getMediatorFeesOwed(panel.confirmedMediators[2]);
        uint256 mediationReserveBefore = mediatorPool.getMediationReserve();
        uint256 mediatorPoolBalBefore = address(mediatorPool).balance;
        assertEq(mediationService.getFeesHeld(dispute.disputeId), dispute.mediationFee * 2);

        vm.prank(panel.confirmedMediators[0]);
        mediationService.revealVote(dispute.disputeId, true, "someSalt");
        vm.prank(panel.confirmedMediators[1]);
        mediationService.revealVote(dispute.disputeId, true, "someSalt");
        vm.expectEmit(true, false, false, true);
        emit DecisionReached(dispute.disputeId, true, 2);
        vm.prank(panel.confirmedMediators[2]);
        mediationService.revealVote(dispute.disputeId, false, "someSalt");

        dispute = mediationService.getDispute(dispute.disputeId);
        assertEq(uint(dispute.phase), uint(Phase.Decision));
        assertEq(dispute.granted, true);
        assertEq(dispute.decisionRenderedDate, block.timestamp);
        // mediator fees owed recorded correctly
        uint256 mediatorFee = dispute.mediationFee / mediationService.mediatorsNeeded(dispute.disputeId);
        assertEq(mediationService.getMediatorFeesOwed(panel.confirmedMediators[0]), mediator0FeesBefore + mediatorFee);
        assertEq(mediationService.getMediatorFeesOwed(panel.confirmedMediators[1]), mediator1FeesBefore + mediatorFee);
        assertEq(mediationService.getMediatorFeesOwed(panel.confirmedMediators[2]), mediator2FeesBefore); // minority vote, nothing owed
        // minority mediator's fee transferred to to panel reserve
        assertEq(mediatorPool.getMediationReserve(), mediationReserveBefore + mediatorFee);
        assertEq(address(mediatorPool).balance, mediatorPoolBalBefore + mediatorFee);
        // fees held now only represents winner's fee - loser's fee has been distributed to mediators and panel reserve
        assertEq(mediationService.getFeesHeld(dispute.disputeId), dispute.mediationFee);

        /////////
        // test with full majority
        /////////
        dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_confirmedPanel_MATIC));
        panel = mediationService.getPanel(dispute.disputeId);
        mediator0FeesBefore = mediationService.getMediatorFeesOwed(panel.confirmedMediators[0]);
        mediator1FeesBefore = mediationService.getMediatorFeesOwed(panel.confirmedMediators[1]);
        mediator2FeesBefore = mediationService.getMediatorFeesOwed(panel.confirmedMediators[2]);
        mediationReserveBefore = mediatorPool.getMediationReserve();
        mediatorPoolBalBefore = address(mediatorPool).balance;
        assertEq(mediationService.getFeesHeld(dispute.disputeId), dispute.mediationFee * 2);

        bool[3] memory voteInputs = [false, false, false];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customReveal(id_mediation_confirmedPanel_MATIC, votes, true);
        
        dispute = mediationService.getDispute(dispute.disputeId);
        // mediator fees owed recorded correctly
        assertEq(mediationService.getMediatorFeesOwed(panel.confirmedMediators[0]), mediator0FeesBefore + mediatorFee);
        assertEq(mediationService.getMediatorFeesOwed(panel.confirmedMediators[1]), mediator1FeesBefore + mediatorFee);
        assertEq(mediationService.getMediatorFeesOwed(panel.confirmedMediators[2]), mediator2FeesBefore + mediatorFee); 
        // no transfer to panel reserve
        assertEq(mediatorPool.getMediationReserve(), mediationReserveBefore);
        assertEq(address(mediatorPool).balance, mediatorPoolBalBefore);
        // fees held now only represents winner's fee - loser's fee has been distributed to mediators
        assertEq(mediationService.getFeesHeld(dispute.disputeId), dispute.mediationFee);
    }

    function test_claimMediatorFees() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_committedVotes_ERC20));
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        uint256 mediator0BalBefore = panel.confirmedMediators[0].balance;
        uint256 mediator1BalBefore = panel.confirmedMediators[1].balance;

        vm.prank(panel.confirmedMediators[0]);
        mediationService.revealVote(dispute.disputeId, true, "someSalt");
        vm.prank(panel.confirmedMediators[1]);
        mediationService.revealVote(dispute.disputeId, true, "someSalt");
        vm.expectEmit(true, false, false, true);
        emit DecisionReached(dispute.disputeId, true, 2);
        vm.prank(panel.confirmedMediators[2]);
        mediationService.revealVote(dispute.disputeId, false, "someSalt");

        uint256 mediatorFee = dispute.mediationFee / mediationService.mediatorsNeeded(dispute.disputeId);
        uint256 stake = dispute.mediationFee / mediationService.mediatorsNeeded(dispute.disputeId);
        vm.expectEmit(true, false, false, true);
        emit MediatorFeesClaimed(panel.confirmedMediators[0], mediatorFee);
        vm.prank(panel.confirmedMediators[0]);
        mediationService.claimMediatorFees();
        assertEq(mediationService.getMediatorFeesOwed(panel.confirmedMediators[0]), 0);
        assertEq(panel.confirmedMediators[0].balance, mediator0BalBefore + mediatorFee + stake);

        vm.expectEmit(true, false, false, true);
        emit MediatorFeesClaimed(panel.confirmedMediators[1], mediatorFee);
        vm.prank(panel.confirmedMediators[1]);
        mediationService.claimMediatorFees();
        assertEq(mediationService.getMediatorFeesOwed(panel.confirmedMediators[1]), 0);
        assertEq(panel.confirmedMediators[1].balance, mediator1BalBefore + mediatorFee + stake);

        vm.expectRevert(MediationService.MediationService__NoMediatorFeesOwed.selector);
        vm.prank(panel.confirmedMediators[2]); // minority - nothing owed
        mediationService.claimMediatorFees();
    }

    ///////////////////////////
    ///   PANEL EXCEPTIONS   ///
    ///////////////////////////

    function test_drawAdditionalMediators() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_panelSelection_MATIC));
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        assertEq(panel.drawnMediators.length, mediationService.mediatorsNeeded(dispute.disputeId) * 3);
        assertEq(panel.confirmedMediators.length, 0);
        vm.warp(block.timestamp + mediationService.PANEL_SELECTION_PERIOD() + 1);
        
        vm.expectEmit(true, false, false, false);
        emit AdditionalMediatorDrawingInitiated(dispute.disputeId, 42 /* cannot be known */);
        vm.recordLogs();
        mediationService.drawAdditionalMediators(dispute.disputeId);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[1].data));
        vrf.fulfillRandomWords(requestId, address(mediationService));

        panel = mediationService.getPanel(dispute.disputeId);
        assertEq(panel.drawnMediators.length, mediationService.mediatorsNeeded(dispute.disputeId) * 5);
        for(uint i; i < panel.drawnMediators.length; ++i) {
            for(uint j; j < panel.drawnMediators.length; ++j) {
                if(i != j) {
                    assertTrue(panel.drawnMediators[i] != panel.drawnMediators[j]);
                }
            }
        }
    }

    function test_drawAdditionalMediators_revert() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_disclosure_ERC20));
        // wrong phase
        vm.expectRevert(MediationService.MediationService__OnlyDuringPanelSelection.selector);
        mediationService.drawAdditionalMediators(dispute.disputeId);
        // initial selection still open
        dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_panelSelection_MATIC));
        vm.expectRevert(MediationService.MediationService__InitialSelectionPeriodStillOpen.selector);
        mediationService.drawAdditionalMediators(dispute.disputeId);
        // already redrawn
        vm.warp(block.timestamp + mediationService.PANEL_SELECTION_PERIOD() + 1);
        vm.recordLogs();
        mediationService.drawAdditionalMediators(dispute.disputeId);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[1].data));
        vrf.fulfillRandomWords(requestId, address(mediationService));
        vm.expectRevert(MediationService.MediationService__PanelAlreadyRedrawn.selector);
        mediationService.drawAdditionalMediators(dispute.disputeId);
    }

    function test_assignAdditionalMediators() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_panelSelection_MATIC));
        vm.warp(block.timestamp + mediationService.PANEL_SELECTION_PERIOD() + 1);
        vm.recordLogs();
        mediationService.drawAdditionalMediators(dispute.disputeId);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[1].data));
        vrf.fulfillRandomWords(requestId, address(mediationService));

        address assignedMediator1 = vm.addr(10000001);
        address assignedMediator2 = vm.addr(10000002);
        address assignedMediator3 = vm.addr(10000003);
        address[3] memory ringers = [assignedMediator1, assignedMediator2, assignedMediator3];
        uint256 stake = mediatorPool.minimumStake();
        for(uint i; i < ringers.length; ++i) {
            vm.deal(ringers[i], 10000 ether);
            vm.prank(admin1);
            whitelist.approveAddress(ringers[i]);
            vm.prank(ringers[i]);
            mediatorPool.registerAsMediator{value: stake}();
        }
        address[] memory assignedMediators = new address[](ringers.length);
        for(uint i; i < assignedMediators.length; ++i) {
            assignedMediators[i] = ringers[i];
        } 
        vm.expectEmit(true, false, false, true);
        emit AdditionalMediatorsAssigned(dispute.disputeId, assignedMediators);
        vm.prank(admin1);
        mediationService.assignAdditionalMediators(dispute.disputeId, assignedMediators);

        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        assertEq(panel.drawnMediators.length, assignedMediators.length + (mediationService.mediatorsNeeded(dispute.disputeId) * 5));
        uint256 mediatorFee = mediationService.mediatorFlatFee();
        for(uint i; i < assignedMediators.length; ++i) {
            vm.prank(assignedMediators[i]);
            mediationService.acceptCase{value: mediatorFee}(dispute.disputeId);
            assertEq(mediationService.isConfirmedMediator(dispute.disputeId, assignedMediators[i]), true);
        }
    }

    function test_assignAdditionalMediators_revert() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_disclosure_MATIC));
        address[] memory additionalMediators = new address[](1);
        additionalMediators[0] = admin1;
        // wrong phase
        vm.expectRevert(MediationService.MediationService__OnlyDuringPanelSelection.selector);
        vm.prank(admin1);
        mediationService.assignAdditionalMediators(dispute.disputeId, additionalMediators);
        // selection period still open
        dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_panelSelection_MATIC));
        vm.expectRevert(MediationService.MediationService__InitialSelectionPeriodStillOpen.selector);
        vm.prank(admin1);
        mediationService.assignAdditionalMediators(dispute.disputeId, additionalMediators);
        // panel not redrawn
        vm.warp(block.timestamp + mediationService.PANEL_SELECTION_PERIOD() + 1);
        vm.expectRevert(MediationService.MediationService__PanelNotRedrawn.selector);
        vm.prank(admin1);
        mediationService.assignAdditionalMediators(dispute.disputeId, additionalMediators);
        // not admin
        vm.recordLogs();
        mediationService.drawAdditionalMediators(dispute.disputeId);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[1].data));
        vrf.fulfillRandomWords(requestId, address(mediationService));
        vm.expectRevert(MediationService.MediationService__OnlyAdmin.selector);
        vm.prank(carlos);
        mediationService.assignAdditionalMediators(dispute.disputeId, additionalMediators);
        // invalid mediator - confirmed mediator
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        uint256 mediatorFee = mediationService.mediatorFlatFee();
        vm.prank(panel.drawnMediators[0]);
        mediationService.acceptCase{value: mediatorFee}(dispute.disputeId);
        panel = mediationService.getPanel(dispute.disputeId);
        additionalMediators[0] = panel.confirmedMediators[0];
        vm.expectRevert(MediationService.MediationService__InvalidMediator.selector);
        vm.prank(admin1);
        mediationService.assignAdditionalMediators(dispute.disputeId, additionalMediators);
        // invalid mediator - ineligible
        uint256 stake = mediatorPool.getMediatorStake(admin1);
        vm.prank(admin1);
        mediatorPool.withdrawStake(stake);
        additionalMediators[0] = admin1;
        vm.expectRevert(MediationService.MediationService__InvalidMediator.selector);
        vm.prank(admin1);
        mediationService.assignAdditionalMediators(dispute.disputeId, additionalMediators);
        // invalid mediator - claimant or respondent
        additionalMediators[0] = dispute.claimant;
        vm.expectRevert(MediationService.MediationService__InvalidMediator.selector);
        vm.prank(admin1);
        mediationService.assignAdditionalMediators(dispute.disputeId, additionalMediators);
    }

    function test_overdueCommit() public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_confirmedPanel_MATIC));
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        address mediator1 = panel.confirmedMediators[1];
        address mediator2 = panel.confirmedMediators[2];
        uint256 stake = mediationService.mediatorFlatFee();
            // mediator 0 votes
        bytes32 commit = keccak256(abi.encodePacked(true, "someSalt"));
        vm.prank(panel.confirmedMediators[0]);
        mediationService.commitVote(dispute.disputeId, commit);
        vm.warp(block.timestamp + mediationService.VOTING_PERIOD() + 1);
            // mediators 1 & 2 have not voted
        assertEq(mediationService.getCommit(mediator1, dispute.disputeId), 0x0);
        assertEq(mediationService.getCommit(mediator2, dispute.disputeId), 0x0);
        uint256 drawnMediatorsBefore = panel.drawnMediators.length;
        uint256 confirmedMediatorsBefore = panel.confirmedMediators.length;
        assertEq(mediationService.getMediatorStakeHeld(mediator1, dispute.disputeId), stake);
        assertEq(mediationService.getMediatorStakeHeld(mediator2, dispute.disputeId), stake);
        uint256 mediationReserveBefore = mediatorPool.getMediationReserve();
        
        vm.expectEmit(true, true, false, false);
        emit MediatorRemoved(dispute.disputeId, mediator1);
        vm.expectEmit(true, true, false, false);
        emit MediatorRemoved(dispute.disputeId, mediator2);
        mediationService.overdueCommit(dispute.disputeId);

        // mediators removed
        panel = mediationService.getPanel(dispute.disputeId);
        assertEq(panel.drawnMediators.length, drawnMediatorsBefore - 2);
        for(uint i; i < panel.drawnMediators.length; ++i) {
            assertTrue(panel.drawnMediators[i] != mediator1);
            assertTrue(panel.drawnMediators[i] != mediator2);
        }
        assertEq(panel.confirmedMediators.length, confirmedMediatorsBefore - 2);
        assertEq(mediationService.isConfirmedMediator(dispute.disputeId, mediator1), false);
        assertEq(mediationService.isConfirmedMediator(dispute.disputeId, mediator2), false);
        // stakes transferred to panel pool
        assertEq(mediationService.getMediatorStakeHeld(mediator1, dispute.disputeId), 0);
        assertEq(mediationService.getMediatorStakeHeld(mediator2, dispute.disputeId), 0);
        assertEq(mediatorPool.getMediationReserve(), mediationReserveBefore + stake + stake);
        // voting period restarted
        dispute = mediationService.getDispute(dispute.disputeId);
        assertEq(dispute.votingStart, block.timestamp);
    }

    function test_overdueCommit_revert() public {
        // voting period still active
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_confirmedPanel_MATIC));
        vm.expectRevert(MediationService.MediationService__VotingPeriodStillActive.selector);
        mediationService.overdueCommit(dispute.disputeId);
        // no overdue commits
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        bytes32 commit = keccak256(abi.encodePacked(true, "someSalt"));
        for(uint i; i < panel.confirmedMediators.length; ++i) {
            vm.prank(panel.confirmedMediators[i]);
            mediationService.commitVote(dispute.disputeId, commit);
        }
        vm.warp(block.timestamp + mediationService.VOTING_PERIOD() + 1);
        vm.expectRevert(MediationService.MediationService__NoOverdueCommits.selector);
        mediationService.overdueCommit(dispute.disputeId);
    }

    function test_revealOverdue_majority() public {
        vm.pauseGasMetering();
        bool[3] memory voteInputs = [false, true, true];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customReveal(id_mediation_confirmedPanel_MATIC, votes, false);
        vm.resumeGasMetering();
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_confirmedPanel_MATIC));
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
            // mediator0 will be removed, resulting in a majority decision
        address mediator0 = panel.confirmedMediators[0];
        address mediator1 = panel.confirmedMediators[1];
        address mediator2 = panel.confirmedMediators[2];
        vm.prank(mediator1);
        mediationService.revealVote(dispute.disputeId, true, "someSalt");
        vm.prank(mediator2);
        mediationService.revealVote(dispute.disputeId, true, "someSalt");
        assertTrue(mediationService.hasRevealedVote(mediator1, dispute.disputeId));
        assertTrue(mediationService.hasRevealedVote(mediator2, dispute.disputeId));
        uint256 stake = mediationService.mediatorFlatFee();
        uint256 drawnMediatorsBefore = panel.drawnMediators.length;
        uint256 confirmedMediatorsBefore = panel.confirmedMediators.length;
        assertEq(mediationService.getMediatorStakeHeld(mediator0, dispute.disputeId), stake);
        uint256 mediationReserveBefore = mediatorPool.getMediationReserve();

        vm.warp(block.timestamp + mediationService.VOTING_PERIOD() + 1);
        vm.expectEmit(true, false, false, true);
        emit DecisionReached(dispute.disputeId, true, 2);
        vm.expectEmit(true, false, false, true);
        emit RevealOverdue(dispute.disputeId, false);
        mediationService.revealOverdue(dispute.disputeId);

        // mediator removed
        panel = mediationService.getPanel(dispute.disputeId);
        assertEq(panel.drawnMediators.length, drawnMediatorsBefore - 1);
        for(uint i; i < panel.drawnMediators.length; ++i) {
            assertFalse(panel.drawnMediators[i] == mediator0);
        }
        assertEq(panel.confirmedMediators.length, confirmedMediatorsBefore - 1);
        assertEq(mediationService.isConfirmedMediator(dispute.disputeId, mediator0), false);
        // stake forfeitted
        assertEq(mediationService.getMediatorStakeHeld(mediator0, dispute.disputeId), 0);
        assertEq(mediatorPool.getMediationReserve(), mediationReserveBefore + stake);
        
        // decision rendered (majority)
        dispute = mediationService.getDispute(dispute.disputeId);
        assertEq(uint(dispute.phase), uint(Phase.Decision));
        assertEq(dispute.granted, true);
    }

    function test_revealOverdue_tie() public {
        vm.pauseGasMetering();
        bool[3] memory voteInputs = [false, false, true];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customReveal(id_mediation_confirmedPanel_MATIC, votes, false);
        vm.resumeGasMetering();
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_confirmedPanel_MATIC));
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
            // mediator0 will be removed, resulting in a majority decision
        address mediator0 = panel.confirmedMediators[0];
        address mediator1 = panel.confirmedMediators[1];
        address mediator2 = panel.confirmedMediators[2];
        vm.prank(mediator1);
        mediationService.revealVote(dispute.disputeId, false, "someSalt");
        vm.prank(mediator2);
        mediationService.revealVote(dispute.disputeId, true, "someSalt");
        assertTrue(mediationService.hasRevealedVote(mediator1, dispute.disputeId));
        assertTrue(mediationService.hasRevealedVote(mediator2, dispute.disputeId));
        uint256 stake = mediationService.mediatorFlatFee();
        uint256 drawnMediatorsBefore = panel.drawnMediators.length;
        uint256 confirmedMediatorsBefore = panel.confirmedMediators.length;
        assertEq(mediationService.getMediatorStakeHeld(mediator0, dispute.disputeId), stake);
        uint256 mediationReserveBefore = mediatorPool.getMediationReserve();

        vm.warp(block.timestamp + mediationService.VOTING_PERIOD() + 1);
        // vm.expectEmit(true, false, false, true);
        // emit DecisionReached(dispute.disputeId, true, 2);
        vm.expectEmit(true, false, false, true);
        emit RevealOverdue(dispute.disputeId, true);
        mediationService.revealOverdue(dispute.disputeId);

        // mediator removed
        panel = mediationService.getPanel(dispute.disputeId);
        assertEq(panel.drawnMediators.length, drawnMediatorsBefore - 1);
        for(uint i; i < panel.drawnMediators.length; ++i) {
            assertFalse(panel.drawnMediators[i] == mediator0);
        }
        assertEq(panel.confirmedMediators.length, confirmedMediatorsBefore - 1);
        assertEq(mediationService.isConfirmedMediator(dispute.disputeId, mediator0), false);
        // stake forfeitted
        assertEq(mediationService.getMediatorStakeHeld(mediator0, dispute.disputeId), 0);
        assertEq(mediatorPool.getMediationReserve(), mediationReserveBefore + stake);
        
        // no decision rendered (tie)
        dispute = mediationService.getDispute(dispute.disputeId);
        assertEq(uint(dispute.phase), uint(Phase.Reveal));
        assertEq(dispute.granted, false);
        assertEq(mediationService.votesTied(dispute.disputeId), true);
    }

    function test_revealOverdue_revert() public {
        // wrong phase
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_confirmedPanel_MATIC));
        vm.expectRevert(MediationService.MediationService__OnlyDuringReveal.selector);
        mediationService.revealOverdue(dispute.disputeId);
        // reveal period still active
        vm.pauseGasMetering();
        bool[3] memory voteInputs = [false, false, true];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customReveal(id_mediation_confirmedPanel_MATIC, votes, false);
        vm.resumeGasMetering();
        dispute = mediationService.getDispute(dispute.disputeId);
        assertTrue(block.timestamp < dispute.revealStart + mediationService.REVEAL_PERIOD());
        vm.expectRevert(MediationService.MediationService__RevealPeriodStillActive.selector);
        mediationService.revealOverdue(dispute.disputeId);
    }

    function test_assignArbiter() public {
        vm.pauseGasMetering();
        bool[3] memory voteInputs = [false, false, true];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customReveal(id_mediation_confirmedPanel_MATIC, votes, false);
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_confirmedPanel_MATIC));
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        // mediator0 will be removed, resulting in a tie
        address mediator1 = panel.confirmedMediators[1];
        address mediator2 = panel.confirmedMediators[2];
        vm.prank(mediator1);
        mediationService.revealVote(dispute.disputeId, false, "someSalt");
        vm.prank(mediator2);
        mediationService.revealVote(dispute.disputeId, true, "someSalt");
        vm.resumeGasMetering();
        vm.warp(block.timestamp + mediationService.REVEAL_PERIOD() + 1);
        mediationService.revealOverdue(dispute.disputeId);
        assertEq(mediationService.arbiter(dispute.disputeId), address(0));

        address arbiter = panel.drawnMediators[panel.drawnMediators.length -1]; // we know this mediator is eligible
        vm.expectEmit(true, true, false, false);
        emit ArbiterAssigned(dispute.disputeId, arbiter);
        vm.prank(admin1);
        mediationService.assignArbiter(dispute.disputeId, arbiter);

        assertEq(mediationService.arbiter(dispute.disputeId), arbiter);
    }

    function test_assignArbiter_revert() public {
        // case not deadlocked
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_confirmedPanel_MATIC));
        vm.expectRevert(MediationService.MediationService__CaseNotDeadlocked.selector);
        vm.prank(admin1);
        mediationService.assignArbiter(dispute.disputeId, admin1);

        vm.pauseGasMetering();
        bool[3] memory voteInputs = [false, false, true];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customReveal(id_mediation_confirmedPanel_MATIC, votes, false);
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        address mediator1 = panel.confirmedMediators[1];
        address mediator2 = panel.confirmedMediators[2];
        vm.prank(mediator1);
        mediationService.revealVote(dispute.disputeId, false, "someSalt");
        vm.prank(mediator2);
        mediationService.revealVote(dispute.disputeId, true, "someSalt");
        vm.resumeGasMetering();
        vm.warp(block.timestamp + mediationService.REVEAL_PERIOD() + 1);
        mediationService.revealOverdue(dispute.disputeId);

        // not admin
        vm.expectRevert(MediationService.MediationService__OnlyAdmin.selector);
        vm.prank(alice);
        mediationService.assignArbiter(dispute.disputeId, admin1);
        // invalid arbiter - disputant
        vm.expectRevert(MediationService.MediationService__InvalidArbiter.selector);
        vm.prank(admin1);
        mediationService.assignArbiter(dispute.disputeId, dispute.respondent);
        // invalid arbiter - ineligible mediator
        vm.prank(admin1);
        mediatorPool.pauseMediator();
        vm.expectRevert(MediationService.MediationService__InvalidArbiter.selector);
        vm.prank(admin1);
        mediationService.assignArbiter(dispute.disputeId, admin1);
        // invalid arbiter - confirmed mediator (no double votes)
        vm.expectRevert(MediationService.MediationService__InvalidArbiter.selector);
        vm.prank(admin1);
        mediationService.assignArbiter(dispute.disputeId, panel.confirmedMediators[2]);
        // wrong phase
        vm.prank(admin1);
        mediationService.assignArbiter(dispute.disputeId, admin2);
        vm.prank(admin2);
        mediationService.breakTie(dispute.disputeId, false);
        vm.expectRevert(MediationService.MediationService__OnlyDuringReveal.selector);
        vm.prank(admin1);
        mediationService.assignArbiter(dispute.disputeId, admin2);
    }

    function test_breakTie() public {
        vm.pauseGasMetering();
        bool[3] memory voteInputs = [false, false, true];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customReveal(id_mediation_confirmedPanel_MATIC, votes, false);
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_confirmedPanel_MATIC));
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        address mediator1 = panel.confirmedMediators[1];
        address mediator2 = panel.confirmedMediators[2];
        vm.prank(mediator1);
        mediationService.revealVote(dispute.disputeId, false, "someSalt");
        vm.prank(mediator2);
        mediationService.revealVote(dispute.disputeId, true, "someSalt");
        vm.warp(block.timestamp + mediationService.REVEAL_PERIOD() + 1);
        mediationService.revealOverdue(dispute.disputeId);
        address arbiter = panel.drawnMediators[panel.drawnMediators.length -1]; // we know this mediator is eligible
        vm.prank(admin1);
        mediationService.assignArbiter(dispute.disputeId, arbiter);
        vm.resumeGasMetering();
        assertTrue(mediationService.votesTied(dispute.disputeId));
        assertEq(uint(dispute.phase), uint(Phase.Reveal));
        uint256 mediatorFee = mediationService.mediatorFlatFee();
        // uint256 mediator1BalBefore = mediator1.balance;
        uint256 mediator2FeesOwedBefore = mediationService.getMediatorFeesOwed(mediator2);
        uint256 mediationReserveBefore = mediatorPool.getMediationReserve();

        vm.expectEmit(true, true, false, true);
        emit ArbiterVote(dispute.disputeId, arbiter, true);
        vm.prank(arbiter);
        mediationService.breakTie(dispute.disputeId, true);

        // decision rendered
        dispute = mediationService.getDispute(dispute.disputeId);
        assertEq(uint(dispute.phase), uint(Phase.Decision));
        assertEq(dispute.granted, true);
        // majority (mediator2) paid
        assertEq(mediationService.getMediatorFeesOwed(mediator2), mediator2FeesOwedBefore + mediatorFee);
        // minority (mediator1) fee + forfeitted fee (mediator0) transferred
        assertEq(mediatorPool.getMediationReserve(), mediationReserveBefore + mediatorFee + mediatorFee);
    }

    function test_breakTie_revert() public {
        // wrong phase - case tested in test_assignArbiter_revert()
        // not arbiter
        bool[3] memory voteInputs = [false, false, true];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _customReveal(id_mediation_confirmedPanel_MATIC, votes, false);
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(id_mediation_confirmedPanel_MATIC));
        vm.expectRevert(MediationService.MediationService__InvalidArbiter.selector);
        vm.prank(admin1);
        mediationService.breakTie(dispute.disputeId, true);
    }

}
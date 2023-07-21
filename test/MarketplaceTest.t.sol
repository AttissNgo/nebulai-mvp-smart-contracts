// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";

import "../src/Interfaces/IEscrow.sol";

contract MarketplaceTest is Test, TestSetup {

    // test project params
    address buyer = alice;
    address provider = bob;
    uint256 projectFee = 1000 ether;
    uint256 providerStake = 50 ether;
    uint256 dueDate;
    uint256 reviewPeriodLength = 3 days;
    string detailsURI = "ipfs://someURI/";
    uint256 testProjectId_MATIC;
    uint256 testProjectId_ERC20;

    // test change order
    uint256 changeOrderAdjustedProjectFee = 750 ether;
    string changeOrderDetailsURI = "ipfs://changeOrderUri";

    // test arbitration
    string[] evidence1 = ["someEvidenceURI", "someOtherEvidenceURI"];
    string[] evidence2 = ["someEvidenceURI2", "someOtherEvidenceURI2"];

    event ProjectCreated(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectCancelled(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectActivated(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectDiscontinued(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectCompleted(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectApproved(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectChallenged(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectDisputed(uint256 indexed projectId, address indexed buyer, address indexed provider, uint256 petitionId);
    event DelinquentPayment(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ChangeOrderApproved(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ChangeOrderRetracted(uint256 indexed projectId, address indexed retractedBy);
    event ProjectAppealed(uint256 indexed projectId, uint256 indexed petitionId, address appealedBy);
    event ResolvedByCourtOrder(uint256 indexed projectId, uint256 indexed petitionId);
    event ResolvedByDismissedCase(uint256 indexed projectId, uint256 indexed petitionId);

    function setUp() public {
        _setUp();
        _whitelistUsers();
        _registerJurors();
        dueDate = block.timestamp + 30 days;
        testProjectId_MATIC = _createProject();
        testProjectId_ERC20 = _createProjectERC20();
    }

    function _disputedProject(uint256 _projectId) public returns (uint256) {
        Marketplace.Project memory p = marketplace.getProject(_projectId);
        if(p.paymentToken != address(0)) {
            vm.prank(p.provider);
            usdt.approve(address(marketplace), p.providerStake);
            vm.prank(p.provider);
            marketplace.activateProject(p.projectId);
        } else {
            vm.prank(provider);
            marketplace.activateProject{value: p.providerStake}(p.projectId);
        }
        vm.prank(provider);
        marketplace.completeProject(p.projectId);
        vm.prank(buyer);
        marketplace.challengeProject(
            p.projectId,
            changeOrderAdjustedProjectFee,
            p.providerStake,
            changeOrderDetailsURI
        );
        // change order period passes
        vm.warp(block.timestamp + marketplace.CHANGE_ORDER_PERIOD() + 1);
        // buyer disputes
        vm.prank(buyer);
        uint256 petitionId = marketplace.disputeProject(
            p.projectId,
            changeOrderAdjustedProjectFee,
            p.providerStake
        );
        return petitionId;
    }

    function _disputedProjectWithRuling(uint256 _projectId) public {
        uint256 petitionId = _disputedProject(_projectId);
        // jury assembles and votes 
        Court.Petition memory petition = court.getPetition(petitionId);
        vm.prank(petition.plaintiff);
        court.payArbitrationFee{value: petition.arbitrationFee}(petitionId, evidence1);
        vm.recordLogs();
        vm.prank(petition.defendant);
        court.payArbitrationFee{value: petition.arbitrationFee}(petitionId, evidence2);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[2].data));
        vrf.fulfillRandomWords(requestId, address(court));
        Court.Jury memory jury = court.getJury(petition.petitionId);
        uint256 jurorStake = court.jurorFlatFee();
        for(uint i; i < court.jurorsNeeded(petition.petitionId); ++i) {
            vm.prank(jury.drawnJurors[i]);
            court.acceptCase{value: jurorStake}(petition.petitionId);
        }
        jury = court.getJury(petition.petitionId);
        bytes32 commit = keccak256(abi.encodePacked(true, "someSalt"));
        vm.prank(jury.confirmedJurors[0]);
        court.commitVote(petition.petitionId, commit);
        commit = keccak256(abi.encodePacked(false, "someSalt"));
        vm.prank(jury.confirmedJurors[1]);
        court.commitVote(petition.petitionId, commit);
        commit = keccak256(abi.encodePacked(true, "someSalt"));
        vm.prank(jury.confirmedJurors[2]);
        court.commitVote(petition.petitionId, commit);
        vm.prank(jury.confirmedJurors[0]);
        court.revealVote(petition.petitionId, true, "someSalt");
        vm.prank(jury.confirmedJurors[1]);
        court.revealVote(petition.petitionId, false, "someSalt");
        vm.prank(jury.confirmedJurors[2]);
        court.revealVote(petition.petitionId, true, "someSalt");
    }

    function _createProject() public returns (uint256) {
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
        return projectId;
    }

    function _createProjectERC20() public returns (uint256) {
        uint256 txFee = marketplace.calculateNebulaiTxFee(projectFee);
        vm.startPrank(buyer);
        usdt.approve(address(marketplace), txFee + projectFee);
        uint256 projectId = marketplace.createProject{value: 0}(
            provider,
            address(usdt),
            projectFee,
            providerStake,
            dueDate,
            reviewPeriodLength,
            detailsURI
        );
        vm.stopPrank();
        return projectId;
    }

    function test_deployment() public {
        // usdt is approved
        assertEq(marketplace.isApprovedToken(address(usdt)), true);
    }

    function test_createProject() public {
        uint256 txFee = marketplace.calculateNebulaiTxFee(projectFee);
        uint256 contractUsdtBalBefore = usdt.balanceOf(address(marketplace));
        vm.startPrank(buyer);
        usdt.approve(address(marketplace), txFee + projectFee);
        vm.expectEmit(false, true, true, false); // we don't know project ID yet
        emit ProjectCreated(42, buyer, provider); // we don't know project ID yet
        uint256 projectId = marketplace.createProject{value: 0}(
            provider,
            address(usdt),
            projectFee,
            providerStake,
            dueDate,
            reviewPeriodLength,
            detailsURI
        );
        vm.stopPrank();
        // project stored correctly:
        Marketplace.Project memory p = marketplace.getProject(projectId);
        assertEq(p.projectId, projectId);
        assertEq(p.buyer, buyer);
        assertEq(p.provider, provider);
        assertEq(p.paymentToken, address(usdt)); 
        assertEq(p.projectFee, projectFee);
        assertEq(p.providerStake, providerStake);
        assertEq(p.dueDate, dueDate);
        assertEq(p.reviewPeriodLength, reviewPeriodLength);
        assertEq(p.dateCompleted, 0);
        assertEq(p.changeOrderPeriodInitiated, 0);
        assertEq(uint(p.status), uint(Marketplace.Status.Created));
        assertEq(p.detailsURI, detailsURI);
        // fees captured
        assertEq(usdt.balanceOf(address(marketplace)), contractUsdtBalBefore + txFee);
        assertEq(marketplace.getTxFeesHeld(p.projectId), txFee);

        /// now the same thing again, but with MATIC:
        uint256 contractMaticBalBefore = address(marketplace).balance;
        vm.startPrank(buyer);
        usdt.approve(address(marketplace), txFee + projectFee);
        vm.expectEmit(false, true, true, false); // we don't know project ID yet
        emit ProjectCreated(42, buyer, provider); // we don't know project ID yet
        projectId = marketplace.createProject{value: txFee + projectFee}(
            provider,
            address(0),
            projectFee,
            providerStake,
            dueDate,
            reviewPeriodLength,
            detailsURI
        );
        vm.stopPrank();
        p = marketplace.getProject(projectId);
        assertEq(p.projectId, projectId);
        assertEq(p.buyer, buyer);
        assertEq(p.provider, provider);
        assertEq(p.paymentToken, address(0)); 
        assertEq(p.projectFee, projectFee);
        assertEq(p.providerStake, providerStake);
        assertEq(p.dueDate, dueDate);
        assertEq(p.reviewPeriodLength, reviewPeriodLength);
        assertEq(p.dateCompleted, 0);
        assertEq(p.changeOrderPeriodInitiated, 0);
        assertEq(uint(p.status), uint(Marketplace.Status.Created));
        assertEq(p.detailsURI, detailsURI);
        // fees captured: 
        assertEq(address(marketplace).balance, contractMaticBalBefore + txFee);
        assertEq(marketplace.getTxFeesHeld(p.projectId), txFee);
        // ....
        // we will test escrow separately
    }

    /// TEST CREATE REVERT

    function test_cancelProject() public {
        uint256 contractBalBefore = address(marketplace).balance;
        uint256 buyerBalBefore = buyer.balance;
        uint256 txFeeHeld = marketplace.getTxFeesHeld(testProjectId_MATIC);
        vm.prank(buyer);
        vm.expectEmit(true, true, true, false);
        emit ProjectCancelled(testProjectId_MATIC, buyer, provider);
        marketplace.cancelProject(testProjectId_MATIC);
        Marketplace.Project memory p = marketplace.getProject(testProjectId_MATIC);
        assertEq(uint(p.status), uint(Marketplace.Status.Cancelled));
        assertEq(marketplace.getTxFeesHeld(p.projectId), 0);
        assertEq(address(marketplace).balance, contractBalBefore - txFeeHeld);
        assertEq(buyer.balance, buyerBalBefore + txFeeHeld);
        // and once again for ERC20:
        contractBalBefore = usdt.balanceOf(address(marketplace));
        buyerBalBefore = usdt.balanceOf(buyer);
        txFeeHeld = marketplace.getTxFeesHeld(testProjectId_ERC20);
        vm.prank(buyer);
        vm.expectEmit(true, true, true, false);
        emit ProjectCancelled(testProjectId_ERC20, buyer, provider);
        marketplace.cancelProject(testProjectId_ERC20);
        p = marketplace.getProject(testProjectId_ERC20);
        assertEq(uint(p.status), uint(Marketplace.Status.Cancelled));
        assertEq(marketplace.getTxFeesHeld(p.projectId), 0);
        assertEq(usdt.balanceOf(address(marketplace)), contractBalBefore - txFeeHeld);
        assertEq(usdt.balanceOf(buyer), buyerBalBefore + txFeeHeld);
    }

    function test_cancelProject_revert() public {
        // not buyer
        vm.expectRevert(Marketplace.Marketplace__OnlyBuyer.selector);
        vm.prank(provider);
        marketplace.cancelProject(testProjectId_MATIC);
        // wrong status
        vm.prank(buyer);
        marketplace.cancelProject(testProjectId_MATIC); // cancel project
        vm.expectRevert(Marketplace.Marketplace__ProjectCannotBeCancelled.selector);
        vm.prank(buyer);
        marketplace.cancelProject(testProjectId_MATIC);
    }

    function test_activateProject() public {
        Marketplace.Project memory p = marketplace.getProject(testProjectId_MATIC);
        uint256 txFeesHeldBefore = marketplace.getTxFeesHeld(p.projectId);
        uint256 txFeesPaidBefore = marketplace.getTxFeesPaid(p.paymentToken);
        vm.prank(provider);
        vm.expectEmit(true, true, true, false);
        emit ProjectActivated(p.projectId, p.buyer, p.provider);
        marketplace.activateProject{value: p.providerStake}(p.projectId);
        p = marketplace.getProject(p.projectId);
        assertEq(uint(p.status), uint(Marketplace.Status.Active));
        assertEq(marketplace.getTxFeesHeld(p.projectId), 0);
        assertEq(marketplace.getTxFeesPaid(p.paymentToken), txFeesPaidBefore + txFeesHeldBefore);
    }

    function test_activateProject_revert() public {
        Marketplace.Project memory p = marketplace.getProject(testProjectId_MATIC);
        // not provider
        vm.expectRevert(Marketplace.Marketplace__OnlyProvider.selector);
        vm.prank(buyer);
        marketplace.activateProject(p.projectId);
        // insufficient value
        vm.expectRevert(Marketplace.Marketplace__InsufficientAmount.selector);
        vm.prank(provider);
        marketplace.activateProject{value: p.providerStake - 1}(p.projectId);
        // wrong status
        vm.prank(buyer);
        marketplace.cancelProject(p.projectId);
        vm.expectRevert(Marketplace.Marketplace__ProjectCannotBeActivated.selector);
        vm.prank(provider);
        marketplace.activateProject{value: p.providerStake}(p.projectId);       
    }

    function test_discontinueProject() public {
        Marketplace.Project memory p = marketplace.getProject(testProjectId_ERC20);
        vm.prank(provider);
        usdt.approve(address(marketplace), p.providerStake);
        vm.prank(provider);
        marketplace.activateProject(p.projectId);
        // buyer discontinues project - proposed 75% payment for work completed
        vm.prank(buyer);
        vm.expectEmit(true, true, true, false);
        emit ProjectDiscontinued(p.projectId, p.buyer, p.provider);
        marketplace.discontinueProject(
            p.projectId,
            changeOrderAdjustedProjectFee,
            0,
            changeOrderDetailsURI
        );
        p = marketplace.getProject(testProjectId_ERC20);
        assertEq(uint(p.status), uint(Marketplace.Status.Discontinued));
        assertEq(p.changeOrderPeriodInitiated, block.timestamp);
        // change order in dedicated test...
    }

    function test_discontinueProject_reverts() public {
        // project not active
        vm.expectRevert(Marketplace.Marketplace__ProjectMustBeActive.selector);
        vm.prank(buyer);
        marketplace.discontinueProject(
            testProjectId_MATIC,
            changeOrderAdjustedProjectFee,
            0,
            changeOrderDetailsURI
        );
    }

    function test_completeProject() public {
        Marketplace.Project memory p = marketplace.getProject(testProjectId_ERC20);
        vm.startPrank(provider);
        usdt.approve(address(marketplace), p.providerStake);
        marketplace.activateProject(p.projectId);
        vm.expectEmit(true, true, true, false);
        emit ProjectCompleted(p.projectId, p.buyer, p.provider);
        marketplace.completeProject(p.projectId);
        vm.stopPrank();
        p = marketplace.getProject(p.projectId);
        assertEq(uint(p.status), uint(Marketplace.Status.Completed));
        assertEq(p.dateCompleted, block.timestamp);
    }

    function test_completeProject_revert() public {
        Marketplace.Project memory p = marketplace.getProject(testProjectId_MATIC);
        // not provider
        vm.expectRevert(Marketplace.Marketplace__OnlyProvider.selector);
        vm.prank(buyer);
        marketplace.completeProject(p.projectId);
        // not active
        vm.prank(buyer);
        marketplace.cancelProject(p.projectId);
        vm.expectRevert(Marketplace.Marketplace__ProjectMustBeActive.selector);
        vm.prank(provider);
        marketplace.completeProject(p.projectId);     
    }

    function test_approve_project() public {
        Marketplace.Project memory p = marketplace.getProject(testProjectId_ERC20);
        vm.startPrank(provider);
        usdt.approve(address(marketplace), p.providerStake);
        marketplace.activateProject(p.projectId);
        marketplace.completeProject(p.projectId);
        vm.stopPrank();
        vm.prank(buyer);
        vm.expectEmit(true, true, true, false);
        emit ProjectApproved(p.projectId, p.buyer, p.provider);
        marketplace.approveProject(p.projectId);
        p = marketplace.getProject(testProjectId_ERC20);
        assertEq(uint(p.status), uint(Marketplace.Status.Approved));
    }

    function test_approve_project_revert() public {
        Marketplace.Project memory p = marketplace.getProject(testProjectId_MATIC);
        vm.prank(provider);
        marketplace.activateProject{value: p.providerStake}(p.projectId);
        // not active
        vm.expectRevert(Marketplace.Marketplace__ProjectNotCompleted.selector);
        vm.prank(buyer);
        marketplace.approveProject(p.projectId);
        // not buyer
        vm.prank(provider);
        marketplace.completeProject(p.projectId);
        vm.expectRevert(Marketplace.Marketplace__OnlyBuyer.selector);
        vm.prank(provider);
        marketplace.approveProject(p.projectId);
    }

    function test_challengeProject() public {
        Marketplace.Project memory p = marketplace.getProject(testProjectId_MATIC);
        vm.prank(provider);
        marketplace.activateProject{value: p.providerStake}(p.projectId);
        // project has gone past due date, so buyer challenges
        vm.warp(p.dueDate + 1);
        // marketplace.completeProject(p.projectId);
        vm.expectEmit(true, true, true, false);
        emit ProjectChallenged(p.projectId, p.buyer, p.provider);
        vm.prank(buyer);
        marketplace.challengeProject(
            p.projectId,
            changeOrderAdjustedProjectFee,
            p.providerStake,
            changeOrderDetailsURI
        );
        p = marketplace.getProject(testProjectId_MATIC);
        assertEq(uint(p.status), uint(Marketplace.Status.Challenged));
        assertEq(p.changeOrderPeriodInitiated, block.timestamp);
    }

    function test_challengeProject_revert() public {
        Marketplace.Project memory p = marketplace.getProject(testProjectId_MATIC);
        vm.prank(provider);
        marketplace.activateProject{value: p.providerStake}(p.projectId);
        // active but not past due date
        assertTrue(block.timestamp < p.dueDate);
        vm.expectRevert(Marketplace.Marketplace__ProjectIsNotOverdue.selector);
        vm.prank(buyer);
        marketplace.challengeProject(
            p.projectId,
            changeOrderAdjustedProjectFee,
            p.providerStake,
            changeOrderDetailsURI
        );
        // completed but past review period
        vm.prank(provider);
        marketplace.completeProject(p.projectId);
        vm.warp(p.dueDate + p.reviewPeriodLength + 1);
        vm.expectRevert(Marketplace.Marketplace__ProjectReviewPeriodEnded.selector);
        vm.prank(buyer);
        marketplace.challengeProject(
            p.projectId,
            changeOrderAdjustedProjectFee,
            p.providerStake,
            changeOrderDetailsURI
        );
        // wrong status
        p = marketplace.getProject(testProjectId_ERC20);
        vm.expectRevert(Marketplace.Marketplace__ProjectCannotBeChallenged.selector);
        vm.prank(buyer);
        marketplace.challengeProject(
            p.projectId,
            changeOrderAdjustedProjectFee,
            p.providerStake,
            changeOrderDetailsURI
        );
    }

    function test_delinquentPayment() public {
        Marketplace.Project memory p = marketplace.getProject(testProjectId_MATIC);
        vm.prank(provider);
        marketplace.activateProject{value: p.providerStake}(p.projectId);
        vm.prank(provider);
        marketplace.completeProject(p.projectId);
        // review period passes but buyer does not sign
        vm.warp(block.timestamp + p.reviewPeriodLength + 1);
        vm.expectEmit(true, true, true, false);
        emit DelinquentPayment(p.projectId, p.buyer, p.provider);
        vm.prank(provider);
        marketplace.delinquentPayment(p.projectId);
        p = marketplace.getProject(testProjectId_MATIC);
        assertEq(uint(p.status), uint(Marketplace.Status.Resolved_DelinquentPayment));
    }

    function test_delinquentPayment_revert() public {
        Marketplace.Project memory p = marketplace.getProject(testProjectId_MATIC);
        vm.prank(provider);
        marketplace.activateProject{value: p.providerStake}(p.projectId);
        // wrong status
        vm.expectRevert(Marketplace.Marketplace__PaymentIsNotDelinquent.selector);
        vm.prank(provider);
        marketplace.delinquentPayment(p.projectId);
        // completed, but still within review period
        vm.prank(provider);
        marketplace.completeProject(p.projectId);
        vm.expectRevert(Marketplace.Marketplace__PaymentIsNotDelinquent.selector);
        vm.prank(provider);
        marketplace.delinquentPayment(p.projectId);
    }

    /////////////////////////////////
    ///  DISPUTES & ARBITRATION   ///
    /////////////////////////////////

    function test_disputeProject() public {
        Marketplace.Project memory p = marketplace.getProject(testProjectId_MATIC);
        vm.prank(provider);
        marketplace.activateProject{value: p.providerStake}(p.projectId);
        vm.prank(provider);
        marketplace.completeProject(p.projectId);
        vm.prank(buyer);
        marketplace.challengeProject(
            p.projectId,
            changeOrderAdjustedProjectFee,
            p.providerStake,
            changeOrderDetailsURI
        );
        // change order period passes
        vm.warp(block.timestamp + marketplace.CHANGE_ORDER_PERIOD() + 1);
        vm.expectEmit(true, true, true, false);
        emit ProjectDisputed(p.projectId, p.buyer, p.provider, 42);
        vm.prank(buyer);
        uint256 petitionId = marketplace.disputeProject(
            p.projectId,
            changeOrderAdjustedProjectFee,
            p.providerStake
        );
        p = marketplace.getProject(testProjectId_MATIC);
        assertEq(uint(p.status), uint(Marketplace.Status.Disputed));
        assertEq(marketplace.getArbitrationPetitionId(p.projectId), petitionId);
        // change order has been reset to default
        assertEq(marketplace.activeChangeOrder(p.projectId), false);
    }

    function test_appealRuling() public {
        vm.pauseGasMetering();
        _disputedProjectWithRuling(testProjectId_ERC20);
        vm.resumeGasMetering();
        Marketplace.Project memory p = marketplace.getProject(testProjectId_ERC20);
        Court.Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(p.projectId));
        assertEq(uint(p.status), uint(Marketplace.Status.Disputed));
        assertEq(uint(petition.phase), uint(Court.Phase.Verdict));
        assertEq(petition.isAppeal, false);
        vm.expectEmit(true, false, false, false);
        emit ProjectAppealed(p.projectId, 42, p.provider);
        vm.prank(p.provider);
        uint256 newPetitionId = marketplace.appealRuling(p.projectId);
        // new petition has been created
        Court.Petition memory appealPetition = court.getPetition(newPetitionId);
        assertEq(appealPetition.isAppeal, true);
        // project status updated
        p = marketplace.getProject(p.projectId);
        assertEq(uint(p.status), uint(Marketplace.Status.Appealed));
        // project ID mapped to new petition ID
        assertEq(marketplace.getArbitrationPetitionId(p.projectId), appealPetition.petitionId);
    }

    function test_appealRuling_revert() public {
        vm.pauseGasMetering();
        _disputedProjectWithRuling(testProjectId_ERC20);
        vm.resumeGasMetering();
        Marketplace.Project memory p = marketplace.getProject(testProjectId_MATIC); // NOT the disputed project
        // not disputed
        vm.expectRevert(Marketplace.Marketplace__ProjectIsNotDisputed.selector);
        vm.prank(p.provider);
        marketplace.appealRuling(p.projectId);
        // court has not ruled 
        _disputedProject(testProjectId_MATIC); // NOT the disputed project)
        vm.expectRevert(Marketplace.Marketplace__CourtHasNotRuled.selector);
        vm.prank(p.provider);
        marketplace.appealRuling(p.projectId);
        // appeal period over
        p = marketplace.getProject(testProjectId_ERC20); // WITH ruling
        vm.warp(block.timestamp + marketplace.APPEAL_PERIOD() + 1); // warp ahead past appeal period
        vm.expectRevert(Marketplace.Marketplace__AppealPeriodOver.selector);
        vm.prank(p.provider);
        marketplace.appealRuling(p.projectId);
    }

    function test_waiveAppeal() public {
        vm.pauseGasMetering();
        _disputedProjectWithRuling(testProjectId_MATIC);
        vm.resumeGasMetering();
        Marketplace.Project memory p = marketplace.getProject(testProjectId_MATIC);
        Court.Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(p.projectId));
        vm.expectEmit(true, true, false, false);
        emit ResolvedByCourtOrder(p.projectId, petition.petitionId);
        (petition.petitionGranted) ? vm.prank(petition.defendant) : vm.prank(petition.plaintiff); // prank non-prevailing party
        marketplace.waiveAppeal(p.projectId);
        p = marketplace.getProject(testProjectId_MATIC);
        assertEq(uint(p.status), uint(Marketplace.Status.Resolved_CourtOrder));
    }

    function test_waiveAppeal_revert() public {
        Marketplace.Project memory p = marketplace.getProject(testProjectId_MATIC);
        // not disputed
        vm.expectRevert(Marketplace.Marketplace__ProjectIsNotDisputed.selector);
        vm.prank(p.provider);
        marketplace.waiveAppeal(p.projectId);
        // court has not ruled 
        _disputedProject(testProjectId_MATIC);
        p = marketplace.getProject(testProjectId_MATIC);
        vm.expectRevert(Marketplace.Marketplace__CourtHasNotRuled.selector);
        vm.prank(p.provider);
        marketplace.waiveAppeal(p.projectId);
        // not non-prevailing party
        _disputedProjectWithRuling(testProjectId_ERC20);
        p = marketplace.getProject(testProjectId_ERC20);
        Court.Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(p.projectId));
        vm.expectRevert(Marketplace.Marketplace__OnlyNonPrevailingParty.selector);
        (petition.petitionGranted) ? vm.prank(petition.plaintiff) : vm.prank(petition.defendant); // prank prevailing party
        marketplace.waiveAppeal(p.projectId);
    }

    function test_resolveByCourtOrder() public {
        vm.pauseGasMetering();
        _disputedProjectWithRuling(testProjectId_MATIC);
        vm.resumeGasMetering();
        Marketplace.Project memory p = marketplace.getProject(testProjectId_MATIC);
        vm.warp(block.timestamp + marketplace.APPEAL_PERIOD() + 1); 
        vm.expectEmit(true, true, false, false);
        emit ResolvedByCourtOrder(p.projectId, marketplace.getArbitrationPetitionId(p.projectId));
        vm.prank(p.buyer);
        marketplace.resolveByCourtOrder(p.projectId);
        p = marketplace.getProject(testProjectId_MATIC);
        assertEq(uint(p.status), uint(Marketplace.Status.Resolved_CourtOrder));
    }

    function test_resolveByCourtOrder_revert() public {
        Marketplace.Project memory p = marketplace.getProject(testProjectId_MATIC);
        // not disputed
        vm.expectRevert(Marketplace.Marketplace__ProjectIsNotDisputed.selector);
        vm.prank(p.buyer);
        marketplace.resolveByCourtOrder(p.projectId);
        // court has not ruled 
        _disputedProject(testProjectId_MATIC);
        p = marketplace.getProject(testProjectId_MATIC);
        vm.expectRevert(Marketplace.Marketplace__CourtHasNotRuled.selector);
        vm.prank(p.buyer);
        marketplace.resolveByCourtOrder(p.projectId);
        // appeal period not over
        _disputedProjectWithRuling(testProjectId_ERC20);
        p = marketplace.getProject(testProjectId_ERC20);
        vm.expectRevert(Marketplace.Marketplace__AppealPeriodNotOver.selector);
        vm.prank(p.buyer);
        marketplace.resolveByCourtOrder(p.projectId);
    }

    function test_resolveDismissedCase() public {
        vm.pauseGasMetering();
        uint256 petitionId = _disputedProject(testProjectId_ERC20);
        vm.resumeGasMetering();
        vm.warp(block.timestamp + court.DISCOVERY_PERIOD() + 1);
        court.dismissUnpaidCase(petitionId);
        Marketplace.Project memory p = marketplace.getProject(testProjectId_ERC20);
        vm.expectEmit(true, true, false, false);
        emit ResolvedByDismissedCase(p.projectId, petitionId);
        vm.prank(p.buyer);
        marketplace.resolveDismissedCase(p.projectId);
        p = marketplace.getProject(testProjectId_ERC20);
        assertEq(uint(p.status), uint(Marketplace.Status.Resolved_ArbitrationDismissed));
    }

    function test_resolveDismissedCase_revert() public {
        Marketplace.Project memory p = marketplace.getProject(testProjectId_ERC20);
        // not disputed 
        vm.expectRevert(Marketplace.Marketplace__ProjectIsNotDisputed.selector);
        vm.prank(p.buyer);
        marketplace.resolveDismissedCase(p.projectId);
        // assertEq(marketplace.isDisputed(p.projectId), false);
        // not dismissed case
        _disputedProjectWithRuling(testProjectId_ERC20); 
        p = marketplace.getProject(testProjectId_ERC20);
        // assertEq(marketplace.isDisputed(p.projectId), true);
        Court.Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(p.projectId));
        assertFalse(uint(petition.phase) == uint(Court.Phase.Dismissed));
        vm.expectRevert(Marketplace.Marketplace__CourtHasNotDismissedCase.selector);
        vm.prank(p.buyer);
        marketplace.resolveDismissedCase(p.projectId);

    }


    //////////////////////////////
    ///   CHANGE ORDER TESTS   ///
    //////////////////////////////

    function test_proposeChangeOrder() public {
        Marketplace.Project memory p = marketplace.getProject(testProjectId_ERC20);
        assertEq(marketplace.activeChangeOrder(p.projectId), false);
        // get discontinued project with change order
        vm.pauseGasMetering();
        test_discontinueProject(); // uses ERC20 project
        vm.resumeGasMetering();
        assertEq(marketplace.activeChangeOrder(p.projectId), true);
        Marketplace.ChangeOrder memory c = marketplace.getChangeOrder(p.projectId);
        assertEq(c.projectId, p.projectId);
        assertEq(c.dateProposed, block.timestamp);
        assertEq(c.proposedBy, buyer);
        assertEq(c.adjustedProjectFee, changeOrderAdjustedProjectFee);
        assertEq(c.providerStakeForfeit, 0);
        assertEq(c.buyerApproval, true);
        assertEq(c.providerApproval, false);
        assertEq(c.detailsURI, changeOrderDetailsURI);
    }

    function test_proposeChangeOrder_revert() public {
        Marketplace.Project memory p = marketplace.getProject(testProjectId_ERC20);
        vm.prank(provider);
        usdt.approve(address(marketplace), p.providerStake);
        vm.prank(provider);
        marketplace.activateProject(p.projectId);
        // adjusted project fee too high
        vm.expectRevert(Marketplace.Marketplace__AdjustedFeeExceedsProjectFee.selector);
        vm.prank(buyer);
        marketplace.discontinueProject(
            p.projectId,
            p.projectFee + 1,
            p.providerStake,
            changeOrderDetailsURI
        );
        // provider stake forfeit too high
        vm.expectRevert(Marketplace.Marketplace__ForfeitExceedsProviderStake.selector);
        vm.prank(buyer);
        marketplace.discontinueProject(
            p.projectId,
            p.projectFee,
            p.providerStake + 1,
            changeOrderDetailsURI
        );
    }

    function test_approveChangeOrder() public {
        Marketplace.Project memory p = marketplace.getProject(testProjectId_ERC20);
        vm.pauseGasMetering();
        test_proposeChangeOrder(); // gets change order from discontinued ERC20 project, already signed by buyer
        vm.resumeGasMetering();
        vm.prank(provider);
        vm.expectEmit(true, true, true, false);
        emit ChangeOrderApproved(p.projectId, p.buyer, p.provider);
        marketplace.approveChangeOrder(p.projectId);
        p = marketplace.getProject(testProjectId_ERC20);
        assertEq(uint(p.status), uint(Marketplace.Status.Resolved_ChangeOrder));
        Marketplace.ChangeOrder memory c = marketplace.getChangeOrder(p.projectId);
        assertEq(c.providerApproval, true);
    }

    function test_approveChangeOrder_revert() public {
        Marketplace.Project memory p = marketplace.getProject(testProjectId_ERC20);
        vm.pauseGasMetering();
        test_proposeChangeOrder(); // gets change order from discontinued ERC20 project, already signed by buyer
        vm.resumeGasMetering();
        // already approved
        vm.expectRevert(Marketplace.Marketplace__AlreadyApprovedChangeOrder.selector);
        vm.prank(buyer);
        marketplace.approveChangeOrder(p.projectId);
        // wrong status
        vm.prank(provider);
        marketplace.approveChangeOrder(p.projectId);
        p = marketplace.getProject(testProjectId_ERC20);
        assertEq(uint(p.status), uint(Marketplace.Status.Resolved_ChangeOrder));
        vm.expectRevert(Marketplace.Marketplace__ChangeOrderNotValid.selector);
        vm.prank(provider);
        marketplace.approveChangeOrder(p.projectId);
    }

    function test_proposeCounterOffer() public {
        Marketplace.Project memory p = marketplace.getProject(testProjectId_ERC20);
        assertEq(marketplace.activeChangeOrder(p.projectId), false);
        // get discontinued project with change order
        vm.pauseGasMetering();
        test_discontinueProject(); // uses ERC20 project
        vm.resumeGasMetering();
        uint256 counterAdjProjFee = 800 ether;
        uint256 counterProvStake = 0;
        string memory counterUri = "ipfs://counterUri/";
        vm.prank(provider);
        marketplace.proposeCounterOffer(
            p.projectId,
            counterAdjProjFee,
            counterProvStake,
            counterUri
        );
        Marketplace.ChangeOrder memory c = marketplace.getChangeOrder(p.projectId);
        assertEq(c.projectId, p.projectId);
        assertEq(c.adjustedProjectFee, counterAdjProjFee);
        assertEq(c.providerStakeForfeit, counterProvStake);
        assertEq(c.detailsURI, counterUri);
        assertEq(c.buyerApproval, false);
        assertEq(c.providerApproval, true);
    }

    function test_proposeCounterOffer_revert() public {
        // no active change order
        Marketplace.Project memory p = marketplace.getProject(testProjectId_MATIC);
        assertEq(marketplace.activeChangeOrder(p.projectId), false);
        vm.expectRevert(Marketplace.Marketplace__NoActiveChangeOrder.selector);
        vm.prank(buyer);
        marketplace.proposeCounterOffer(p.projectId, 0, 0, "details");
        // unauthorized user
        p = marketplace.getProject(testProjectId_ERC20);
        vm.pauseGasMetering();
        test_discontinueProject(); // uses ERC20 project
        vm.resumeGasMetering();
        vm.prank(carlos);
        vm.expectRevert(Marketplace.Marketplace__OnlyBuyerOrProvider.selector);
        marketplace.proposeCounterOffer(p.projectId, 0, 0, "details");
        // disputed case, but court hasn't ruled yet
    }


    ////////////////////////
    ///   ESCROW TESTS   ///
    ////////////////////////

    function test_escrow_deployment() public {
        address escrowAddress = marketplace.getProject(testProjectId_MATIC).escrow;
        IEscrow escrow = IEscrow(escrowAddress);
        // state variables initialized correctly:
        assertEq(escrow.MARKETPLACE(), address(marketplace));
        assertEq(escrow.PROJECT_ID(), testProjectId_MATIC);
        assertEq(escrow.BUYER(), buyer);
        assertEq(escrow.PROVIDER(), provider);
        assertEq(escrow.PAYMENT_TOKEN(), address(0));
        assertEq(escrow.PROJECT_FEE(), projectFee);
        assertEq(escrow.PROVIDER_STAKE(), providerStake);
        // escrow is holding project fee
        assertEq(escrowAddress.balance, projectFee);
        // and again, but for ERC20:
        escrowAddress = marketplace.getProject(testProjectId_ERC20).escrow;
        escrow = IEscrow(escrowAddress);
        assertEq(usdt.balanceOf(escrowAddress), projectFee);
    }

    function test_escrow_providerStake_payment() public {
        vm.prank(provider);
        usdt.approve(address(marketplace), providerStake);
        vm.prank(provider);
        marketplace.activateProject(testProjectId_ERC20);
        IEscrow escrow = IEscrow(marketplace.getProject(testProjectId_ERC20).escrow);
        assertTrue(escrow.providerHasStaked());
        // assertEq(escrow.verifyProviderStake(), true);
    }

    // function test_escrow_approved_project() public {
    //     Marketplace.Project memory p = marketplace.getProject(testProjectId_ERC20);
    //     IEscrow escrow = IEscrow(p.escrow);
    //     vm.startPrank(provider);
    //     usdt.approve(address(marketplace), p.providerStake);
    //     marketplace.activateProject(p.projectId);
    //     marketplace.completeProject(p.projectId);
    //     vm.stopPrank();
    //     vm.prank(buyer);
    //     marketplace.approveProject(p.projectId);
    //     // users claim
    // }

    // internals
        // approving / removing erc20

}
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/Interfaces/IEscrow.sol";
import "forge-std/console.sol";

contract MarketplaceMediationTest is Test, TestSetup {

    uint256 project_dispute_granted;
    uint256 project_dispute_denied;

    // event SettlementProposed(uint256 indexed projectId, uint256 indexed disputeId);
    event ProjectAppealed(uint256 indexed projectId, uint256 indexed disputeId, address appealedBy);
    event ResolvedByMediation(uint256 indexed projectId, uint256 indexed disputeId);
    event ResolvedByDismissedCase(uint256 indexed projectId, uint256 indexed disputeId);

    function setUp() public {
        _setUp();
        _whitelistUsers();
        _registerMediators();
        _initializeTestProjects();
        _initializeMediationProjects();
        // set up completed mediationService cases
        project_dispute_granted = _disclosureToResolved(id_mediation_disclosure_ERC20, true);
        project_dispute_denied = _disclosureToResolved(id_mediation_disclosure_MATIC, false);
    }

    function test_appealReveal() public {
        Project memory project = marketplace.getProject(project_dispute_granted);
        uint256 originalDisputeId = marketplace.getDisputeId(project.projectId);
        uint256 currentDisputeId = mediationService.disputeIds();

        vm.expectEmit(true, true, false, true);
        emit ProjectAppealed(project.projectId, currentDisputeId + 1, project.provider);
        vm.prank(project.provider);
        uint256 newDisputeId = marketplace.appealReveal(project.projectId);

        // status changed
        project = marketplace.getProject(project.projectId);
        assertEq(uint(project.status), uint(Status.Appealed));
        // new dispute created
        assertTrue(originalDisputeId != newDisputeId);
        assertEq(marketplace.getDisputeId(project.projectId), newDisputeId);
    }

    function test_appealReveal_revert() public {
        // project not disputed
        Project memory project = marketplace.getProject(id_challenged_ERC20);
        vm.expectRevert(Marketplace.Marketplace__ProjectIsNotDisputed.selector);
        vm.prank(project.buyer);
        marketplace.appealReveal(project.projectId);
        // mediationService has not ruled
        project = marketplace.getProject(id_mediation_committedVotes_MATIC);
        vm.expectRevert(Marketplace.Marketplace__MediationServiceHasNotRuled.selector);
        vm.prank(project.buyer);
        marketplace.appealReveal(project.projectId);
        // not buyer or provider
        project = marketplace.getProject(project_dispute_granted);
        vm.expectRevert(Marketplace.Marketplace__OnlyBuyerOrProvider.selector);
        vm.prank(admin1);
        marketplace.appealReveal(project.projectId);
        // appeal period over
        vm.warp(block.timestamp + marketplace.APPEAL_PERIOD());
        vm.expectRevert(Marketplace.Marketplace__AppealPeriodOver.selector);
        vm.prank(project.buyer);
        marketplace.appealReveal(project.projectId);
    }

    function test_waiveAppeal() public {
        Project memory project = marketplace.getProject(project_dispute_granted);
        assertEq(uint(project.status), uint(Status.Disputed));
    
        vm.expectEmit(true, true, false, false);
        emit ResolvedByMediation(project.projectId, marketplace.getDisputeId(project.projectId));
        vm.prank(project.provider);
        marketplace.waiveAppeal(project.projectId);

        // status changed
        project = marketplace.getProject(project.projectId);
        assertEq(uint(project.status), uint(Status.Resolved_Mediation));
    }

    function test_waiveAppeal_revert() public {
        // not disputed
        vm.expectRevert(Marketplace.Marketplace__ProjectIsNotDisputed.selector);
        vm.prank(alice);
        marketplace.waiveAppeal(id_challenged_ERC20);
        // mediationService has not ruled
        Project memory project = marketplace.getProject(id_mediation_committedVotes_MATIC);
        vm.expectRevert(Marketplace.Marketplace__MediationServiceHasNotRuled.selector);
        vm.prank(project.provider);
        marketplace.waiveAppeal(project.projectId);
        // not non-prevailing party
        project = marketplace.getProject(project_dispute_denied);
        vm.expectRevert(Marketplace.Marketplace__OnlyNonPrevailingParty.selector);
        vm.prank(project.provider); // provider is winner in this case
        marketplace.waiveAppeal(project.projectId);
    }

    function test_resolveByMediation() public {
        Project memory project = marketplace.getProject(project_dispute_denied);
        assertEq(uint(project.status), uint(Status.Disputed));
        vm.warp(block.timestamp + marketplace.APPEAL_PERIOD() + 1);

        vm.expectEmit(true, true, false, false);
        emit ResolvedByMediation(project.projectId, marketplace.getDisputeId(project.projectId));
        vm.prank(project.provider);
        marketplace.resolveByMediation(project.projectId);

        // status changed
        project = marketplace.getProject(project.projectId);
        assertEq(uint(project.status), uint(Status.Resolved_Mediation));
    }

    function test_resolveByMediation_revert() public {
        Project memory project = marketplace.getProject(project_dispute_denied);
        // not buyer or provider
        vm.expectRevert(Marketplace.Marketplace__OnlyBuyerOrProvider.selector);
        vm.prank(zorro);
        marketplace.resolveByMediation(project.projectId);
        // project not disputed
        project = marketplace.getProject(id_challenged_ERC20);
        vm.expectRevert(Marketplace.Marketplace__ProjectIsNotDisputed.selector);
        vm.prank(project.buyer);
        marketplace.resolveByMediation(project.projectId);
        // mediationService has not ruled
        project = marketplace.getProject(id_mediation_committedVotes_MATIC);
        vm.expectRevert(Marketplace.Marketplace__MediationServiceHasNotRuled.selector);
        vm.prank(project.buyer);
        marketplace.resolveByMediation(project.projectId);
        // appeal period not over
        project = marketplace.getProject(project_dispute_denied);
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(project.projectId));
        assertTrue(block.timestamp < dispute.decisionRenderedDate + marketplace.APPEAL_PERIOD());
        vm.expectRevert(Marketplace.Marketplace__AppealPeriodNotOver.selector);
        vm.prank(project.buyer);
        marketplace.resolveByMediation(project.projectId);
    }

    function test_resolveDismissedCase() public {
        Project memory project = marketplace.getProject(id_challenged_MATIC);
        _disputeProject(project.projectId, changeOrderAdjustedProjectFee, changeOrderProviderStakeForfeit);
        vm.warp(block.timestamp + mediationService.DISCLOSURE_PERIOD() + 1);
        mediationService.dismissUnpaidCase(marketplace.getDisputeId(project.projectId));

        vm.expectEmit(true, true, false, false);
        emit ResolvedByDismissedCase(project.projectId, marketplace.getDisputeId(project.projectId));
        vm.prank(project.provider);
        marketplace.resolveDismissedCase(project.projectId);

        // status changed
        project = marketplace.getProject(project.projectId);
        assertEq(uint(project.status), uint(Status.Resolved_MediationDismissed));
    }

    function test_resolveDismissedCase_revert() public {
        Project memory project = marketplace.getProject(id_challenged_MATIC);
        _disputeProject(project.projectId, changeOrderAdjustedProjectFee, changeOrderProviderStakeForfeit);
        vm.warp(block.timestamp + mediationService.DISCLOSURE_PERIOD() + 1);
        mediationService.dismissUnpaidCase(marketplace.getDisputeId(project.projectId));
        // not buyer or provider
        vm.expectRevert(Marketplace.Marketplace__OnlyBuyerOrProvider.selector);
        vm.prank(zorro);
        marketplace.resolveDismissedCase(project.projectId);
        // project not disputed
        project = marketplace.getProject(id_challenged_ERC20);
        vm.expectRevert(Marketplace.Marketplace__ProjectIsNotDisputed.selector);
        vm.prank(project.buyer);
        marketplace.resolveDismissedCase(project.projectId);
        // mediationService has not dismissed
        project = marketplace.getProject(id_mediation_committedVotes_MATIC);
        vm.expectRevert(Marketplace.Marketplace__MediationServiceHasNotDismissedCase.selector);
        vm.prank(project.buyer);
        marketplace.resolveDismissedCase(project.projectId);
    }
    
}
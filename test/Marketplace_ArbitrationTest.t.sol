// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/Interfaces/IEscrow.sol";
import "forge-std/console.sol";

contract MarketplaceArbitrationTest is Test, TestSetup {

    uint256 project_petition_granted;
    uint256 project_petition_denied;

    // event SettlementProposed(uint256 indexed projectId, uint256 indexed petitionId);
    event ProjectAppealed(uint256 indexed projectId, uint256 indexed petitionId, address appealedBy);
    event ResolvedByCourtOrder(uint256 indexed projectId, uint256 indexed petitionId);
    event ResolvedByDismissedCase(uint256 indexed projectId, uint256 indexed petitionId);

    function setUp() public {
        _setUp();
        _whitelistUsers();
        _registerJurors();
        _initializeTestProjects();
        _initializeArbitrationProjects();
        // set up completed court cases
        project_petition_granted = _discoveryToResolved(id_arbitration_discovery_ERC20, true);
        project_petition_denied = _discoveryToResolved(id_arbitration_discovery_MATIC, false);
    }

    function test_appealRuling() public {
        Project memory project = marketplace.getProject(project_petition_granted);
        uint256 originalPetitionId = marketplace.getArbitrationPetitionId(project.projectId);
        uint256 currentPetitionId = court.petitionIds();

        vm.expectEmit(true, true, false, true);
        emit ProjectAppealed(project.projectId, currentPetitionId + 1, project.provider);
        vm.prank(project.provider);
        uint256 newPetitionId = marketplace.appealRuling(project.projectId);

        // status changed
        project = marketplace.getProject(project.projectId);
        assertEq(uint(project.status), uint(Status.Appealed));
        // new petition created
        assertTrue(originalPetitionId != newPetitionId);
        assertEq(marketplace.getArbitrationPetitionId(project.projectId), newPetitionId);
    }

    function test_appealRuling_revert() public {
        // project not disputed
        Project memory project = marketplace.getProject(id_challenged_ERC20);
        vm.expectRevert(Marketplace.Marketplace__ProjectIsNotDisputed.selector);
        vm.prank(project.buyer);
        marketplace.appealRuling(project.projectId);
        // court has not ruled
        project = marketplace.getProject(id_arbitration_committedVotes_MATIC);
        vm.expectRevert(Marketplace.Marketplace__CourtHasNotRuled.selector);
        vm.prank(project.buyer);
        marketplace.appealRuling(project.projectId);
        // not buyer or provider
        project = marketplace.getProject(project_petition_granted);
        vm.expectRevert(Marketplace.Marketplace__OnlyBuyerOrProvider.selector);
        vm.prank(admin1);
        marketplace.appealRuling(project.projectId);
        // appeal period over
        vm.warp(block.timestamp + marketplace.APPEAL_PERIOD());
        vm.expectRevert(Marketplace.Marketplace__AppealPeriodOver.selector);
        vm.prank(project.buyer);
        marketplace.appealRuling(project.projectId);
    }

    function test_waiveAppeal() public {
        Project memory project = marketplace.getProject(project_petition_granted);
        assertEq(uint(project.status), uint(Status.Disputed));
    
        vm.expectEmit(true, true, false, false);
        emit ResolvedByCourtOrder(project.projectId, marketplace.getArbitrationPetitionId(project.projectId));
        vm.prank(project.provider);
        marketplace.waiveAppeal(project.projectId);

        // status changed
        project = marketplace.getProject(project.projectId);
        assertEq(uint(project.status), uint(Status.Resolved_CourtOrder));
    }

    function test_waiveAppeal_revert() public {
        // not disputed
        vm.expectRevert(Marketplace.Marketplace__ProjectIsNotDisputed.selector);
        vm.prank(alice);
        marketplace.waiveAppeal(id_challenged_ERC20);
        // court has not ruled
        Project memory project = marketplace.getProject(id_arbitration_committedVotes_MATIC);
        vm.expectRevert(Marketplace.Marketplace__CourtHasNotRuled.selector);
        vm.prank(project.provider);
        marketplace.waiveAppeal(project.projectId);
        // not non-prevailing party
        project = marketplace.getProject(project_petition_denied);
        vm.expectRevert(Marketplace.Marketplace__OnlyNonPrevailingParty.selector);
        vm.prank(project.provider); // provider is winner in this case
        marketplace.waiveAppeal(project.projectId);
    }

    function test_resolveByCourtOrder() public {
        Project memory project = marketplace.getProject(project_petition_denied);
        assertEq(uint(project.status), uint(Status.Disputed));
        vm.warp(block.timestamp + marketplace.APPEAL_PERIOD() + 1);

        vm.expectEmit(true, true, false, false);
        emit ResolvedByCourtOrder(project.projectId, marketplace.getArbitrationPetitionId(project.projectId));
        vm.prank(project.provider);
        marketplace.resolveByCourtOrder(project.projectId);

        // status changed
        project = marketplace.getProject(project.projectId);
        assertEq(uint(project.status), uint(Status.Resolved_CourtOrder));
    }

    function test_resolveByCourtOrder_revert() public {
        Project memory project = marketplace.getProject(project_petition_denied);
        // not buyer or provider
        vm.expectRevert(Marketplace.Marketplace__OnlyBuyerOrProvider.selector);
        vm.prank(zorro);
        marketplace.resolveByCourtOrder(project.projectId);
        // project not disputed
        project = marketplace.getProject(id_challenged_ERC20);
        vm.expectRevert(Marketplace.Marketplace__ProjectIsNotDisputed.selector);
        vm.prank(project.buyer);
        marketplace.resolveByCourtOrder(project.projectId);
        // court has not ruled
        project = marketplace.getProject(id_arbitration_committedVotes_MATIC);
        vm.expectRevert(Marketplace.Marketplace__CourtHasNotRuled.selector);
        vm.prank(project.buyer);
        marketplace.resolveByCourtOrder(project.projectId);
        // appeal period not over
        project = marketplace.getProject(project_petition_denied);
        Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(project.projectId));
        assertTrue(block.timestamp < petition.verdictRenderedDate + marketplace.APPEAL_PERIOD());
        vm.expectRevert(Marketplace.Marketplace__AppealPeriodNotOver.selector);
        vm.prank(project.buyer);
        marketplace.resolveByCourtOrder(project.projectId);
    }

    function test_resolveDismissedCase() public {
        Project memory project = marketplace.getProject(id_challenged_MATIC);
        _disputeProject(project.projectId, changeOrderAdjustedProjectFee, changeOrderProviderStakeForfeit);
        vm.warp(block.timestamp + court.DISCOVERY_PERIOD() + 1);
        court.dismissUnpaidCase(marketplace.getArbitrationPetitionId(project.projectId));

        vm.expectEmit(true, true, false, false);
        emit ResolvedByDismissedCase(project.projectId, marketplace.getArbitrationPetitionId(project.projectId));
        vm.prank(project.provider);
        marketplace.resolveDismissedCase(project.projectId);

        // status changed
        project = marketplace.getProject(project.projectId);
        assertEq(uint(project.status), uint(Status.Resolved_ArbitrationDismissed));
    }

    function test_resolveDismissedCase_revert() public {
        Project memory project = marketplace.getProject(id_challenged_MATIC);
        _disputeProject(project.projectId, changeOrderAdjustedProjectFee, changeOrderProviderStakeForfeit);
        vm.warp(block.timestamp + court.DISCOVERY_PERIOD() + 1);
        court.dismissUnpaidCase(marketplace.getArbitrationPetitionId(project.projectId));
        // not buyer or provider
        vm.expectRevert(Marketplace.Marketplace__OnlyBuyerOrProvider.selector);
        vm.prank(zorro);
        marketplace.resolveDismissedCase(project.projectId);
        // project not disputed
        project = marketplace.getProject(id_challenged_ERC20);
        vm.expectRevert(Marketplace.Marketplace__ProjectIsNotDisputed.selector);
        vm.prank(project.buyer);
        marketplace.resolveDismissedCase(project.projectId);
        // court has not dismissed
        project = marketplace.getProject(id_arbitration_committedVotes_MATIC);
        vm.expectRevert(Marketplace.Marketplace__CourtHasNotDismissedCase.selector);
        vm.prank(project.buyer);
        marketplace.resolveDismissedCase(project.projectId);
    }
    
}
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/Interfaces/IEscrow.sol";
import "forge-std/console.sol";

contract MarketplaceChangeOrderTest is Test, TestSetup {
    
    event ChangeOrderProposed(uint256 indexed projectId);
    event ChangeOrderApproved(uint256 indexed projectId, address indexed buyer, address indexed provider);

    function setUp() public {
        _setUp();
        _whitelistUsers();
        _registerJurors();
        _initializeTestProjects();
    }

    function test_createChangeOrder() public {
        Project memory project = marketplace.getProject(id_complete_ERC20);
        uint256 id = marketplace.changeOrderIds();
        assertEq(marketplace.activeChangeOrder(project.projectId), false);

        vm.expectEmit(true, false, false, false);
        emit ChangeOrderProposed(project.projectId);
        vm.prank(project.buyer);
        marketplace.challengeProject(
            project.projectId,
            changeOrderAdjustedProjectFee,
            changeOrderProviderStakeForfeit,
            changeOrderDetailsURI
        );

        assertEq(marketplace.changeOrderIds(), id + 1);
        assertEq(marketplace.activeChangeOrder(project.projectId), true);
        ChangeOrder memory order = marketplace.getActiveChangeOrder(project.projectId);
        assertEq(order.changeOrderId, marketplace.changeOrderIds());
        assertEq(order.projectId, project.projectId);
        assertEq(order.dateProposed, block.timestamp);
        assertEq(order.proposedBy, project.buyer);
        assertEq(order.adjustedProjectFee, changeOrderAdjustedProjectFee);
        assertEq(order.providerStakeForfeit, changeOrderProviderStakeForfeit);
        assertEq(order.active, true);
        assertEq(order.buyerApproval, true);
        assertEq(order.providerApproval, false);
        assertEq(order.detailsURI, changeOrderDetailsURI);
    }

    function test_createChangeOrder_revert() public {
        // adjusted fee > project fee
        Project memory project = marketplace.getProject(id_complete_MATIC);
        vm.expectRevert(Marketplace.Marketplace__AdjustedFeeExceedsProjectFee.selector);
        vm.prank(project.buyer);
        marketplace.challengeProject(
            project.projectId,
            project.projectFee + 1,
            changeOrderProviderStakeForfeit,
            changeOrderDetailsURI
        );
        // stake forfeit > stake
        vm.expectRevert(Marketplace.Marketplace__ForfeitExceedsProviderStake.selector);
        vm.prank(project.buyer);
        marketplace.challengeProject(
            project.projectId,
            changeOrderAdjustedProjectFee,
            project.providerStake + 1,
            changeOrderDetailsURI
        );
    }

    function test_approveChangeOrder() public {
        uint256[2] memory challengedProjects = [id_challenged_ERC20, id_challenged_MATIC];
        for(uint i; i < challengedProjects.length; ++i) {
            Project memory project = marketplace.getProject(challengedProjects[i]);
            ChangeOrder memory order = marketplace.getActiveChangeOrder(project.projectId);
            assertFalse(order.providerApproval);

            vm.expectEmit(true, true, true, false);
            emit ChangeOrderApproved(project.projectId, project.buyer, project.provider);
            vm.prank(project.provider);
            marketplace.approveChangeOrder(project.projectId);

            order = marketplace.getActiveChangeOrder(project.projectId);
            assertTrue(order.providerApproval);
            project = marketplace.getProject(project.projectId);
            assertEq(uint(project.status), uint(Status.Resolved_ChangeOrder));
        }
    }

    function test_approveChangeOrder_revert() public {
        // no active change order
        Project memory project = marketplace.getProject(id_active_ERC20);
        assertFalse(marketplace.activeChangeOrder(project.projectId));
        vm.expectRevert(Marketplace.Marketplace__NoActiveChangeOrder.selector);
        vm.prank(project.provider);
        marketplace.approveChangeOrder(project.projectId);
        // not buyer or provider 
        project = marketplace.getProject(id_challenged_ERC20);
        vm.expectRevert(Marketplace.Marketplace__OnlyBuyerOrProvider.selector);
        vm.prank(zorro);
        marketplace.approveChangeOrder(project.projectId);
        // already approved
        vm.expectRevert(Marketplace.Marketplace__AlreadyApprovedChangeOrder.selector);
        vm.prank(project.buyer);
        marketplace.approveChangeOrder(project.projectId);
    }

    function test_proposeSettlement() public {
        Project memory project = marketplace.getProject(id_challenged_MATIC);
        _disputeProject(project.projectId, changeOrderAdjustedProjectFee, changeOrderProviderStakeForfeit);
        assertFalse(marketplace.activeChangeOrder(project.projectId));
        uint256 numOrders = marketplace.getChangeOrders(project.projectId).length;

        vm.prank(project.provider);
        marketplace.proposeSettlement(
            project.projectId,
            settlementAdjustedProjectFee,
            settlementProviderStakeForfeit,
            "ipfs://settlementDetails"
        );

        // change order has been added
        assertTrue(marketplace.activeChangeOrder(project.projectId));
        assertEq(marketplace.getChangeOrders(project.projectId).length, numOrders + 1);
        ChangeOrder memory order = marketplace.getActiveChangeOrder(project.projectId);
        assertEq(order.adjustedProjectFee, settlementAdjustedProjectFee);
        assertEq(order.providerStakeForfeit, settlementProviderStakeForfeit);
        assertEq(order.proposedBy, project.provider);
        assertEq(order.dateProposed, block.timestamp);
        assertEq(order.detailsURI, "ipfs://settlementDetails");
    }

    // function test_proposeSettlement_revert() public {
    //     // case not in discovery
    // }

}
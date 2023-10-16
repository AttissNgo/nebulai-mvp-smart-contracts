// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/Interfaces/IEscrow.sol";
import "forge-std/console.sol";

contract MarketplaceArbitrationTest is Test, TestSetup {

    event SettlementProposed(uint256 indexed projectId, uint256 indexed petitionId);

    function setUp() public {
        _setUp();
        _whitelistUsers();
        _registerJurors();
        _initializeTestProjects();
        _initializeArbitrationProjects();
    }

    // function test_proposeSettlement() public {
    //     Project memory project = marketplace.getProject(id_arbitration_discovery_MATIC);
    //     Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(project.projectId));
    //     assertEq(uint(petition.phase), uint(Phase.Discovery));
    //     assertEq(marketplace.activeChangeOrder(project.projectId), false);

    //     vm.expectEmit(true, true, false, false);
    //     emit SettlementProposed(project.projectId, petition.petitionId);
    //     vm.prank(petition.defendant);
    //     marketplace.proposeSettlement(
    //         project.projectId,
    //         changeOrderAdjustedProjectFee + 100 ether,
    //         0,
    //         "ipfs://settlementDetails/"
    //     );

    //     assertEq(marketplace.activeChangeOrder(project.projectId), true);

    // } // don't need --- tested in Marketplace_ChangeOrderTest
    
}
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
}
        

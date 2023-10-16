// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/Interfaces/IEscrow.sol";
import "forge-std/console.sol";

contract CourtJuryTest is Test, TestSetup {

    event JuryDrawn(uint256 indexed petitionId, bool isRedraw);

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
}
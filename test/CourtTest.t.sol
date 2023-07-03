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


    event ArbitrationFeePaid(uint256 indexed petitionId, address indexed user);
    event JurySelectionInitiated(uint256 indexed petitionId, uint256 requestId);
    event JuryDrawn(uint256 indexed petitionId, bool isRedraw);


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
        // vm.pauseGasMetering();
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
        // vm.resumeGasMetering();
    }

    // function _createProjectERC20() public returns (uint256) {
    //     uint256 txFee = marketplace.calculateNebulaiTxFee(projectFee);
    //     vm.startPrank(buyer);
    //     usdt.approve(address(marketplace), txFee + projectFee);
    //     uint256 projectId = marketplace.createProject{value: 0}(
    //         provider,
    //         address(usdt),
    //         projectFee,
    //         providerStake,
    //         dueDate,
    //         reviewPeriodLength,
    //         detailsURI
    //     );
    //     vm.stopPrank();
    //     return projectId;
    // }

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
        // emit log_address(jury.confirmedJurors[0]);
        emit log_address(juror_one);
        // emit log_uint(uint(juryPool.getJurorStatus(juror_one)));
        vm.prank(juror_one);
        court.acceptCase{value: court.jurorFlatFee()}(p.petitionId);
        jury = court.getJury(p.petitionId);
        emit log_address(jury.confirmedJurors[0]);
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
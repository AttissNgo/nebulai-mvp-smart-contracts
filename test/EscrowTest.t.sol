// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";
// import "./MarketplaceTest.t.sol";
import "../src/Interfaces/IEscrow.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/Escrow.sol";
// import "./Marketplace_ProjectTest.t.sol";
import "forge-std/console.sol";


contract EscrowTest is Test, TestSetup {

    event EscrowReleased(address recipient, uint256 amountReleased, uint256 commissionFeePaid);

    function setUp() public {
        _setUp();
        _whitelistUsers();
        _registerJurors();
        _initializeTestProjects();
        _initializeArbitrationProjects();
    }

    //////////////////////
    ///   DEPLOYMENT   ///
    //////////////////////

    function test_escrow_deployement() public {
        uint256[2] memory createdProjects = [id_created_MATIC, id_created_ERC20];
        for(uint i = 0; i < createdProjects.length; ++i) {
            Project memory project = marketplace.getProject(createdProjects[i]);
            IEscrow escrow = IEscrow(project.escrow);
            // variables initialized correctly
            assertEq(address(marketplace), escrow.MARKETPLACE());
            assertEq(project.projectId, escrow.PROJECT_ID());
            assertEq(project.buyer, escrow.BUYER());
            assertEq(project.provider, escrow.PROVIDER());
            assertEq(project.paymentToken, escrow.PAYMENT_TOKEN());
            assertEq(project.projectFee, escrow.PROJECT_FEE());
            assertEq(project.providerStake, escrow.PROVIDER_STAKE());
            assertEq(address(court), escrow.COURT());
            // correct balance
            assertEq(escrow.providerHasStaked(), false);
            assertEq(_getBalance(address(escrow), project.paymentToken), escrow.PROJECT_FEE());
        }
    }

    function test_provider_stake_recorded() public {
        Project memory project = marketplace.getProject(id_created_MATIC);
        IEscrow escrow = IEscrow(project.escrow);
        assertEq(escrow.providerHasStaked(), false);
        _activatedProject(project.projectId);
        assertEq(escrow.providerHasStaked(), true);
    }

    ////////////////////
    ///   WITHDRAW   ///
    ////////////////////

    function test_isReleasable() public {
        // blocks projects with wrong status
        Project memory project = marketplace.getProject(id_created_ERC20);
        assertFalse(IEscrow(project.escrow).isReleasable());
        project = marketplace.getProject(id_active_ERC20);
        assertFalse(IEscrow(project.escrow).isReleasable());
        project = marketplace.getProject(id_challenged_MATIC);
        assertFalse(IEscrow(project.escrow).isReleasable());
    }

    function test_withdraw_revert() public {
        // not buyer or provider
        Project memory project = marketplace.getProject(id_approved_MATIC);
        vm.expectRevert(Escrow.Escrow__OnlyBuyerOrProvider.selector);
        vm.prank(zorro);
        IEscrow(project.escrow).withdraw();
        // not releasable - wrong status
        project = marketplace.getProject(id_active_MATIC);
        vm.expectRevert(Escrow.Escrow__NotReleasable.selector);
        vm.prank(project.provider);
        IEscrow(project.escrow).withdraw();
        // already withdrawn
        project = marketplace.getProject(id_approved_MATIC);
        vm.prank(project.provider);
        IEscrow(project.escrow).withdraw();
        assertTrue(IEscrow(project.escrow).hasWithdrawn(project.provider));
        vm.expectRevert(Escrow.Escrow__UserHasAlreadyWithdrawn.selector);
        vm.prank(project.provider);
        IEscrow(project.escrow).withdraw();
    }

    function test_withdraw_approved() public {
        uint256[2] memory approvedProjects = [id_approved_ERC20, id_approved_MATIC];
        for(uint i; i < approvedProjects.length; ++i) {
            Project memory project = marketplace.getProject(approvedProjects[i]);
            IEscrow escrow = IEscrow(project.escrow);
            (,, uint providerBefore, uint marketplaceBefore) = _snapshotBeforeBalances(project.projectId);

            // provider withdraw
            (uint256 amountDue, uint256 commission) = escrow.amountDue(project.provider);
            assertEq(commission, project.projectFee/100);
            assertEq(amountDue, project.projectFee + project.providerStake - commission);
            vm.prank(project.provider);
            vm.expectEmit(false, false, false, true);
            emit EscrowReleased(project.provider, amountDue, commission);
            escrow.withdraw();
            assertEq(_getBalance(project.provider, project.paymentToken), providerBefore + amountDue);
            assertEq(_getBalance(address(marketplace), project.paymentToken), marketplaceBefore + commission);
            assertEq(_getBalance(address(escrow), project.paymentToken), 0);

            // buyer withdraw - should revert due to zero amount
            vm.expectRevert(Escrow.Escrow__NoPaymentDue.selector);
            vm.prank(project.buyer);
            escrow.withdraw();
        }
    }

    function test_withdraw_changeOrder() public {
        uint256[2] memory approvedOrderProjects = [id_approved_change_order_ERC20, id_approved_change_order_MATIC];
        for(uint i; i < approvedOrderProjects.length; ++i) {
            Project memory project = marketplace.getProject(approvedOrderProjects[i]);
            IEscrow escrow = IEscrow(project.escrow);
            ChangeOrder memory order = marketplace.getActiveChangeOrder(project.projectId);
            (uint escrowBefore, uint buyerBefore, uint providerBefore, uint marketplaceBefore) = _snapshotBeforeBalances(project.projectId);
            
            // provider withdraw
            (uint256 amountDue, uint256 commission) = escrow.amountDue(project.provider);
            assertEq(commission, order.adjustedProjectFee/100);
            assertEq(amountDue, order.adjustedProjectFee + project.providerStake - order.providerStakeForfeit - commission);
            vm.expectEmit(false, false, false, true);
            emit EscrowReleased(project.provider, amountDue, commission);
            vm.prank(project.provider);
            escrow.withdraw();
            assertEq(_getBalance(project.provider, project.paymentToken), providerBefore + amountDue);
            assertEq(_getBalance(address(marketplace), project.paymentToken), marketplaceBefore + commission);
            assertEq(_getBalance(address(escrow), project.paymentToken), escrowBefore - amountDue - commission);

            // buyer withdraw
            (amountDue,) = escrow.amountDue(project.buyer);
            assertEq(amountDue, project.projectFee - order.adjustedProjectFee + order.providerStakeForfeit);
            vm.expectEmit(false, false, false, true);
            emit EscrowReleased(project.buyer, amountDue, 0);
            vm.prank(project.buyer);
            escrow.withdraw();
            assertEq(_getBalance(project.buyer, project.paymentToken), buyerBefore + amountDue);
            assertEq(_getBalance(address(escrow), project.paymentToken), 0);
        }
    }

    function test_withdraw_deliquentPayment() public {
        uint256[2] memory delinquentProjects = [id_complete_ERC20, id_complete_MATIC];
        for(uint i; i < delinquentProjects.length; ++i) {
            Project memory project = marketplace.getProject(delinquentProjects[i]);
            vm.warp(block.timestamp + project.reviewPeriodLength + 1);
            vm.prank(project.provider);
            marketplace.delinquentPayment(project.projectId);
            IEscrow escrow = IEscrow(project.escrow);
            (uint escrowBefore,, uint providerBefore, uint marketplaceBefore) = _snapshotBeforeBalances(project.projectId);
            
            // provider withdraw
            (uint256 amountDue, uint256 commission) = escrow.amountDue(project.provider);
            assertEq(commission, project.projectFee/100);
            assertEq(amountDue, project.projectFee + project.providerStake - commission);
            vm.prank(project.provider);
            escrow.withdraw();
            assertEq(_getBalance(project.provider, project.paymentToken), providerBefore + amountDue);
            assertEq(_getBalance(address(marketplace), project.paymentToken), marketplaceBefore + commission);
            assertEq(_getBalance(address(escrow), project.paymentToken), escrowBefore - amountDue - commission);

            // buyer withdraw - should revert due to zero amount
            vm.expectRevert(Escrow.Escrow__NoPaymentDue.selector);
            vm.prank(project.buyer);
            escrow.withdraw();
        }
    }

    function test_withdraw_full_refund_to_buyer_plus_forfeit() public {
        Project memory project = marketplace.getProject(id_complete_ERC20);
        IEscrow escrow = IEscrow(project.escrow);
        vm.prank(buyer);
        marketplace.challengeProject(
            project.projectId,
            0, // full refund
            project.providerStake, // also captures provider stake
            changeOrderDetailsURI
        );
        vm.prank(project.provider);
        marketplace.approveChangeOrder(project.projectId);
        (, uint buyerBefore,,) = _snapshotBeforeBalances(project.projectId);

        // provider has nothing to withdraw
        vm.expectRevert(Escrow.Escrow__NoPaymentDue.selector);
        vm.prank(project.provider);
        escrow.withdraw();

        // buyer withdraw
        (uint256 amountDue,) = escrow.amountDue(project.buyer);
        assertEq(amountDue, project.projectFee + project.providerStake);
        vm.expectEmit(false, false, false, true);
        emit EscrowReleased(project.buyer, amountDue, 0);
        vm.prank(project.buyer);
        escrow.withdraw();
        assertEq(_getBalance(project.buyer, project.paymentToken), buyerBefore + amountDue);
        assertEq(_getBalance(address(escrow), project.paymentToken), 0);
    }

    function test_withdraw_court_order_granted() public {
        _discoveryToResolved(id_arbitration_discovery_ERC20, true);
        _discoveryToResolved(id_arbitration_discovery_MATIC, true);
        uint256[2] memory grantedProjects = [id_arbitration_discovery_ERC20, id_arbitration_discovery_MATIC];
        for(uint i; i < grantedProjects.length; ++i) {
            Project memory project = marketplace.getProject(grantedProjects[i]);
            Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(project.projectId));
            IEscrow escrow = IEscrow(project.escrow);
            (uint escrowBefore, uint buyerBefore, uint providerBefore, uint marketplaceBefore) = _snapshotBeforeBalances(project.projectId);
            assertEq(petition.plaintiff, project.buyer); // buyer is winner
            vm.prank(project.provider);
            marketplace.waiveAppeal(project.projectId);

            // buyer withdraw
            (uint256 amountDue, uint256 commission) = escrow.amountDue(project.buyer);
            assertEq(amountDue, project.projectFee - petition.adjustedProjectFee + petition.providerStakeForfeit);
            vm.prank(project.buyer);
            escrow.withdraw();
            assertEq(_getBalance(project.buyer, project.paymentToken), buyerBefore + amountDue);
            assertEq(_getBalance(address(escrow), project.paymentToken), escrowBefore - amountDue);

            // provider withdraw
            (amountDue, commission) = escrow.amountDue(project.provider);
            assertEq(commission, petition.adjustedProjectFee/100);
            assertEq(amountDue, petition.adjustedProjectFee - commission + project.providerStake - petition.providerStakeForfeit);
            vm.prank(project.provider);
            escrow.withdraw();
            assertEq(_getBalance(project.provider, project.paymentToken), providerBefore + amountDue);
            assertEq(_getBalance(address(marketplace), project.paymentToken), marketplaceBefore + commission);
            assertEq(_getBalance(address(escrow), project.paymentToken), 0);
        }
    }

    function test_withdraw_court_order_denied() public {
        _discoveryToResolved(id_arbitration_discovery_ERC20, false);
        _discoveryToResolved(id_arbitration_discovery_MATIC, false);
        uint256[2] memory grantedProjects = [id_arbitration_discovery_ERC20, id_arbitration_discovery_MATIC];
        for(uint i; i < grantedProjects.length; ++i) {
            Project memory project = marketplace.getProject(grantedProjects[i]);
            Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(project.projectId));
            IEscrow escrow = IEscrow(project.escrow);
            (uint escrowBefore, uint buyerBefore, uint providerBefore, uint marketplaceBefore) = _snapshotBeforeBalances(project.projectId);
            assertEq(petition.plaintiff, project.buyer); // buyer is loser
            vm.prank(project.buyer);
            marketplace.waiveAppeal(project.projectId);

            // buyer withdraw - should revert due to zero amount
            vm.expectRevert(Escrow.Escrow__NoPaymentDue.selector);
            vm.prank(project.buyer);
            escrow.withdraw();

            // provider withdraw
            (uint256 amountDue, uint256 commission) = escrow.amountDue(project.provider);
            assertEq(commission, project.projectFee/100);
            assertEq(amountDue, project.projectFee - commission + project.providerStake);
            vm.prank(project.provider);
            escrow.withdraw();
            assertEq(_getBalance(project.provider, project.paymentToken), providerBefore + amountDue);
            assertEq(_getBalance(address(marketplace), project.paymentToken), marketplaceBefore + commission);
            assertEq(_getBalance(address(escrow), project.paymentToken), 0);
        }
    }

    function test_withdraw_arbitration_dismissed() public {
        _disputeProject(id_challenged_ERC20, changeOrderAdjustedProjectFee, changeOrderProviderStakeForfeit);
        _disputeProject(id_challenged_MATIC, changeOrderAdjustedProjectFee, changeOrderProviderStakeForfeit);
        uint256[2] memory dismissedProjects = [id_challenged_ERC20, id_challenged_MATIC];
        for(uint i; i < dismissedProjects.length; ++i) {
            Project memory project = marketplace.getProject(dismissedProjects[i]);
            Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(project.projectId));
            vm.warp(block.timestamp + court.DISCOVERY_PERIOD() + 1);
            court.dismissUnpaidCase(petition.petitionId);
            vm.prank(project.provider);
            marketplace.resolveDismissedCase(project.projectId);
            IEscrow escrow = IEscrow(project.escrow);
            (uint escrowBefore, uint buyerBefore, uint providerBefore, uint marketplaceBefore) = _snapshotBeforeBalances(project.projectId);

            // buyer withdraw - should revert due to zero amount
            vm.expectRevert(Escrow.Escrow__NoPaymentDue.selector);
            vm.prank(project.buyer);
            escrow.withdraw();

            // provider withdraw
            (uint256 amountDue, uint256 commission) = escrow.amountDue(project.provider);
            assertEq(commission, project.projectFee/100);
            assertEq(amountDue, project.projectFee - commission + project.providerStake);
            vm.prank(project.provider);
            escrow.withdraw();
            assertEq(_getBalance(project.provider, project.paymentToken), providerBefore + amountDue);
            assertEq(_getBalance(address(marketplace), project.paymentToken), marketplaceBefore + commission);
            assertEq(_getBalance(address(escrow), project.paymentToken), 0);
        }
    }

    ////////////////
    ///   UTIL   ///
    ////////////////

    function _snapshotBeforeBalances(uint256 _projectId) public view returns (uint256, uint256, uint256, uint256) {
        Project memory p = marketplace.getProject(_projectId);
        uint256 escrowBal = _getBalance(p.escrow, p.paymentToken);
        uint256 buyerBal = _getBalance(p.buyer, p.paymentToken);
        uint256 providerBal = _getBalance(p.provider, p.paymentToken);
        uint256 marketplaceBal = _getBalance(IEscrow(p.escrow).MARKETPLACE(), p.paymentToken);
        return (escrowBal, buyerBal, providerBal, marketplaceBal);
    }
}

// contract EscrowTest is Test, TestSetup {

//     // test project params
//     address buyer = alice;
//     address provider = bob;
//     uint256 projectFee = 1000 ether;
//     uint256 providerStake = 50 ether;
//     uint256 dueDate;
//     uint256 reviewPeriodLength = 3 days;
//     string detailsURI = "ipfs://someURI/";
//     uint256 testProjectId_MATIC;
//     uint256 testProjectId_ERC20;

//     // balance checks
//     uint256 buyerBalBefore;
//     uint256 providerBalBefore;
//     uint256 escrowBalBefore;
//     uint256 buyerBalCurrent;
//     uint256 providerBalCurrent;
//     uint256 escrowBalCurrent;

//     // test change order
//     uint256 changeOrderAdjustedProjectFee = 750 ether;
//     uint256 changeOrderProviderStakeForfeit = 10 ether;
//     string changeOrderDetailsURI = "ipfs://changeOrderUri";

//     // test arbitration
//     uint256 petitionId;
//     uint256 arbitrationAdjustedProjectFee = 600 ether;
//     uint256 arbitrationProviderStakeForfeit = 20 ether;
//     string[] evidence1 = ["someEvidenceURI", "someOtherEvidenceURI"];
//     string[] evidence2 = ["someEvidenceURI2", "someOtherEvidenceURI2"];

//     function setUp() public {
//         _setUp();
//         _whitelistUsers();
//         _registerJurors();
//         dueDate = block.timestamp + 30 days;
//         testProjectId_MATIC = _createProject_MATIC();
//         testProjectId_ERC20 = _createProjectERC20();
//     }

//     function _createProject_MATIC() public returns (uint256) {
//         uint256 txFee = marketplace.calculateNebulaiTxFee(projectFee);
//         vm.prank(buyer);
//         uint256 projectId = marketplace.createProject{value: txFee + projectFee}(
//             provider,
//             address(0), // MATIC
//             projectFee,
//             providerStake,
//             dueDate,
//             reviewPeriodLength,
//             detailsURI
//         );
//         return projectId;
//     }

//     function _createProjectERC20() public returns (uint256) {
//         uint256 txFee = marketplace.calculateNebulaiTxFee(projectFee);
//         vm.startPrank(buyer);
//         usdt.approve(address(marketplace), txFee + projectFee);
//         uint256 projectId = marketplace.createProject{value: 0}(
//             provider,
//             address(usdt),
//             projectFee,
//             providerStake,
//             dueDate,
//             reviewPeriodLength,
//             detailsURI
//         );
//         vm.stopPrank();
//         return projectId;
//     }

//     function _completedProject(uint256 _projectId) public {
//          Marketplace.Project memory p = marketplace.getProject(_projectId);
//         if(p.paymentToken != address(0)) {
//             vm.prank(p.provider);
//             usdt.approve(address(marketplace), p.providerStake);
//             vm.prank(p.provider);
//             marketplace.activateProject(p.projectId);
//         } else {
//             vm.prank(provider);
//             marketplace.activateProject{value: p.providerStake}(p.projectId);
//         }
//         vm.prank(provider);
//         marketplace.completeProject(p.projectId);
//     }

//     function _approvedProject(uint256 _projectId) public {
//         _completedProject(_projectId);
//         Marketplace.Project memory project = marketplace.getProject(_projectId);
//         vm.prank(project.buyer);
//         marketplace.approveProject(project.projectId);
//     }

//     function _projectWithChangeOrder(uint256 _projectId) public {
//         _completedProject(_projectId);
//         Marketplace.Project memory project = marketplace.getProject(_projectId);
//         vm.prank(project.buyer);
//         marketplace.challengeProject(
//             project.projectId,
//             changeOrderAdjustedProjectFee,
//             changeOrderProviderStakeForfeit,
//             changeOrderDetailsURI
//         );
//     }

//     function _projectWithArbitration(uint256 _projectId) public {
//         _projectWithChangeOrder(_projectId);
//         Marketplace.Project memory project = marketplace.getProject(_projectId);
//             // warp past change order period
//         vm.warp(block.timestamp + marketplace.CHANGE_ORDER_PERIOD() + 1);
//         vm.prank(project.buyer);
//         petitionId = marketplace.disputeProject(
//             project.projectId,
//             arbitrationAdjustedProjectFee,
//             arbitrationProviderStakeForfeit
//         );
//     }

//     function _confirmedJury() public {
//         Court.Petition memory petition = court.getPetition(petitionId);
//             // plaintiff pays
//         vm.prank(petition.plaintiff);
//         court.payArbitrationFee{value: petition.arbitrationFee}(petitionId, evidence1);
//             // defendant pays and jury selection is initiated
//         vm.recordLogs();
//         vm.prank(petition.defendant);
//         court.payArbitrationFee{value: petition.arbitrationFee}(petitionId, evidence2);
//         Vm.Log[] memory entries = vm.getRecordedLogs();
//         uint256 requestId = uint(bytes32(entries[2].data));
//         vrf.fulfillRandomWords(requestId, address(court));
//         Court.Jury memory jury = court.getJury(petition.petitionId);
//         uint256 jurorStake = court.jurorFlatFee();
//         for(uint i; i < court.jurorsNeeded(petition.petitionId); ++i) {
//             vm.prank(jury.drawnJurors[i]);
//             court.acceptCase{value: jurorStake}(petition.petitionId);
//         }
//     }

//     function _arbitrationPetitionGranted(uint256 _projectId) public {
//         _projectWithArbitration(_projectId);
//         _confirmedJury();
//             // jurors vote
//         Court.Petition memory petition = court.getPetition(petitionId);
//         Court.Jury memory jury = court.getJury(petition.petitionId);
//         bytes32 commit = keccak256(abi.encodePacked(true, "someSalt"));
//         vm.prank(jury.confirmedJurors[0]);
//         court.commitVote(petition.petitionId, commit);
//         commit = keccak256(abi.encodePacked(true, "someSalt"));
//         vm.prank(jury.confirmedJurors[1]);
//         court.commitVote(petition.petitionId, commit);
//         commit = keccak256(abi.encodePacked(true, "someSalt"));
//         vm.prank(jury.confirmedJurors[2]);
//         court.commitVote(petition.petitionId, commit);
//             // jurors reveal
//         vm.prank(jury.confirmedJurors[0]);
//         court.revealVote(petition.petitionId, true, "someSalt");
//         vm.prank(jury.confirmedJurors[1]);
//         court.revealVote(petition.petitionId, true, "someSalt");
//         vm.prank(jury.confirmedJurors[2]);
//         court.revealVote(petition.petitionId, true, "someSalt");
//             // defendant (provider) waives appeal
//         vm.prank(petition.defendant);
//         marketplace.waiveAppeal(_projectId);
//     }

//     function _arbitrationPetitionNotGranted(uint256 _projectId) public {
//         _projectWithArbitration(_projectId);
//         _confirmedJury();
//             // jurors vote
//         Court.Petition memory petition = court.getPetition(petitionId);
//         Court.Jury memory jury = court.getJury(petition.petitionId);
//         bytes32 commit = keccak256(abi.encodePacked(false, "someSalt"));
//         vm.prank(jury.confirmedJurors[0]);
//         court.commitVote(petition.petitionId, commit);
//         commit = keccak256(abi.encodePacked(false, "someSalt"));
//         vm.prank(jury.confirmedJurors[1]);
//         court.commitVote(petition.petitionId, commit);
//         commit = keccak256(abi.encodePacked(true, "someSalt"));
//         vm.prank(jury.confirmedJurors[2]);
//         court.commitVote(petition.petitionId, commit);
//             // jurors reveal
//         vm.prank(jury.confirmedJurors[0]);
//         court.revealVote(petition.petitionId, false, "someSalt");
//         vm.prank(jury.confirmedJurors[1]);
//         court.revealVote(petition.petitionId, false, "someSalt");
//         vm.prank(jury.confirmedJurors[2]);
//         court.revealVote(petition.petitionId, true, "someSalt");
//             // appeal period passes and defendant resolves 
//         vm.warp(block.timestamp + marketplace.APPEAL_PERIOD() + 1);
//         vm.prank(petition.defendant);
//         marketplace.resolveByCourtOrder(_projectId);
//     }

//     function _setBeforeBalances(
//         address _paymentToken,
//         address _buyer, 
//         address _provider, 
//         address _escrow
//     ) 
//         public 
//     {
//         if(_paymentToken == address(0)) {
//             buyerBalBefore = _buyer.balance;
//             providerBalBefore = _provider.balance;
//             escrowBalBefore = _escrow.balance;
//         } else {
//             buyerBalBefore = IERC20(_paymentToken).balanceOf(_buyer);
//             providerBalBefore = IERC20(_paymentToken).balanceOf(_provider);
//             escrowBalBefore = IERC20(_paymentToken).balanceOf(_escrow);
//         }
//     }

//     function _setCurrentBalances(
//         address _paymentToken,
//         address _buyer, 
//         address _provider, 
//         address _escrow
//     ) 
//         public 
//     {
//         if(_paymentToken == address(0)) {
//             buyerBalCurrent = _buyer.balance;
//             providerBalCurrent = _provider.balance;
//             escrowBalCurrent = _escrow.balance;
//         } else {
//             buyerBalCurrent = IERC20(_paymentToken).balanceOf(_buyer);
//             providerBalCurrent = IERC20(_paymentToken).balanceOf(_provider);
//             escrowBalCurrent = IERC20(_paymentToken).balanceOf(_escrow);
//         }
//     }

//     function test_withdraw_cancelled_project() public {
//         vm.pauseGasMetering();
//         Marketplace.Project memory project = marketplace.getProject(testProjectId_ERC20);
//         IEscrow escrow = IEscrow(project.escrow);
//         vm.prank(project.buyer);
//         marketplace.cancelProject(project.projectId);
//         _setBeforeBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
//         vm.resumeGasMetering();
//         // buyer can withdraw project fee
//         vm.prank(project.buyer);
//         escrow.withdraw();
//         _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
//         assertEq(buyerBalCurrent, buyerBalBefore + projectFee);
//         assertEq(escrowBalCurrent, escrowBalBefore - projectFee);
//         assertEq(escrow.hasWithdrawn(project.buyer), true);
//         // provider is not owed
//         vm.expectRevert(Escrow.Escrow__NoPaymentDue.selector);
//         vm.prank(project.provider);
//         escrow.withdraw();
//     }

//     function test_withdraw_approved_project() public {
//         vm.pauseGasMetering();
//         _approvedProject(testProjectId_MATIC);
//         Marketplace.Project memory project = marketplace.getProject(testProjectId_MATIC);
//         IEscrow escrow = IEscrow(project.escrow);
//         _setBeforeBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
//         vm.resumeGasMetering();
//         // provider can withdraw project fee (- commission) and provider stake
//         uint256 commissionFee = project.projectFee/100;
//         uint256 marketplaceBalBefore = address(marketplace).balance;
//         uint256 commissionsMappingBefore = marketplace.getCommissionFees(address(0));
//         vm.prank(project.provider);
//         escrow.withdraw();
//         _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
//         assertEq(providerBalCurrent, providerBalBefore + project.projectFee + project.providerStake - commissionFee);
//         assertEq(escrow.hasWithdrawn(project.provider), true);
//         // commission has gone to marketplace
//         assertEq(address(marketplace).balance, marketplaceBalBefore + commissionFee);
//         assertEq(marketplace.getCommissionFees(address(0)), commissionsMappingBefore + commissionFee);
//         // buyer is not owed
//         vm.expectRevert(Escrow.Escrow__NoPaymentDue.selector);
//         vm.prank(project.buyer);
//         escrow.withdraw();
//     }

//     function test_withdraw_change_order() public {
//         vm.pauseGasMetering();
//         _projectWithChangeOrder(testProjectId_ERC20);
//         Marketplace.Project memory project = marketplace.getProject(testProjectId_ERC20);
//         IEscrow escrow = IEscrow(project.escrow);
//         vm.prank(project.provider);
//         marketplace.approveChangeOrder(project.projectId);
//         _setBeforeBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
//         vm.resumeGasMetering();
//         // provider can withdraw adjusted project fee + stake (- forfeit) - commission
//         uint256 commissionFee = changeOrderAdjustedProjectFee/100;
//         vm.prank(project.provider);
//         escrow.withdraw();
//         _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
//         assertEq(providerBalCurrent, 
//             providerBalBefore + 
//             changeOrderAdjustedProjectFee + 
//             project.providerStake - 
//             changeOrderProviderStakeForfeit - 
//             commissionFee
//         );
//         // buyer can withdraw remaining project fee + stake forfeit
//         vm.prank(project.buyer);
//         escrow.withdraw();
//         _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
//         assertEq(buyerBalCurrent, 
//             buyerBalBefore + 
//             project.projectFee - 
//             changeOrderAdjustedProjectFee + 
//             changeOrderProviderStakeForfeit
//         );
//     }

//     function test_withdraw_court_order_granted() public {
//         vm.pauseGasMetering();
//         _arbitrationPetitionGranted(testProjectId_MATIC);
//         Marketplace.Project memory project = marketplace.getProject(testProjectId_MATIC);
//         IEscrow escrow = IEscrow(project.escrow);
//         _setBeforeBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
//         vm.resumeGasMetering();
//         // buyer can withdraw remaining project fee + stake forfeit
//         vm.prank(project.buyer);
//         escrow.withdraw();
//         _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
//         assertEq(buyerBalCurrent, 
//             buyerBalBefore + 
//             project.projectFee - 
//             arbitrationAdjustedProjectFee + 
//             arbitrationProviderStakeForfeit
//         );
//         // provider can withdraw adjusted project fee + stake (- forfeit) - commission
//         uint256 commissionFee = arbitrationAdjustedProjectFee/100;
//         vm.prank(project.provider);
//         escrow.withdraw();
//         _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
//         assertEq(providerBalCurrent, 
//             providerBalBefore + 
//             arbitrationAdjustedProjectFee + 
//             project.providerStake - 
//             arbitrationProviderStakeForfeit - 
//             commissionFee
//         );
//     }

//     function test_withdraw_court_order_not_granted() public {
//         vm.pauseGasMetering();
//         _arbitrationPetitionNotGranted(testProjectId_ERC20);
//         Marketplace.Project memory project = marketplace.getProject(testProjectId_ERC20);
//         IEscrow escrow = IEscrow(project.escrow);
//         _setBeforeBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
//         vm.resumeGasMetering();
//         // provider (defendant - won case) can withdraw original amount (project fee + stake - commission)
//         uint256 commissionFee = project.projectFee/100;
//         vm.prank(project.provider);
//         escrow.withdraw();
//         _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
//         assertEq(providerBalCurrent, providerBalBefore + project.projectFee + project.providerStake - commissionFee);
//         // nothing owed to buyer
//         vm.expectRevert(Escrow.Escrow__NoPaymentDue.selector);
//         vm.prank(project.buyer);
//         escrow.withdraw();
//     }

//     function test_withdraw_dismissed_arbitration_case() public {
//         vm.pauseGasMetering();
//         _projectWithArbitration(testProjectId_MATIC);
//         Marketplace.Project memory project = marketplace.getProject(testProjectId_MATIC);
//         IEscrow escrow = IEscrow(project.escrow);
//             // discovery period passes no one pays, case is dismissed 
//         vm.warp(block.timestamp + court.DISCOVERY_PERIOD() + 1);
//         court.dismissUnpaidCase(marketplace.getArbitrationPetitionId(project.projectId));
//         vm.prank(project.buyer);
//         marketplace.resolveDismissedCase(project.projectId);
//         _setBeforeBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
//         vm.resumeGasMetering();
//         // provider can withdraw project fee + stake - commission
//         uint256 commissionFee = project.projectFee/100;
//         vm.prank(project.provider);
//         escrow.withdraw();
//         _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
//         assertEq(providerBalCurrent, providerBalBefore + project.projectFee + project.providerStake - commissionFee);
//         // nothing owed to buyer
//         vm.expectRevert(Escrow.Escrow__NoPaymentDue.selector);
//         vm.prank(project.buyer);
//         escrow.withdraw();
//     }

//     function test_withdraw_delinquent_payment() public {
//         vm.pauseGasMetering();
//         _completedProject(testProjectId_ERC20);
//         Marketplace.Project memory project = marketplace.getProject(testProjectId_ERC20);
//         IEscrow escrow = IEscrow(project.escrow);
//             // review period passes, buyer does not approve, provider marks payment delinquent
//         vm.warp(block.timestamp + project.reviewPeriodLength + 1);
//         vm.prank(project.provider);
//         marketplace.delinquentPayment(project.projectId);
//         _setBeforeBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
//         vm.resumeGasMetering();
//         // provider can withdraw project fee + stake - commission
//         uint256 commissionFee = project.projectFee/100;
//         vm.prank(project.provider);
//         escrow.withdraw();
//         _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
//         assertEq(providerBalCurrent, providerBalBefore + project.projectFee + project.providerStake - commissionFee);
//         // nothing owed to buyer
//         vm.expectRevert(Escrow.Escrow__NoPaymentDue.selector);
//         vm.prank(project.buyer);
//         escrow.withdraw();
//     }

//     function test_arbitration_with_settlement() public {
//         vm.pauseGasMetering();
//         _projectWithArbitration(testProjectId_MATIC);
//         Marketplace.Project memory project = marketplace.getProject(testProjectId_MATIC);
//         IEscrow escrow = IEscrow(project.escrow);
//             // settlement proposed and approved
//         vm.prank(project.provider);
//         marketplace.proposeSettlement(
//             project.projectId,
//             changeOrderAdjustedProjectFee,
//             changeOrderProviderStakeForfeit,
//             changeOrderDetailsURI
//         );
//         vm.prank(project.buyer);
//         marketplace.approveChangeOrder(project.projectId);
//         Court.Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(project.projectId));
//         assertEq(uint(petition.phase), uint(Phase.SettledExternally));
//         _setBeforeBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
//         vm.resumeGasMetering();
//          // provider can withdraw adjusted project fee + stake (- forfeit) - commission
//         uint256 commissionFee = changeOrderAdjustedProjectFee/100;
//         vm.prank(project.provider);
//         escrow.withdraw();
//         _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
//         assertEq(providerBalCurrent, 
//             providerBalBefore + 
//             changeOrderAdjustedProjectFee + 
//             project.providerStake - 
//             changeOrderProviderStakeForfeit - 
//             commissionFee
//         );
//         // buyer can withdraw remaining project fee + stake forfeit
//         vm.prank(project.buyer);
//         escrow.withdraw();
//         _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
//         assertEq(buyerBalCurrent, 
//             buyerBalBefore + 
//             project.projectFee - 
//             changeOrderAdjustedProjectFee + 
//             changeOrderProviderStakeForfeit
//         );
//     }

//     function test_withdraw_revert() public {
//         vm.pauseGasMetering();
//         _completedProject(testProjectId_ERC20);
//         Marketplace.Project memory project = marketplace.getProject(testProjectId_ERC20);
//         IEscrow escrow = IEscrow(project.escrow);
//         vm.resumeGasMetering();
//         // not releasable
//         vm.expectRevert(Escrow.Escrow__NotReleasable.selector);
//         vm.prank(project.provider);
//         escrow.withdraw();
//         // double withdraw
//             // buyer approves, provider withdraws 
//         vm.prank(project.buyer);
//         marketplace.approveProject(project.projectId);
//         vm.prank(project.provider);
//         escrow.withdraw();
//         vm.expectRevert(Escrow.Escrow__UserHasAlreadyWithdrawn.selector);
//         vm.prank(project.provider);
//         escrow.withdraw();
//     }
    

// }
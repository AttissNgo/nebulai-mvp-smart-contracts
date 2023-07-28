// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";
import "./MarketplaceTest.t.sol";
import "../src/Interfaces/IEscrow.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/Escrow.sol";

contract EscrowTest is Test, TestSetup {

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

    // balance checks
    uint256 buyerBalBefore;
    uint256 providerBalBefore;
    uint256 escrowBalBefore;
    uint256 buyerBalCurrent;
    uint256 providerBalCurrent;
    uint256 escrowBalCurrent;

    // test change order
    uint256 changeOrderAdjustedProjectFee = 750 ether;
    uint256 changeOrderProviderStakeForfeit = 10 ether;
    string changeOrderDetailsURI = "ipfs://changeOrderUri";

    // test arbitration
    uint256 petitionId;
    uint256 arbitrationAdjustedProjectFee = 600 ether;
    uint256 arbitrationProviderStakeForfeit = 20 ether;
    string[] evidence1 = ["someEvidenceURI", "someOtherEvidenceURI"];
    string[] evidence2 = ["someEvidenceURI2", "someOtherEvidenceURI2"];

    function setUp() public {
        _setUp();
        _whitelistUsers();
        _registerJurors();
        dueDate = block.timestamp + 30 days;
        testProjectId_MATIC = _createProject_MATIC();
        testProjectId_ERC20 = _createProjectERC20();
    }

    function _createProject_MATIC() public returns (uint256) {
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

    function _completedProject(uint256 _projectId) public {
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
    }

    function _approvedProject(uint256 _projectId) public {
        _completedProject(_projectId);
        Marketplace.Project memory project = marketplace.getProject(_projectId);
        vm.prank(project.buyer);
        marketplace.approveProject(project.projectId);
    }

    function _projectWithChangeOrder(uint256 _projectId) public {
        _completedProject(_projectId);
        Marketplace.Project memory project = marketplace.getProject(_projectId);
        vm.prank(project.buyer);
        marketplace.challengeProject(
            project.projectId,
            changeOrderAdjustedProjectFee,
            changeOrderProviderStakeForfeit,
            changeOrderDetailsURI
        );
    }

    function _projectWithArbitration(uint256 _projectId) public {
        _projectWithChangeOrder(_projectId);
        Marketplace.Project memory project = marketplace.getProject(_projectId);
            // warp past change order period
        vm.warp(block.timestamp + marketplace.CHANGE_ORDER_PERIOD() + 1);
        vm.prank(project.buyer);
        petitionId = marketplace.disputeProject(
            project.projectId,
            arbitrationAdjustedProjectFee,
            arbitrationProviderStakeForfeit
        );
    }

    function _confirmedJury() public {
        Court.Petition memory petition = court.getPetition(petitionId);
            // plaintiff pays
        vm.prank(petition.plaintiff);
        court.payArbitrationFee{value: petition.arbitrationFee}(petitionId, evidence1);
            // defendant pays and jury selection is initiated
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
    }

    function _arbitrationPetitionGranted(uint256 _projectId) public {
        _projectWithArbitration(_projectId);
        _confirmedJury();
            // jurors vote
        Court.Petition memory petition = court.getPetition(petitionId);
        Court.Jury memory jury = court.getJury(petition.petitionId);
        bytes32 commit = keccak256(abi.encodePacked(true, "someSalt"));
        vm.prank(jury.confirmedJurors[0]);
        court.commitVote(petition.petitionId, commit);
        commit = keccak256(abi.encodePacked(true, "someSalt"));
        vm.prank(jury.confirmedJurors[1]);
        court.commitVote(petition.petitionId, commit);
        commit = keccak256(abi.encodePacked(true, "someSalt"));
        vm.prank(jury.confirmedJurors[2]);
        court.commitVote(petition.petitionId, commit);
            // jurors reveal
        vm.prank(jury.confirmedJurors[0]);
        court.revealVote(petition.petitionId, true, "someSalt");
        vm.prank(jury.confirmedJurors[1]);
        court.revealVote(petition.petitionId, true, "someSalt");
        vm.prank(jury.confirmedJurors[2]);
        court.revealVote(petition.petitionId, true, "someSalt");
            // defendant (provider) waives appeal
        vm.prank(petition.defendant);
        marketplace.waiveAppeal(_projectId);
    }

    function _arbitrationPetitionNotGranted(uint256 _projectId) public {
        _projectWithArbitration(_projectId);
        _confirmedJury();
            // jurors vote
        Court.Petition memory petition = court.getPetition(petitionId);
        Court.Jury memory jury = court.getJury(petition.petitionId);
        bytes32 commit = keccak256(abi.encodePacked(false, "someSalt"));
        vm.prank(jury.confirmedJurors[0]);
        court.commitVote(petition.petitionId, commit);
        commit = keccak256(abi.encodePacked(false, "someSalt"));
        vm.prank(jury.confirmedJurors[1]);
        court.commitVote(petition.petitionId, commit);
        commit = keccak256(abi.encodePacked(true, "someSalt"));
        vm.prank(jury.confirmedJurors[2]);
        court.commitVote(petition.petitionId, commit);
            // jurors reveal
        vm.prank(jury.confirmedJurors[0]);
        court.revealVote(petition.petitionId, false, "someSalt");
        vm.prank(jury.confirmedJurors[1]);
        court.revealVote(petition.petitionId, false, "someSalt");
        vm.prank(jury.confirmedJurors[2]);
        court.revealVote(petition.petitionId, true, "someSalt");
            // appeal period passes and defendant resolves 
        vm.warp(block.timestamp + marketplace.APPEAL_PERIOD() + 1);
        vm.prank(petition.defendant);
        marketplace.resolveByCourtOrder(_projectId);
    }

    function _setBeforeBalances(
        address _paymentToken,
        address _buyer, 
        address _provider, 
        address _escrow
    ) 
        public 
    {
        if(_paymentToken == address(0)) {
            buyerBalBefore = _buyer.balance;
            providerBalBefore = _provider.balance;
            escrowBalBefore = _escrow.balance;
        } else {
            buyerBalBefore = IERC20(_paymentToken).balanceOf(_buyer);
            providerBalBefore = IERC20(_paymentToken).balanceOf(_provider);
            escrowBalBefore = IERC20(_paymentToken).balanceOf(_escrow);
        }
    }

    function _setCurrentBalances(
        address _paymentToken,
        address _buyer, 
        address _provider, 
        address _escrow
    ) 
        public 
    {
        if(_paymentToken == address(0)) {
            buyerBalCurrent = _buyer.balance;
            providerBalCurrent = _provider.balance;
            escrowBalCurrent = _escrow.balance;
        } else {
            buyerBalCurrent = IERC20(_paymentToken).balanceOf(_buyer);
            providerBalCurrent = IERC20(_paymentToken).balanceOf(_provider);
            escrowBalCurrent = IERC20(_paymentToken).balanceOf(_escrow);
        }
    }

    function test_withdraw_cancelled_project() public {
        vm.pauseGasMetering();
        Marketplace.Project memory project = marketplace.getProject(testProjectId_ERC20);
        IEscrow escrow = IEscrow(project.escrow);
        vm.prank(project.buyer);
        marketplace.cancelProject(project.projectId);
        _setBeforeBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
        vm.resumeGasMetering();
        // buyer can withdraw project fee
        vm.prank(project.buyer);
        escrow.withdraw();
        _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
        assertEq(buyerBalCurrent, buyerBalBefore + projectFee);
        assertEq(escrowBalCurrent, escrowBalBefore - projectFee);
        assertEq(escrow.hasWithdrawn(project.buyer), true);
        // provider is not owed
        vm.expectRevert(Escrow.Escrow__NoPaymentDue.selector);
        vm.prank(project.provider);
        escrow.withdraw();
    }

    function test_withdraw_approved_project() public {
        vm.pauseGasMetering();
        _approvedProject(testProjectId_MATIC);
        Marketplace.Project memory project = marketplace.getProject(testProjectId_MATIC);
        IEscrow escrow = IEscrow(project.escrow);
        _setBeforeBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
        vm.resumeGasMetering();
        // provider can withdraw project fee (- commission) and provider stake
        uint256 commissionFee = project.projectFee/100;
        uint256 marketplaceBalBefore = address(marketplace).balance;
        uint256 commissionsMappingBefore = marketplace.getCommissionFees(address(0));
        vm.prank(project.provider);
        escrow.withdraw();
        _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
        assertEq(providerBalCurrent, providerBalBefore + project.projectFee + project.providerStake - commissionFee);
        assertEq(escrow.hasWithdrawn(project.provider), true);
        // commission has gone to marketplace
        assertEq(address(marketplace).balance, marketplaceBalBefore + commissionFee);
        assertEq(marketplace.getCommissionFees(address(0)), commissionsMappingBefore + commissionFee);
        // buyer is not owed
        vm.expectRevert(Escrow.Escrow__NoPaymentDue.selector);
        vm.prank(project.buyer);
        escrow.withdraw();
    }

    // delinquent payment

    // arbitration dismissed

    function test_withdraw_change_order() public {
        vm.pauseGasMetering();
        _projectWithChangeOrder(testProjectId_ERC20);
        Marketplace.Project memory project = marketplace.getProject(testProjectId_ERC20);
        IEscrow escrow = IEscrow(project.escrow);
        vm.prank(project.provider);
        marketplace.approveChangeOrder(project.projectId);
        _setBeforeBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
        vm.resumeGasMetering();
        // provider can withdraw adjusted project fee + stake (- forfeit) - commission
        uint256 commissionFee = changeOrderAdjustedProjectFee/100;
        vm.prank(project.provider);
        escrow.withdraw();
        _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
        assertEq(providerBalCurrent, 
            providerBalBefore + 
            changeOrderAdjustedProjectFee + 
            project.providerStake - 
            changeOrderProviderStakeForfeit - 
            commissionFee
        );
        // buyer can withdraw remaining project fee + stake forfeit
        vm.prank(project.buyer);
        escrow.withdraw();
        _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
        assertEq(buyerBalCurrent, 
            buyerBalBefore + 
            project.projectFee - 
            changeOrderAdjustedProjectFee + 
            changeOrderProviderStakeForfeit
        );
    }

    function test_withdraw_court_order_granted() public {
        vm.pauseGasMetering();
        _arbitrationPetitionGranted(testProjectId_MATIC);
        Marketplace.Project memory project = marketplace.getProject(testProjectId_MATIC);
        IEscrow escrow = IEscrow(project.escrow);
        _setBeforeBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
        vm.resumeGasMetering();
        // buyer can withdraw remaining project fee + stake forfeit
        vm.prank(project.buyer);
        escrow.withdraw();
        _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
        assertEq(buyerBalCurrent, 
            buyerBalBefore + 
            project.projectFee - 
            arbitrationAdjustedProjectFee + 
            arbitrationProviderStakeForfeit
        );
        // provider can withdraw adjusted project fee + stake (- forfeit) - commission
        uint256 commissionFee = arbitrationAdjustedProjectFee/100;
        vm.prank(project.provider);
        escrow.withdraw();
        _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
        assertEq(providerBalCurrent, 
            providerBalBefore + 
            arbitrationAdjustedProjectFee + 
            project.providerStake - 
            arbitrationProviderStakeForfeit - 
            commissionFee
        );
    }

    function test_withdraw_court_order_not_granted() public {
        vm.pauseGasMetering();
        _arbitrationPetitionNotGranted(testProjectId_ERC20);
        Marketplace.Project memory project = marketplace.getProject(testProjectId_ERC20);
        IEscrow escrow = IEscrow(project.escrow);
        _setBeforeBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
        vm.resumeGasMetering();
        // provider (defendant - won case) can withdraw original amount (project fee + stake - commission)
        uint256 commissionFee = project.projectFee/100;
        vm.prank(project.provider);
        escrow.withdraw();
        _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
        assertEq(providerBalCurrent, providerBalBefore + project.projectFee + project.providerStake - commissionFee);
        // nothing owed to buyer
        vm.expectRevert(Escrow.Escrow__NoPaymentDue.selector);
        vm.prank(project.buyer);
        escrow.withdraw();
    }

    function test_withdraw_dismissed_arbitration_case() public {
        vm.pauseGasMetering();
        _projectWithArbitration(testProjectId_MATIC);
        Marketplace.Project memory project = marketplace.getProject(testProjectId_MATIC);
        IEscrow escrow = IEscrow(project.escrow);
            // discovery period passes no one pays, case is dismissed 
        vm.warp(block.timestamp + court.DISCOVERY_PERIOD() + 1);
        court.dismissUnpaidCase(marketplace.getArbitrationPetitionId(project.projectId));
        vm.prank(project.buyer);
        marketplace.resolveDismissedCase(project.projectId);
        _setBeforeBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
        vm.resumeGasMetering();
        // provider can withdraw project fee + stake - commission
        uint256 commissionFee = project.projectFee/100;
        vm.prank(project.provider);
        escrow.withdraw();
        _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
        assertEq(providerBalCurrent, providerBalBefore + project.projectFee + project.providerStake - commissionFee);
        // nothing owed to buyer
        vm.expectRevert(Escrow.Escrow__NoPaymentDue.selector);
        vm.prank(project.buyer);
        escrow.withdraw();
    }

    function test_withdraw_delinquent_payment() public {
        vm.pauseGasMetering();
        _completedProject(testProjectId_ERC20);
        Marketplace.Project memory project = marketplace.getProject(testProjectId_ERC20);
        IEscrow escrow = IEscrow(project.escrow);
            // review period passes, buyer does not approve, provider marks payment delinquent
        vm.warp(block.timestamp + project.reviewPeriodLength + 1);
        vm.prank(project.provider);
        marketplace.delinquentPayment(project.projectId);
        _setBeforeBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
        vm.resumeGasMetering();
        // provider can withdraw project fee + stake - commission
        uint256 commissionFee = project.projectFee/100;
        vm.prank(project.provider);
        escrow.withdraw();
        _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
        assertEq(providerBalCurrent, providerBalBefore + project.projectFee + project.providerStake - commissionFee);
        // nothing owed to buyer
        vm.expectRevert(Escrow.Escrow__NoPaymentDue.selector);
        vm.prank(project.buyer);
        escrow.withdraw();
    }

    function test_arbitration_with_settlement() public {
        vm.pauseGasMetering();
        _projectWithArbitration(testProjectId_MATIC);
        Marketplace.Project memory project = marketplace.getProject(testProjectId_MATIC);
        IEscrow escrow = IEscrow(project.escrow);
            // settlement proposed and approved
        vm.prank(project.provider);
        marketplace.proposeSettlement(
            project.projectId,
            changeOrderAdjustedProjectFee,
            changeOrderProviderStakeForfeit,
            changeOrderDetailsURI
        );
        vm.prank(project.buyer);
        marketplace.approveChangeOrder(project.projectId);
        Court.Petition memory petition = court.getPetition(marketplace.getArbitrationPetitionId(project.projectId));
        assertEq(uint(petition.phase), uint(Court.Phase.SettledExternally));
        _setBeforeBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
        vm.resumeGasMetering();
         // provider can withdraw adjusted project fee + stake (- forfeit) - commission
        uint256 commissionFee = changeOrderAdjustedProjectFee/100;
        vm.prank(project.provider);
        escrow.withdraw();
        _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
        assertEq(providerBalCurrent, 
            providerBalBefore + 
            changeOrderAdjustedProjectFee + 
            project.providerStake - 
            changeOrderProviderStakeForfeit - 
            commissionFee
        );
        // buyer can withdraw remaining project fee + stake forfeit
        vm.prank(project.buyer);
        escrow.withdraw();
        _setCurrentBalances(project.paymentToken, project.buyer, project.provider, project.escrow);
        assertEq(buyerBalCurrent, 
            buyerBalBefore + 
            project.projectFee - 
            changeOrderAdjustedProjectFee + 
            changeOrderProviderStakeForfeit
        );
    }

    function test_withdraw_revert() public {
        vm.pauseGasMetering();
        _completedProject(testProjectId_ERC20);
        Marketplace.Project memory project = marketplace.getProject(testProjectId_ERC20);
        IEscrow escrow = IEscrow(project.escrow);
        vm.resumeGasMetering();
        // not releasable
        vm.expectRevert(Escrow.Escrow__NotReleasable.selector);
        vm.prank(project.provider);
        escrow.withdraw();
        // double withdraw
            // buyer approves, provider withdraws 
        vm.prank(project.buyer);
        marketplace.approveProject(project.projectId);
        vm.prank(project.provider);
        escrow.withdraw();
        vm.expectRevert(Escrow.Escrow__UserHasAlreadyWithdrawn.selector);
        vm.prank(project.provider);
        escrow.withdraw();
    }
    

}
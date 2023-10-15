// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/Interfaces/IEscrow.sol";
import "forge-std/console.sol";

contract MarketplaceProjectTest is Test, TestSetup {

    event ProjectCreated(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectCancelled(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectActivated(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectDiscontinued(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectCompleted(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectApproved(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectChallenged(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectDisputed(uint256 indexed projectId, address indexed buyer, address indexed provider, uint256 petitionId);
    event DelinquentPayment(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectAppealed(uint256 indexed projectId, uint256 indexed petitionId, address appealedBy);
    event ResolvedByCourtOrder(uint256 indexed projectId, uint256 indexed petitionId);
    event ResolvedByDismissedCase(uint256 indexed projectId, uint256 indexed petitionId);
    event SettlementProposed(uint256 indexed projectId, uint256 indexed petitionId);
    // event FeesWithdrawn(address recipient, uint256 nativeAmount, address[] erc20Tokens, uint256[] erc20Amounts);

    function setUp() public {
        _setUp();
        _whitelistUsers();
        _registerJurors();
        _initializeTestProjects();
    }

    //////////////////////////
    ///   CREATE PROJECT   ///
    //////////////////////////

    function test_createProject_native() public {
        uint256 currentProjectIdBefore = marketplace.projectIds();
        string memory details = "ipfs://someNewURI"; 
        uint256 txFee = marketplace.calculateNebulaiTxFee(projectFee);
        uint256 marketplaceBalanceBefore = address(marketplace).balance;
        // console.log(currentProjectId);
        vm.expectEmit(true, true, true, false);
        emit ProjectCreated(currentProjectIdBefore + 1, alice, bob);
        vm.prank(alice);
        uint256 newProjectId = marketplace.createProject{value: projectFee + txFee}(
            bob, address(0), projectFee, providerStake, dueDate, reviewPeriodLength, details
        );
        Marketplace.Project memory project = marketplace.getProject(newProjectId);
        // correct project ID
        assertEq(currentProjectIdBefore + 1, project.projectId);
        // project stored correctly
        assertEq(project.buyer, alice);
        assertEq(project.provider, bob);
        assertEq(project.paymentToken, address(0));
        assertEq(project.projectFee, projectFee);
        assertEq(project.providerStake, providerStake);
        assertEq(project.dueDate, dueDate);
        assertEq(project.reviewPeriodLength, reviewPeriodLength);
        assertEq(project.detailsURI, details);
        assertEq(project.dateCompleted, 0);
        assertEq(project.changeOrderPeriodInitiated, 0);
        assertEq(project.nebulaiTxFee, txFee);
        assertEq(uint(project.status), uint(Status.Created));
        // escrow generated
        assertEq(IEscrow(project.escrow).PROJECT_ID(), project.projectId);
        // escrow holds project fee
        assertEq(project.escrow.balance, projectFee);
        // marketplace holds tx fee
        assertEq(address(marketplace).balance, marketplaceBalanceBefore + project.nebulaiTxFee);
        // tx fee recorded
        assertEq(marketplace.getTxFeesHeld(project.projectId), project.nebulaiTxFee);
    }

    function test_createProject_ERC20() public {
        uint256 currentProjectIdBefore = marketplace.projectIds();
        string memory details = "ipfs://someNewURI"; 
        uint256 txFee = marketplace.calculateNebulaiTxFee(projectFee);
        uint256 marketplaceBalanceBefore = usdt.balanceOf(address(marketplace));
        // console.log(currentProjectId);
        vm.prank(alice);
        usdt.approve(address(marketplace), projectFee + txFee);
        vm.expectEmit(true, true, true, false);
        emit ProjectCreated(currentProjectIdBefore + 1, alice, bob);
        vm.prank(alice);
        uint256 newProjectId = marketplace.createProject(
            bob, address(usdt), projectFee, providerStake, dueDate, reviewPeriodLength, details
        );
        Marketplace.Project memory project = marketplace.getProject(newProjectId);
        // correct project ID
        assertEq(currentProjectIdBefore + 1, project.projectId);
        // project stored correctly
        assertEq(project.buyer, alice);
        assertEq(project.provider, bob);
        assertEq(project.paymentToken, address(usdt));
        assertEq(project.projectFee, projectFee);
        assertEq(project.providerStake, providerStake);
        assertEq(project.dueDate, dueDate);
        assertEq(project.reviewPeriodLength, reviewPeriodLength);
        assertEq(project.detailsURI, details);
        assertEq(project.dateCompleted, 0);
        assertEq(project.changeOrderPeriodInitiated, 0);
        assertEq(project.nebulaiTxFee, txFee);
        assertEq(uint(project.status), uint(Status.Created));
        // escrow generated
        assertEq(IEscrow(project.escrow).PROJECT_ID(), project.projectId);
        // escrow holds project fee
        assertEq(usdt.balanceOf(project.escrow), projectFee);
        // marketplace holds tx fee
        assertEq(usdt.balanceOf(address(marketplace)), marketplaceBalanceBefore + project.nebulaiTxFee);
        // tx fee recorded
        assertEq(marketplace.getTxFeesHeld(project.projectId), project.nebulaiTxFee);
    }

    function test_createProject_revert() public {
        string memory details = "ipfs://someNewURI"; 
        uint256 txFee = marketplace.calculateNebulaiTxFee(projectFee);
        // invalid provider address
        vm.expectRevert(Marketplace.Marketplace__InvalidProviderAddress.selector);
        vm.prank(alice);
        marketplace.createProject{value: projectFee + txFee}(
            alice, address(0), projectFee, providerStake, dueDate, reviewPeriodLength, details
        ); // provider address is same as buyer
        vm.expectRevert(Marketplace.Marketplace__InvalidProviderAddress.selector);
        vm.prank(alice);
        marketplace.createProject{value: projectFee + txFee}(
            address(0), address(0), projectFee, providerStake, dueDate, reviewPeriodLength, details
        ); // provider address is 0x0
        // invalid due date
        vm.expectRevert(Marketplace.Marketplace__InvalidDueDate.selector);
        vm.prank(alice);
        marketplace.createProject{value: projectFee + txFee}(
            bob, address(0), projectFee, providerStake, block.timestamp - 1, reviewPeriodLength, details
        ); // due date in the past
        vm.expectRevert(Marketplace.Marketplace__InvalidDueDate.selector);
        vm.prank(alice);
        marketplace.createProject{value: projectFee + txFee}(
            bob, address(0), projectFee, providerStake, block.timestamp + 365 days + 1, reviewPeriodLength, details
        ); // due date more than 365 days in the future
        // unapproved token
        assertEq(marketplace.isApprovedToken(address(1)), false);
        vm.expectRevert(Marketplace.Marketplace__UnapprovedToken.selector);
        vm.prank(alice);
        marketplace.createProject{value: projectFee + txFee}(
            bob, address(1), projectFee, providerStake, dueDate, reviewPeriodLength, details
        );
        // insufficient erc20 approval
        vm.prank(alice);
        usdt.approve(address(marketplace), projectFee + txFee - 1);
        vm.expectRevert(Marketplace.Marketplace__InsufficientApproval.selector);
        vm.prank(alice);
        marketplace.createProject(
            bob, address(usdt), projectFee, providerStake, dueDate, reviewPeriodLength, details
        );
        // insufficient value
        vm.expectRevert(Marketplace.Marketplace__InsufficientAmount.selector);
        vm.prank(alice);
        marketplace.createProject{value: projectFee + txFee - 1}(
            bob, address(0), projectFee, providerStake, dueDate, reviewPeriodLength, details
        );
        // attempt to send native currency when creating ERC20 project
        vm.prank(alice);
        usdt.approve(address(marketplace), projectFee + txFee);
        vm.expectRevert(Marketplace.Marketplace__NativeCurrencySent.selector);
        vm.prank(alice);
        marketplace.createProject{value: 1}(
            bob, address(usdt), projectFee, providerStake, dueDate, reviewPeriodLength, details
        );
    }

    function test_minimum_tx_fee_charged_on_projects_with_low_project_fee() public {
        uint256 txFee = marketplace.calculateNebulaiTxFee(0);
        uint256 marketplaceBalanceBefore = address(marketplace).balance;
        vm.prank(alice);
        uint256 id = marketplace.createProject{value: txFee}(
            bob, address(0), 0, providerStake, dueDate, reviewPeriodLength, "ipfs://someDetails"
        );
        Marketplace.Project memory project = marketplace.getProject(id);
        assertEq(project.nebulaiTxFee, marketplace.minimumTxFee());
        assertEq(address(marketplace).balance, marketplaceBalanceBefore + marketplace.minimumTxFee());
    }

    function testFuzz_createProject_native(uint256 _amount) public {
        uint256 hugeBalance = 1000000000000000 ether;
        vm.assume(_amount < hugeBalance);
        uint256 txFee = marketplace.calculateNebulaiTxFee(_amount);
        vm.deal(alice, _amount + txFee);
        
        uint256 currentProjectIdBefore = marketplace.projectIds();
        string memory details = "ipfs://someNewURI"; 
        uint256 marketplaceBalanceBefore = address(marketplace).balance;
        vm.expectEmit(true, true, true, false);
        emit ProjectCreated(currentProjectIdBefore + 1, alice, bob);
        vm.prank(alice);
        uint256 newProjectId = marketplace.createProject{value: _amount + txFee}(
            bob, address(0), _amount, providerStake, dueDate, reviewPeriodLength, details
        );
        Marketplace.Project memory project = marketplace.getProject(newProjectId);
        // correct project ID
        assertEq(currentProjectIdBefore + 1, project.projectId);
        // project stored correctly
        assertEq(project.buyer, alice);
        assertEq(project.provider, bob);
        assertEq(project.paymentToken, address(0));
        assertEq(project.projectFee, _amount);
        assertEq(project.providerStake, providerStake);
        assertEq(project.dueDate, dueDate);
        assertEq(project.reviewPeriodLength, reviewPeriodLength);
        assertEq(project.detailsURI, details);
        assertEq(project.dateCompleted, 0);
        assertEq(project.changeOrderPeriodInitiated, 0);
        assertEq(project.nebulaiTxFee, txFee);
        assertEq(uint(project.status), uint(Status.Created));
        // escrow generated
        assertEq(IEscrow(project.escrow).PROJECT_ID(), project.projectId);
        // escrow holds project fee
        assertEq(project.escrow.balance, _amount);
        // marketplace holds tx fee
        assertEq(address(marketplace).balance, marketplaceBalanceBefore + project.nebulaiTxFee);
        // tx fee recorded
        assertEq(marketplace.getTxFeesHeld(project.projectId), project.nebulaiTxFee);
    }

    function testFuzz_createProject_erc20(uint256 _amount) public {
        uint256 hugeBalance = 1000000000000000 ether;
        vm.assume(_amount < hugeBalance);
        uint256 txFee = marketplace.calculateNebulaiTxFee(_amount);
        usdt.mint(alice, _amount + txFee);
        
        uint256 currentProjectIdBefore = marketplace.projectIds();
        string memory details = "ipfs://someNewURI"; 
        uint256 marketplaceBalanceBefore = usdt.balanceOf(address(marketplace));
        vm.prank(alice);
        usdt.approve(address(marketplace), _amount + txFee);
        vm.expectEmit(true, true, true, false);
        emit ProjectCreated(currentProjectIdBefore + 1, alice, bob);
        vm.prank(alice);
        uint256 newProjectId = marketplace.createProject(
            bob, address(usdt), _amount, providerStake, dueDate, reviewPeriodLength, details
        );
        Marketplace.Project memory project = marketplace.getProject(newProjectId);
        // correct project ID
        assertEq(currentProjectIdBefore + 1, project.projectId);
        // project stored correctly
        assertEq(project.buyer, alice);
        assertEq(project.provider, bob);
        assertEq(project.paymentToken, address(usdt));
        assertEq(project.projectFee, _amount);
        assertEq(project.providerStake, providerStake);
        assertEq(project.dueDate, dueDate);
        assertEq(project.reviewPeriodLength, reviewPeriodLength);
        assertEq(project.detailsURI, details);
        assertEq(project.dateCompleted, 0);
        assertEq(project.changeOrderPeriodInitiated, 0);
        assertEq(project.nebulaiTxFee, txFee);
        assertEq(uint(project.status), uint(Status.Created));
        // escrow generated
        assertEq(IEscrow(project.escrow).PROJECT_ID(), project.projectId);
        // escrow holds project fee
        assertEq(usdt.balanceOf(project.escrow), _amount);
        // marketplace holds tx fee
        assertEq(usdt.balanceOf(address(marketplace)), marketplaceBalanceBefore + project.nebulaiTxFee);
        // tx fee recorded
        assertEq(marketplace.getTxFeesHeld(project.projectId), project.nebulaiTxFee);
    } 

    //////////////////////////
    ///   CANCEL PROJECT   ///
    //////////////////////////

    function test_cancelProject() public {
        uint256[2] memory createdProjects = [id_created_MATIC, id_created_ERC20];
        for(uint i = 0; i < createdProjects.length; ++i) {
            Project memory project = marketplace.getProject(createdProjects[i]);
            uint256 contractBalBefore = _getBalance(address(marketplace), project.paymentToken);
            uint256 buyerBalBefore = _getBalance(buyer, project.paymentToken);
            uint256 feeHeld = marketplace.getTxFeesHeld(project.projectId);
            
            vm.expectEmit(true, true, true, false);
            emit ProjectCancelled(project.projectId, project.buyer, project.provider);
            vm.prank(project.buyer);
            marketplace.cancelProject(project.projectId);

            project = marketplace.getProject(createdProjects[i]);    
            assertEq(uint(project.status), uint(Status.Cancelled));
            assertEq(_getBalance(address(marketplace), project.paymentToken), contractBalBefore - feeHeld);
            assertEq(_getBalance(buyer, project.paymentToken), buyerBalBefore + feeHeld);    
            assertEq(marketplace.getTxFeesHeld(project.projectId), 0);    
        }
    }

    function test_cancelProject_revert() public {
        Project memory project = marketplace.getProject(id_created_MATIC);
        // not buyer
        vm.expectRevert(Marketplace.Marketplace__OnlyBuyer.selector);
        vm.prank(project.provider);
        marketplace.cancelProject(project.projectId);
        // wrong status
        project = marketplace.getProject(id_active_ERC20);
        vm.expectRevert(Marketplace.Marketplace__ProjectCannotBeCancelled.selector);
        vm.prank(project.buyer);
        marketplace.cancelProject(project.projectId);
    }

    ////////////////////////////
    ///   ACTIVATE PROJECT   ///
    ////////////////////////////

    function test_activateProject() public {
       uint256[2] memory createdProjects = [id_created_MATIC, id_created_ERC20];
        for(uint i = 0; i < createdProjects.length; ++i) {
            Project memory project = marketplace.getProject(createdProjects[i]);
            IEscrow escrow = IEscrow(project.escrow);
            assertEq(escrow.providerHasStaked(), false);
            uint256 escrowBalBefore = _getBalance(project.escrow, project.paymentToken);
            uint256 providerBalBefore = _getBalance(provider, project.paymentToken);
            uint256 feeHeld = marketplace.getTxFeesHeld(project.projectId);
            uint256 feesPaid = marketplace.getTxFeesPaid(project.paymentToken);

            uint256 value;
            if(project.paymentToken != address(0)) {
                vm.prank(project.provider);
                IERC20(project.paymentToken).approve(address(marketplace), project.providerStake);
            } else {
                value = project.providerStake;
            }
            
            vm.expectEmit(true, true, true, false);
            emit ProjectActivated(project.projectId, project.buyer, project.provider);
            vm.prank(project.provider);
            marketplace.activateProject{value: value}(project.projectId);

            project = marketplace.getProject(createdProjects[i]);    
            assertEq(uint(project.status), uint(Status.Active));
            assertEq(escrow.providerHasStaked(), true);
            assertEq(_getBalance(project.escrow, project.paymentToken), escrowBalBefore + providerStake);
            assertEq(_getBalance(provider, project.paymentToken), providerBalBefore - project.providerStake);
            assertEq(marketplace.getTxFeesPaid(project.paymentToken), feesPaid + feeHeld);   
        }
    }

    function test_activateProject_revert() public {
        // not provider
        Project memory project = marketplace.getProject(id_created_MATIC);
        vm.expectRevert(Marketplace.Marketplace__OnlyProvider.selector);
        vm.prank(project.buyer);
        marketplace.activateProject{value: project.providerStake}(project.projectId);
        // wrong status
        project = marketplace.getProject(id_active_MATIC);
        vm.expectRevert(Marketplace.Marketplace__ProjectCannotBeActivated.selector);
        vm.prank(project.provider);
        marketplace.activateProject{value: project.providerStake}(project.projectId);
        // insufficient stake 
        project = marketplace.getProject(id_created_MATIC);
        vm.expectRevert(Marketplace.Marketplace__InsufficientAmount.selector);
        vm.prank(project.provider);
        marketplace.activateProject{value: project.providerStake - 1}(project.projectId);
        // insufficient approval
        project = marketplace.getProject(id_created_ERC20);
        vm.prank(project.provider);
        IERC20(project.paymentToken).approve(address(marketplace), project.providerStake - 1);
        vm.expectRevert(Marketplace.Marketplace__InsufficientApproval.selector);
        vm.prank(project.provider);
        marketplace.activateProject(project.projectId);
        // attempt to send native currency for ERC20 project
        project = marketplace.getProject(id_created_ERC20);
        vm.prank(project.provider);
        IERC20(project.paymentToken).approve(address(marketplace), project.providerStake);
        vm.expectRevert(Marketplace.Marketplace__NativeCurrencySent.selector);
        vm.prank(project.provider);
        marketplace.activateProject{value: 42 ether}(project.projectId);
    }

    ///////////////////////////////
    ///   DISCONTINUE PROJECT   ///
    ///////////////////////////////

    function test_discontinueProject() public {
        // provider discontinues, proposes 50% payment for partial work
        Project memory project = marketplace.getProject(id_active_ERC20);
        assertEq(project.changeOrderPeriodInitiated, 0);
        vm.expectEmit(true, true, true, false);
        emit ProjectDiscontinued(project.projectId, project.buyer, project.provider);
        vm.prank(project.provider);
        marketplace.discontinueProject(
            project.projectId,
            project.projectFee/2,
            0,
            "ipfs://someChangeOrder/"
        );
        project = marketplace.getProject(id_active_ERC20);
        assertEq(uint(project.status), uint(Status.Discontinued));
        assertEq(project.changeOrderPeriodInitiated, block.timestamp);
    }

    function test_discontinueProject_revert() public {
        // not buyer or provider
        Project memory project = marketplace.getProject(id_active_ERC20);
        vm.expectRevert(Marketplace.Marketplace__OnlyBuyerOrProvider.selector);
        vm.prank(carlos);
        marketplace.discontinueProject(
            project.projectId,
            project.projectFee/2,
            0,
            "ipfs://someChangeOrder/"
        );
        // wrong status
        project = marketplace.getProject(id_created_ERC20);
        vm.expectRevert(Marketplace.Marketplace__ProjectMustBeActive.selector);
        vm.prank(project.buyer);
        marketplace.discontinueProject(
            project.projectId,
            project.projectFee/2,
            0,
            "ipfs://someChangeOrder/"
        );
        // invalid change order parameters
        project = marketplace.getProject(id_active_MATIC);
        vm.expectRevert(Marketplace.Marketplace__AdjustedFeeExceedsProjectFee.selector);
        vm.prank(project.provider);
        marketplace.discontinueProject(
            project.projectId,
            project.projectFee + 1,
            0,
            "ipfs://someChangeOrder/"
        );
    }

    ////////////////////////////
    ///   COMPLETE PROJECT   ///
    ////////////////////////////

    function test_completeProject() public {
        Project memory project = marketplace.getProject(id_active_MATIC);
        assertEq(project.dateCompleted, 0);
        vm.expectEmit(true, true, true, false);
        emit ProjectCompleted(project.projectId, project.buyer, project.provider);
        vm.prank(project.provider);
        marketplace.completeProject(project.projectId);
        project = marketplace.getProject(id_active_MATIC);
        assertEq(uint(project.status), uint(Status.Completed));
        assertEq(project.dateCompleted, block.timestamp);
    }

    function test_completeProject_revert() public {
        // not provider
        Project memory project = marketplace.getProject(id_active_ERC20);
        vm.expectRevert(Marketplace.Marketplace__OnlyProvider.selector);
        vm.prank(project.buyer);
        marketplace.completeProject(project.projectId);
        // wrong status
        project = marketplace.getProject(id_created_MATIC);
        vm.expectRevert(Marketplace.Marketplace__ProjectMustBeActive.selector);
        vm.prank(project.provider);
        marketplace.completeProject(project.projectId);
    }

    ///////////////////////////
    ///   APPROVE PROJECT   ///
    ///////////////////////////

    function test_approveProject() public {
        Project memory project = marketplace.getProject(id_complete_ERC20);
        vm.expectEmit(true, true, true, false);
        emit ProjectApproved(project.projectId, project.buyer, project.provider);
        vm.prank(project.buyer);
        marketplace.approveProject(project.projectId);
        project = marketplace.getProject(id_complete_ERC20);
        assertEq(uint(project.status), uint(Status.Approved));
    }

    function test_approveProject_revert() public {
        // not buyer
        Project memory project = marketplace.getProject(id_complete_ERC20);
        vm.expectRevert(Marketplace.Marketplace__OnlyBuyer.selector);
        vm.prank(project.provider);
        marketplace.approveProject(project.projectId);
        // not complete
        project = marketplace.getProject(id_active_ERC20);
        vm.expectRevert(Marketplace.Marketplace__ProjectNotCompleted.selector);
        vm.prank(project.buyer);
        marketplace.approveProject(project.projectId);
    }

    /////////////////////////////
    ///   CHALLENGE PROJECT   ///
    /////////////////////////////

    function test_challengeProject() public {
        Project memory project = marketplace.getProject(id_complete_MATIC);
        assertEq(project.changeOrderPeriodInitiated, 0);
        vm.prank(project.buyer);
        marketplace.challengeProject(
            project.projectId,
            project.projectFee - (project.projectFee/4),
            0,
            "ipfs://someChangeOrder/"
        );
        project = marketplace.getProject(project.projectId);
        assertEq(uint(project.status), uint(Status.Challenged));
        assertEq(project.changeOrderPeriodInitiated, block.timestamp);
    }

    function test_challengeProject_revert() public {
        // not buyer 
        Project memory project = marketplace.getProject(id_complete_MATIC);
        vm.expectRevert(Marketplace.Marketplace__OnlyBuyer.selector);
        vm.prank(project.provider);
        marketplace.challengeProject(
            project.projectId,
            project.projectFee - (project.projectFee/4),
            0,
            "ipfs://someChangeOrder/"
        );
        // not active or completed
        project = marketplace.getProject(id_created_MATIC);
        vm.expectRevert(Marketplace.Marketplace__ProjectCannotBeChallenged.selector);
        vm.prank(project.buyer);
        marketplace.challengeProject(
            project.projectId,
            project.projectFee - (project.projectFee/4),
            0,
            "ipfs://someChangeOrder/"
        );
        // active but not overdue
        project = marketplace.getProject(id_active_ERC20);
        assertTrue(block.timestamp < project.dueDate);
        vm.expectRevert(Marketplace.Marketplace__ProjectIsNotOverdue.selector);
        vm.prank(project.buyer);
        marketplace.challengeProject(
            project.projectId,
            project.projectFee - (project.projectFee/4),
            0,
            "ipfs://someChangeOrder/"
        );
        // completed but after review period
        project = marketplace.getProject(id_complete_ERC20);
        vm.warp(block.timestamp + project.reviewPeriodLength + 1);
        vm.expectRevert(Marketplace.Marketplace__ProjectReviewPeriodEnded.selector);
        vm.prank(project.buyer);
        marketplace.challengeProject(
            project.projectId,
            project.projectFee - (project.projectFee/4),
            0,
            "ipfs://someChangeOrder/"
        );
    }

    ///////////////////////////
    ///   DISPUTE PROJECY   ///
    ///////////////////////////

    function test_disputeProject() public {
        Project memory project = marketplace.getProject(id_challenged_ERC20);
        vm.warp(block.timestamp + marketplace.CHANGE_ORDER_PERIOD() + 1);
        assertEq(marketplace.activeChangeOrder(project.projectId), true);
        assertEq(marketplace.getArbitrationPetitionId(project.projectId), 0);

        vm.expectEmit(true, true, true, true);
        emit ProjectDisputed(project.projectId, project.buyer, project.provider, court.petitionIds() + 1);
        vm.prank(project.provider);
        marketplace.disputeProject(
            project.projectId,
            project.projectFee - (project.projectFee/10),
            0
        );
        
        project = marketplace.getProject(project.projectId);
        assertEq(uint(project.status), uint(Status.Disputed));
        // no longer has active change order
        assertEq(marketplace.activeChangeOrder(project.projectId), false);
        // has petition Id
        assertEq(marketplace.getArbitrationPetitionId(project.projectId), court.petitionIds());
    }

    function test_disputeProject_revert() public {
        // not buyer or provider
        Project memory project = marketplace.getProject(id_challenged_ERC20);
        vm.expectRevert(Marketplace.Marketplace__OnlyBuyerOrProvider.selector);
        vm.prank(zorro);
        marketplace.disputeProject(project.projectId, project.projectFee/2, 0);
        // not challenged or discontinued
        project = marketplace.getProject(id_active_MATIC);
        vm.expectRevert(Marketplace.Marketplace__ProjectCannotBeDisputed.selector);
        vm.prank(project.buyer);
        marketplace.disputeProject(project.projectId, project.projectFee/2, 0);
        // change order period still active
        project = marketplace.getProject(id_challenged_ERC20);
        assertTrue(block.timestamp < project.changeOrderPeriodInitiated + marketplace.CHANGE_ORDER_PERIOD());
        vm.expectRevert(Marketplace.Marketplace__ChangeOrderPeriodStillActive.selector);
        vm.prank(project.buyer);
        marketplace.disputeProject(project.projectId, project.projectFee/2, 0);
        // adjusted project fee > project fee
        project = marketplace.getProject(id_challenged_ERC20);
        vm.warp(block.timestamp + marketplace.CHANGE_ORDER_PERIOD() + 1);
        vm.expectRevert(Marketplace.Marketplace__AdjustedFeeExceedsProjectFee.selector);
        vm.prank(project.buyer);
        marketplace.disputeProject(project.projectId, project.projectFee + 1, 0);
        // provider stake forfeit > provider stake
        project = marketplace.getProject(id_challenged_ERC20);
        vm.warp(block.timestamp + marketplace.CHANGE_ORDER_PERIOD() + 1);
        vm.expectRevert(Marketplace.Marketplace__ForfeitExceedsProviderStake.selector);
        vm.prank(project.buyer);
        marketplace.disputeProject(project.projectId, project.projectFee/2, project.providerStake + 1);
    }

}
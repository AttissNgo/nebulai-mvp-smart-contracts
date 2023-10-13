// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/Interfaces/IEscrow.sol";
import "forge-std/console.sol";

contract MarketplaceProjectTest is Test, TestSetup {
    
    // test project params
    address buyer = alice;
    address provider = bob;
    uint256 projectFee = 1000 ether;
    uint256 providerStake = 50 ether;
    uint256 dueDate;
    uint256 reviewPeriodLength = 3 days;
    
    uint256 id_MATIC;
    uint256 id_ERC20;

    // test change order
    uint256 changeOrderAdjustedProjectFee = 750 ether;
    string changeOrderDetailsURI = "ipfs://changeOrderUri";

    // test arbitration
    string[] evidence1 = ["someEvidenceURI", "someOtherEvidenceURI"];
    string[] evidence2 = ["someEvidenceURI2", "someOtherEvidenceURI2"];

    event ProjectCreated(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectCancelled(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectActivated(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectDiscontinued(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectCompleted(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectApproved(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectChallenged(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ProjectDisputed(uint256 indexed projectId, address indexed buyer, address indexed provider, uint256 petitionId);
    event DelinquentPayment(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ChangeOrderApproved(uint256 indexed projectId, address indexed buyer, address indexed provider);
    event ChangeOrderRetracted(uint256 indexed projectId, address indexed retractedBy);
    event ProjectAppealed(uint256 indexed projectId, uint256 indexed petitionId, address appealedBy);
    event ResolvedByCourtOrder(uint256 indexed projectId, uint256 indexed petitionId);
    event ResolvedByDismissedCase(uint256 indexed projectId, uint256 indexed petitionId);
    event SettlementProposed(uint256 indexed projectId, uint256 indexed petitionId);
    // event FeesWithdrawn(address recipient, uint256 nativeAmount, address[] erc20Tokens, uint256[] erc20Amounts);

    function setUp() public {
        _setUp();
        _whitelistUsers();
        _registerJurors();
        dueDate = block.timestamp + 30 days;
        id_MATIC = _createProject(
            buyer,
            provider,
            address(0),
            projectFee,
            providerStake,
            dueDate,
            reviewPeriodLength,
            "ipfs://someURI/MATIC"
        );
        id_ERC20 = _createProject(
            buyer,
            provider,
            address(0),
            projectFee,
            providerStake,
            dueDate,
            reviewPeriodLength,
            "ipfs://someURI/ERC20"
        );
    }

    function _createProject(
        address _buyer,
        address _provider,
        address _paymentToken,
        uint256 _projectFee,
        uint256 _providerStake,
        uint256 _dueDate,
        uint256 _reviewPeriodLength,
        string memory _detailsURI
    ) 
        internal
        returns (uint256)
    {
        uint256 txFee = marketplace.calculateNebulaiTxFee(_projectFee);
        if(_paymentToken != address(0)) {
            // if not native, approve amount
            IERC20(_paymentToken).approve(address(marketplace), _projectFee + txFee);
        }
        vm.prank(_buyer);
        uint256 id = marketplace.createProject{value: (_paymentToken == address(0) ? _projectFee + txFee : 0)}(
            _provider,
            _paymentToken,
            _projectFee,
            _providerStake,
            _dueDate,
            _reviewPeriodLength,
            _detailsURI
        );
        return id;
    }

    function test_createProject_native() public {
        uint256 currentProjectIdBefore = marketplace.projectIds();
        string memory details = "ipfs://someNewURI"; 
        uint256 txFee = marketplace.calculateNebulaiTxFee(projectFee);
        uint256 marketplaceBalanceBefore = address(marketplace).balance;
        // console.log(currentProjectId);
        vm.expectEmit(true, true, true, false);
        emit ProjectCreated(currentProjectIdBefore + 1, alice, bob);
        vm.prank(alice);
        uint256 newProjectId = marketplace.createProject{value: projectFee + txFee} (
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
}
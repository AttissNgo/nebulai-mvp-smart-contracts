// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "./USDTMock.sol";
import "chainlink/VRFCoordinatorV2Mock.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../src/Governor.sol";
import "../src/Whitelist.sol";
import "../src/MediatorPool.sol";
import "../src/MediationService.sol";
import "../src/EscrowFactory.sol";
import "../src/Marketplace.sol";
import "../src/DataStructuresLibrary.sol";


contract TestSetup is Test, DataStructuresLibrary {

    // mocks
    USDTMock public usdt; 
    VRFCoordinatorV2Mock public vrf;
    uint64 public subscriptionId;

    // contracts
    Governor public governor;
    uint8 sigsRequired = 3;

    Whitelist public whitelist;

    MediatorPool public mediatorPool;
    uint256 public minimumMediatorStake = 20 ether;

    MediationService public mediationService;

    EscrowFactory public escrowFactory;
    Marketplace public marketplace;
    address[] public approvedTokens;

    // test users
    address public alice = vm.addr(1);
    address public bob = vm.addr(2);
    address public carlos = vm.addr(3);
    address public david = vm.addr(4);
    address public erin = vm.addr(5);
    address public frank = vm.addr(6);
    address public grace = vm.addr(7);
    address public heidi = vm.addr(8);
    address public ivan = vm.addr(9);
    address public judy = vm.addr(10);
    address public kim = vm.addr(11);
    address public laura = vm.addr(12);
    address public mike = vm.addr(13);
    address public niaj = vm.addr(14);
    address public olivia = vm.addr(15);
    address public patricia = vm.addr(16);
    address public quentin = vm.addr(17);
    address public russel = vm.addr(18);
    address public sean = vm.addr(19);
    address public tabitha = vm.addr(20);
    address public ulrich = vm.addr(21);
    address public vincent = vm.addr(22);
    address public winona = vm.addr(23);
    address public xerxes = vm.addr(24);
    address public yanni = vm.addr(25);
    address public zorro = vm.addr(26);
    // test admins
    address public admin1 = vm.addr(100);
    address public admin2 = vm.addr(101);
    address public admin3 = vm.addr(102);
    address public admin4 = vm.addr(103);
    
    address[] public admins = [admin1, admin2, admin3, admin4];
    address[] public users = [alice,bob,carlos,david,erin,frank,grace,heidi,ivan,judy,kim,laura,mike,niaj,olivia,patricia,quentin,russel,sean,tabitha,ulrich,vincent,winona,xerxes,yanni,zorro];

    // test project params
    address buyer = alice;
    address provider = bob;
    uint256 projectFee = 1000 ether;
    uint256 providerStake = 50 ether;
    uint256 dueDate;
    uint256 reviewPeriodLength = 30 days;
    string detailsURI = "ipfs://someDetails/";
    
    // test project IDs
    uint256 id_created_MATIC;
    uint256 id_created_ERC20;
    uint256 id_active_MATIC;
    uint256 id_active_ERC20;
    uint256 id_complete_MATIC;
    uint256 id_complete_ERC20;
    uint256 id_approved_MATIC;
    uint256 id_approved_ERC20;
    uint256 id_challenged_MATIC;    
    uint256 id_challenged_ERC20;   
    uint256 id_approved_change_order_MATIC; 
    uint256 id_approved_change_order_ERC20; 

    // test projects with mediation
    uint256 id_mediation_disclosure_MATIC;
    uint256 id_mediation_disclosure_ERC20;
    uint256 id_mediation_panelSelection_MATIC;
    uint256 id_mediation_panelSelection_ERC20;
    uint256 id_mediation_confirmedPanel_MATIC;
    uint256 id_mediation_confirmedPanel_ERC20;
    uint256 id_mediation_committedVotes_MATIC;
    uint256 id_mediation_committedVotes_ERC20;

    // test change order
    uint256 changeOrderAdjustedProjectFee = 750 ether;
    uint256 changeOrderProviderStakeForfeit = 25 ether;
    string changeOrderDetailsURI = "ipfs://changeOrderUri";

    // test settlement
    uint256 settlementAdjustedProjectFee = 800 ether;
    uint256 settlementProviderStakeForfeit = 0;

    // test mediation
    string[] evidence1 = ["someEvidenceURI", "someOtherEvidenceURI"];
    string[] evidence2 = ["someEvidenceURI2", "someOtherEvidenceURI2"];

    function _setUp() internal {
        vm.startPrank(admin1);
        // deploy contracts
        usdt = new USDTMock(); 
        vrf = new VRFCoordinatorV2Mock(1, 1); 
        subscriptionId = vrf.createSubscription();
        vrf.fundSubscription(subscriptionId, 100 ether);
        governor = new Governor(admins, sigsRequired);
        whitelist = new Whitelist(address(governor));
        mediatorPool = new MediatorPool(address(governor), address(whitelist), minimumMediatorStake);

        uint64 nonce = vm.getNonce(admin1);
        address predictedMarketplace = computeCreateAddress(admin1, nonce + 2);

        mediationService = new MediationService(
            address(governor), 
            address(mediatorPool),
            address(vrf),
            subscriptionId,
            predictedMarketplace ////////////////
        );
        approvedTokens.push(address(usdt));
        escrowFactory = new EscrowFactory();
        marketplace = new Marketplace(
            address(governor), 
            address(whitelist), 
            address(mediationService), 
            address(escrowFactory),
            approvedTokens
        );
        vm.stopPrank();

        // supply ether & usdt
        for(uint i; i < users.length; ++i) {
            vm.deal(users[i], 10000 ether);
            usdt.mint(users[i], 10000 ether);
        }
        for(uint i; i < admins.length; ++i) {
            vm.deal(admins[i], 10000 ether);
            usdt.mint(admins[i], 10000 ether);
        }

        // label addresses
        _labelTestAddresses();

        // initialize test project variables
        dueDate = block.timestamp + 30 days;
    }

    function _whitelistUsers() public {
        for(uint i; i < users.length; ++i) {
            vm.prank(admin1);
            whitelist.approveAddress(users[i]);
        }
        for(uint i; i < admins.length; ++i) {
            vm.prank(admin1);
            whitelist.approveAddress(admins[i]);
        }
    }

    function _registerMediators() public {
        uint256 stakeAmount = 100 ether;
        for(uint i; i < users.length; ++i) {
            // vm.prank(users[i]);
            // mediatorPool.registerAsMediator{value: stakeAmount}();

            vm.prank(admin1);
            mediatorPool.registerMediator(users[i]);
            vm.prank(users[i]);
            mediatorPool.stake{value: stakeAmount}();

            stakeAmount += 10 ether;
        }
        for(uint i; i < admins.length; ++i) {
            vm.startPrank(admins[i]);
            // mediatorPool.registerAsMediator{value: stakeAmount}();
            mediatorPool.registerMediator(admins[i]);
            mediatorPool.stake{value: stakeAmount}();
            vm.stopPrank();

            stakeAmount += 10 ether;
        }
    }

    function util_executeGovernorTx(uint256 _txIndex) internal {
        for(uint i; i < admins.length; ++i) {
            Governor.Transaction memory transaction = governor.getTransaction(_txIndex);
            if(!governor.adminHasSigned(_txIndex, admins[i]) && transaction.numSignatures < governor.signaturesRequired()) {
                vm.prank(admins[i]);
                governor.signTransaction(_txIndex);
            }
        } 
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
        uint256 value;
        if(_paymentToken != address(0)) {
            // if not native, approve amount
            vm.prank(_buyer);
            IERC20(_paymentToken).approve(address(marketplace), _projectFee + txFee);
        } else {
            value = _projectFee + txFee;
        }
        vm.prank(_buyer);
        uint256 id = marketplace.createProject{value: value}(
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

    function _projectTemplate(address _paymentToken) public returns (uint256 id) {
        id = _createProject(
            buyer, provider, _paymentToken, projectFee, providerStake, dueDate, reviewPeriodLength, detailsURI
        );
    }

    function _initializeTestProjects() public {
        id_created_MATIC = _projectTemplate(address(0));
        id_created_ERC20 = _projectTemplate(address(usdt));

        id_active_MATIC = _activatedProject(_projectTemplate(address(0)));
        id_active_ERC20 = _activatedProject(_projectTemplate(address(usdt)));
        
        id_complete_MATIC = _completedProject(_projectTemplate(address(0)));
        id_complete_ERC20 = _completedProject(_projectTemplate(address(usdt)));

        id_approved_MATIC = _approvedProject(_projectTemplate(address(0)));
        id_approved_ERC20 = _approvedProject(_projectTemplate(address(usdt)));

        id_challenged_MATIC = _challengedProject(_projectTemplate(address(0)));
        id_challenged_ERC20 = _challengedProject(_projectTemplate(address(usdt)));

        id_approved_change_order_MATIC = _project_with_approvedChangeOrder(_projectTemplate(address(0)));
        id_approved_change_order_ERC20 = _project_with_approvedChangeOrder(_projectTemplate(address(usdt)));
    }

    function _initializeMediationProjects() public {
        vm.deal(buyer, 1000000 ether);
        usdt.mint(buyer, 1000000 ether);

        id_mediation_disclosure_MATIC = _challengedProject(_projectTemplate(address(0)));
        id_mediation_disclosure_ERC20 = _challengedProject(_projectTemplate(address(usdt)));
        id_mediation_panelSelection_MATIC = _challengedProject(_projectTemplate(address(0)));
        id_mediation_panelSelection_ERC20 = _challengedProject(_projectTemplate(address(usdt)));
        id_mediation_confirmedPanel_MATIC = _challengedProject(_projectTemplate(address(0)));
        id_mediation_confirmedPanel_ERC20 = _challengedProject(_projectTemplate(address(usdt)));
        id_mediation_committedVotes_MATIC = _challengedProject(_projectTemplate(address(0)));
        id_mediation_committedVotes_ERC20 = _challengedProject(_projectTemplate(address(usdt)));
        uint256[8] memory ids = [
            id_mediation_disclosure_ERC20, 
            id_mediation_disclosure_MATIC,
            id_mediation_panelSelection_MATIC,
            id_mediation_panelSelection_ERC20,
            id_mediation_confirmedPanel_ERC20,
            id_mediation_confirmedPanel_MATIC,
            id_mediation_committedVotes_MATIC,
            id_mediation_committedVotes_ERC20
        ];
        vm.warp(block.timestamp + marketplace.CHANGE_ORDER_PERIOD());
        for(uint i; i < ids.length; ++i) {
            Project memory project = marketplace.getProject(ids[i]);
            vm.prank(project.buyer);
            marketplace.disputeProject(
                project.projectId,
                changeOrderAdjustedProjectFee,
                changeOrderProviderStakeForfeit
            );
        }
        
        _payMediationFeesAndDrawMediators(id_mediation_panelSelection_ERC20);
        _payMediationFeesAndDrawMediators(id_mediation_panelSelection_MATIC);
        _payMediationFeesAndDrawMediators(id_mediation_confirmedPanel_ERC20);
        _payMediationFeesAndDrawMediators(id_mediation_confirmedPanel_MATIC);
        _payMediationFeesAndDrawMediators(id_mediation_committedVotes_ERC20);
        _payMediationFeesAndDrawMediators(id_mediation_committedVotes_MATIC);

        _confirmPanel(id_mediation_confirmedPanel_ERC20);
        _confirmPanel(id_mediation_confirmedPanel_MATIC);
        _confirmPanel(id_mediation_committedVotes_ERC20);
        _confirmPanel(id_mediation_committedVotes_MATIC);

        _commitVotes(id_mediation_committedVotes_ERC20);
        _commitVotes(id_mediation_committedVotes_MATIC);

    }

    function _getBalance(address _addr, address _paymentToken) public view returns (uint256) {
        if(_paymentToken == address(0)) return _addr.balance;
        else return IERC20(_paymentToken).balanceOf(_addr);
    } 

    function _activatedProject(uint256 _projectId) public returns (uint256) {
        Project memory project = marketplace.getProject(_projectId);
        uint256 value;
        if(project.paymentToken != address(0)) {
            vm.prank(project.provider);
            IERC20(project.paymentToken).approve(address(marketplace), project.providerStake);
        } else {
            value = project.providerStake;
        }
        
        vm.prank(project.provider);
        marketplace.activateProject{value: value}(_projectId);
        return project.projectId;
    }

    function _completedProject(uint256 _projectId) public returns (uint256) {
        Project memory project = marketplace.getProject(_projectId);
        _activatedProject(_projectId);
        vm.prank(project.provider);
        marketplace.completeProject(_projectId);
        return project.projectId;
    }

    function _approvedProject(uint256 _projectId) public returns (uint256) {
        Project memory project = marketplace.getProject(_projectId);
        _completedProject(project.projectId);
        vm.prank(project.buyer);
        marketplace.approveProject(project.projectId);
        return project.projectId;
    }   

    function _challengedProject(uint256 _projectId) public returns (uint256) {
        Project memory project = marketplace.getProject(_projectId);
        _completedProject(project.projectId);
        vm.prank(project.buyer);
        marketplace.challengeProject(
            project.projectId,
            changeOrderAdjustedProjectFee,
            changeOrderProviderStakeForfeit,
            changeOrderDetailsURI
        );
        return project.projectId;
    }
    
    function _project_with_approvedChangeOrder(uint256 _projectId) public returns (uint256) {
        Project memory project = marketplace.getProject(_projectId);
        _challengedProject(project.projectId);
        ChangeOrder memory order = marketplace.getActiveChangeOrder(project.projectId);
        if(order.buyerApproval) {
            vm.prank(project.provider);
        } else {
            vm.prank(project.buyer);
        }
        marketplace.approveChangeOrder(project.projectId);
        return project.projectId;
    }

    // DOES NOT INITIALIZE PROJECT FROM CREATION
    // Advances time past change order period!
    function _disputeProject(uint256 _projectId, uint256 _adjustedFee, uint256 _stakeForfeit) public {
        Project memory project = marketplace.getProject(_projectId);
        require(uint(project.status) == uint(Status.Challenged) || uint(project.status )== uint(Status.Discontinued), "wrong phase");
        vm.warp(block.timestamp + marketplace.CHANGE_ORDER_PERIOD() + 1);
        vm.prank(project.buyer);
        marketplace.disputeProject(
            project.projectId,
            _adjustedFee,
            _stakeForfeit
        );
    }

    // DOES NOT INITIALIZE PROJECT FROM CREATION
    function _payMediationFeesAndDrawMediators(uint256 _projectId) public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(_projectId));
        require(!dispute.feePaidRespondent && !dispute.feePaidClaimant);
        vm.prank(dispute.claimant);
        mediationService.payMediationFee{value: dispute.mediationFee}(dispute.disputeId, evidence1);
        vm.recordLogs();
        vm.prank(dispute.respondent);
        mediationService.payMediationFee{value: dispute.mediationFee}(dispute.disputeId, evidence2);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        uint256 requestId = uint(bytes32(entries[2].data));
        vrf.fulfillRandomWords(requestId, address(mediationService));
    }

    // DOES NOT INITIALIZE PROJECT FROM CREATION
    function _confirmPanel(uint256 _projectId) public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(_projectId));
        require(uint(dispute.phase) == uint(Phase.PanelSelection));
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        require(panel.confirmedMediators.length == 0);
        uint256 mediatorsNeeded = mediationService.mediatorsNeeded(dispute.disputeId);
        uint256 flatFee = mediationService.mediatorFlatFee();
        for(uint i; i < panel.drawnMediators.length; ++i) {
            vm.prank(panel.drawnMediators[i]);
            mediationService.acceptCase{value: flatFee}(dispute.disputeId);
            panel = mediationService.getPanel(dispute.disputeId);
            if(panel.confirmedMediators.length == mediatorsNeeded) break;
        }
    }

    // DOES NOT INITIALIZE PROJECT FROM CREATION
    function _commitVotes(uint256 _projectId) public {
        bytes32 mediator_0_commit = keccak256(abi.encodePacked(true, "someSalt"));
        bytes32 mediator_1_commit = keccak256(abi.encodePacked(true, "someSalt"));
        bytes32 mediator_2_commit = keccak256(abi.encodePacked(false, "someSalt"));
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(_projectId));
        require(uint(dispute.phase) == uint(Phase.Voting));
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        vm.prank(panel.confirmedMediators[0]);
        mediationService.commitVote(dispute.disputeId, mediator_0_commit);
        vm.prank(panel.confirmedMediators[1]);
        mediationService.commitVote(dispute.disputeId, mediator_1_commit);
        vm.prank(panel.confirmedMediators[2]);
        mediationService.commitVote(dispute.disputeId, mediator_2_commit);
    }

    // // DOES NOT INITIALIZE PROJECT FROM CREATION
    // function _renderDecision(uint256 _projectId, bool _vote0, bool _vote1, bool _vote2) public {

    // }

    function _customReveal(uint256 _projectId, bool[] memory _votes, bool _revealVotes) public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(_projectId));
        MediationService.Panel memory panel = mediationService.getPanel(dispute.disputeId);
        require(_votes.length == panel.confirmedMediators.length, "mismatched array sizes");
        for(uint i; i < panel.confirmedMediators.length; ++i) {
            vm.prank(panel.confirmedMediators[i]);
            bytes32 commit = keccak256(abi.encodePacked(_votes[i], "someSalt"));
            mediationService.commitVote(dispute.disputeId, commit);
        }
        if(!_revealVotes) return;
        // if(block.timestamp < dispute.votingStart + mediationService.VOTING_PERIOD()) {
        //     vm.warp(block.timestamp + mediationService.VOTING_PERIOD() + 1);
        // }
        for(uint i; i < panel.confirmedMediators.length; ++i) {
            vm.prank(panel.confirmedMediators[i]);
            mediationService.revealVote(dispute.disputeId, _votes[i], "someSalt");
        }
    }

    function _disclosureToResolved(uint256 _projectInDisclosure, bool _granted) public returns (uint256) {
        Project memory project = marketplace.getProject(_projectInDisclosure);
        require(project.status == Status.Disputed, "project is not disputed");
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(project.projectId));
        require(dispute.phase == Phase.Disclosure, "dispute not in disclosure");
        bool[3] memory voteInputs = [true, false, true];
        if(!_granted) voteInputs = [false, false, true];
        bool[] memory votes = new bool[](voteInputs.length);
        for(uint i; i < voteInputs.length; ++i) {
            votes[i] = voteInputs[i];
        }
        _payMediationFeesAndDrawMediators(project.projectId);
        _confirmPanel(project.projectId);
        _customReveal(project.projectId, votes, true);
        return project.projectId;
    }


    function _labelTestAddresses() public {
        vm.label(address(usdt), "USDT");
        vm.label(address(governor), "Governor");

        vm.label(alice, "alice");
        vm.label(bob,"bob");
        vm.label(carlos, "carlos");
        vm.label(david, "david");
        vm.label(erin, "erin");
        vm.label(frank, "frank");
        vm.label(grace, "grace");
        vm.label(heidi, "heidi");
        vm.label(ivan, "ivan");
        vm.label(judy, "judy");
        vm.label(kim, "kim");
        vm.label(laura, "laura");
        vm.label(mike, "mike");
        vm.label(niaj, "niaj");
        vm.label(olivia, "olivia");
        vm.label(patricia, "patricia");
        vm.label(quentin, "quentin");
        vm.label(russel, "russel");
        vm.label(sean, "sean");
        vm.label(tabitha, "tabitha");
        vm.label(ulrich, "ulrich");
        vm.label(vincent, "vincent");
        vm.label(winona, "winona");
        vm.label(xerxes, "xerxes");
        vm.label(yanni, "yanni");
        vm.label(zorro, "zorro");
        vm.label(admin1, "admin1");
        vm.label(admin2, "admin2");
        vm.label(admin3, "admin3");
        vm.label(admin4, "admin4");
    }

}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

interface MarketplaceIface {
    function calculateNebulaiTxFee(uint256 _projectFee) external view returns (uint256);
    function createProject(
        address _provider,
        address _paymentToken,
        uint256 _projectFee,
        uint256 _providerStake,
        uint256 _dueDate,
        uint256 _reviewPeriodLength,
        string memory _detailsURI
    ) 
        external 
        payable
        returns (uint256); 
    function activateProject(uint256 _projectId) external payable;
    function completeProject(uint256 _projectId) external;
    function approveProject(uint256 _projectId) external;
    function challengeProject(
        uint256 _projectId,
        uint256 _adjustedProjectFee,
        uint256 _providerStakeForfeit,
        string memory _changeOrderDetailsURI 
    ) external;
    function disputeProject(
        uint256 _projectId,
        uint256 _adjustedProjectFee,
        uint256 _providerStakeForfeit
    ) external returns (uint256);
    function getDisputeId(uint256 projectId) external view returns (uint256);
    function projectIds() external view returns (uint256);
}

interface MediationServiceIface {
    function calculateMediationFee(bool isAppeal) external view returns (uint256);
    function payMediationFee(uint256 _disputeId, string[] calldata _evidenceURIs) external payable;
}

interface VRFIface {
    function fulfillRandomWords(uint256 _requestId, address _consumer) external;
}

contract TestProject is Script {
    uint256 projectFee = 100 ether;
    uint256 providerStake = 10 ether;
    string detailsURI = "ipfs://someDetails/";
    uint256 changeOrderProjectFee = 75 ether;
    uint256 changeOrderStakeForfeit = 5 ether;
    string changeOrderDetails = "ipfs://changeOrderURI";
    string[] evidence = ["ipfs://evidence1URI", "ipfs://evidence2URI"];

    uint256 pk_0 = vm.envUint("PK_ANVIL_0");
    uint256 pk_1 = vm.envUint("PK_ANVIL_1");
    address anvil_0 = vm.addr(pk_0);
    address anvil_1 = vm.addr(pk_1);

    string json = vm.readFile("./deploymentInfo.json");
    address marketplaceAddr = vm.parseJsonAddress(json, "MarketplaceAddress");
    address testTokenAddr = vm.parseJsonAddress(json, "TestToken");
    address mediationServiceAddr = vm.parseJsonAddress(json, "MediationServiceAddress");
    address vrfMockAddr = vm.parseJsonAddress(json, "VRFMockAddress");

    MarketplaceIface marketplace = MarketplaceIface(marketplaceAddr);
    IERC20 testToken = IERC20(testTokenAddr);
    MediationServiceIface mediationService = MediationServiceIface(mediationServiceAddr);
    VRFIface vrf = VRFIface(vrfMockAddr);

    function create() public returns (uint256 projectId) {
        vm.startBroadcast(pk_0); 
        uint256 txFee = marketplace.calculateNebulaiTxFee(projectFee);
        testToken.approve(marketplaceAddr, projectFee + txFee);
        projectId = marketplace.createProject(
            anvil_1,
            testTokenAddr,
            projectFee,
            providerStake,
            block.timestamp + 7 days,
            block.timestamp + 2 days,
            detailsURI
        );
        vm.stopBroadcast();
    }

    function activate(uint256 _id) public {
        vm.startBroadcast(pk_1); 
        testToken.approve(marketplaceAddr, providerStake);
        marketplace.activateProject(_id);
        vm.stopBroadcast();
    }

    function complete(uint256 _id) public {
        vm.startBroadcast(pk_1); 
        marketplace.completeProject(_id);
        vm.stopBroadcast();
    }

    function approve(uint256 _id) public {
        vm.startBroadcast(pk_0);
        marketplace.approveProject(_id);
        vm.stopBroadcast();
    }

    function challenge(uint256 _id) public {
        vm.startBroadcast(pk_0); 
        marketplace.challengeProject(_id, changeOrderProjectFee, changeOrderStakeForfeit, changeOrderDetails);
        vm.stopBroadcast();
    }
 
    // !!!! ADVANCE TIME BEFORE CALLING
    function dispute(uint256 _id) public {
        vm.startBroadcast(pk_0);
        marketplace.disputeProject(_id,changeOrderProjectFee, changeOrderStakeForfeit);
        vm.stopBroadcast();
    }

    function payFees(uint256 _id) public {
        uint256 mediationFee = mediationService.calculateMediationFee(false);
        uint256 disputeId = marketplace.getDisputeId(_id);
        vm.startBroadcast(pk_0);
        mediationService.payMediationFee{value: mediationFee}(disputeId, evidence);
        vm.stopBroadcast();
        vm.startBroadcast(pk_1);
        vm.recordLogs();
        mediationService.payMediationFee{value: mediationFee}(disputeId, evidence);
        VmSafe.Log[] memory entries = vm.getRecordedLogs(); 
        // console.log(uint(bytes32(entries[1].data)));
        // console.log(uint(bytes32(entries[2].data)));
        uint256 requestId = uint(bytes32(entries[2].data));
        vrf.fulfillRandomWords(requestId, mediationServiceAddr);
        vm.stopBroadcast();
    }

    function allTheWayToChallenge() public returns (uint256) {
        vm.startBroadcast(pk_0); 
        uint256 txFee = marketplace.calculateNebulaiTxFee(projectFee);
        testToken.approve(marketplaceAddr, projectFee + txFee);
        uint256 projectId = marketplace.createProject(
            anvil_1,
            testTokenAddr,
            projectFee,
            providerStake,
            block.timestamp + 7 days,
            block.timestamp + 2 days,
            detailsURI
        );
        vm.stopBroadcast();

        vm.startBroadcast(pk_1); 
        testToken.approve(marketplaceAddr, providerStake);
        marketplace.activateProject(projectId);

        testToken.approve(marketplaceAddr, providerStake);
        marketplace.completeProject(projectId);
        vm.stopBroadcast();

        vm.startBroadcast(pk_0); 
        marketplace.challengeProject(projectId, changeOrderProjectFee, changeOrderStakeForfeit, changeOrderDetails);
        vm.stopBroadcast();

        return projectId;
    }

    function startMediation(uint256 _projectId) public {
        vm.startBroadcast(pk_0);
        marketplace.disputeProject(_projectId,changeOrderProjectFee, changeOrderStakeForfeit);
        vm.stopBroadcast();

        uint256 mediationFee = mediationService.calculateMediationFee(false);
        uint256 disputeId = marketplace.getDisputeId(_projectId);
        vm.startBroadcast(pk_0);
        mediationService.payMediationFee{value: mediationFee}(disputeId, evidence);
        vm.stopBroadcast();
        vm.startBroadcast(pk_1);
        vm.recordLogs();
        mediationService.payMediationFee{value: mediationFee}(disputeId, evidence);
        VmSafe.Log[] memory entries = vm.getRecordedLogs(); 
        uint256 requestId = uint(bytes32(entries[2].data));
        vrf.fulfillRandomWords(requestId, mediationServiceAddr);
        vm.stopBroadcast();
    }

    function aFewMore() public {
        uint256 id = create();
        activate(id);
        id = create();
        activate(id);
        complete(id);
        id = create();
        activate(id);
        complete(id);
        approve(id);
        id = create();
        activate(id);
        complete(id);
        challenge(id);
    }
       
}
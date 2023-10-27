// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
    function payMediationFee(uint256 _petitionId, string[] calldata _evidenceURIs) external payable;
}

interface VRFIface {
    function fulfillRandomWords(uint256 _requestId, address _consumer) external;
}

contract TestProjectStorage is Script {

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
    address mediationserviceAddr = vm.parseJsonAddress(json, "MediationServiceAddress");
    address vrfMockAddr = vm.parseJsonAddress(json, "VRFMockAddress");

    MarketplaceIface marketplace = MarketplaceIface(marketplaceAddr);
    IERC20 testToken = IERC20(testTokenAddr);
    MediationServiceIface mediationservice = MediationServiceIface(mediationserviceAddr);
    VRFIface vrf = VRFIface(vrfMockAddr);
}

contract CreateTestProjects is Script, TestProjectStorage {


    function run() public {

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
        vm.startBroadcast(pk_1); // activate and complete
        testToken.approve(marketplaceAddr, providerStake);
        marketplace.activateProject(projectId);
        marketplace.completeProject(projectId);
        vm.stopBroadcast();
        vm.startBroadcast(pk_0); // challenge
        marketplace.challengeProject(projectId, changeOrderProjectFee, changeOrderStakeForfeit, changeOrderDetails);
        vm.stopBroadcast();
    }
}

contract InitiateMediation is Script, TestProjectStorage {

    // make sure block timestamp has been advanced in anvil!

    uint256 latestProjectId = marketplace.projectIds();

    function run() public {
        vm.startBroadcast(pk_0);
        marketplace.disputeProject(
            latestProjectId,
            changeOrderProjectFee, 
            changeOrderStakeForfeit
        );
        vm.stopBroadcast();
    }
}

contract PayMediationFees is Script, TestProjectStorage {

    uint256 latestProjectId = marketplace.projectIds();

    function run() public {
        uint256 mediationFee = mediationservice.calculateMediationFee(false);
        uint256 petitionId = marketplace.getDisputeId(latestProjectId);
        vm.startBroadcast(pk_0);
        mediationservice.payMediationFee{value: mediationFee}(petitionId, evidence);
        vm.stopBroadcast();
        vm.startBroadcast(pk_1);
        mediationservice.payMediationFee{value: mediationFee}(petitionId, evidence);
        // VmSafe.Log[] memory entries = vm.getRecordedLogs(); 
        // uint256 requestId = uint(bytes32(entries[1].));
        // // uint256 requestId = uint(bytes32(entries[2].data));
        vm.stopBroadcast();

        vm.startBroadcast(pk_0);
        vrf.fulfillRandomWords(latestProjectId, mediationserviceAddr);
        vm.stopBroadcast();
    }
}





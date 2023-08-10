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
    function getArbitrationPetitionId(uint256 projectId) external view returns (uint256);
    function projectIds() external view returns (uint256);
}

interface CourtIface {
    function calculateArbitrationFee(bool isAppeal) external view returns (uint256);
    function payArbitrationFee(uint256 _petitionId, string[] calldata _evidenceURIs) external payable;
}

interface VRFIface {
    function fulfillRandomWords(uint256 _requestId, address _consumer) external;
}

contract TestProjectStorage is Script {

    uint256 projectFee = 100 ether;
    uint256 providerStake = 10 ether;
    string detailsURI = "someURI";
    uint256 changeOrderProjectFee = 75 ether;
    uint256 changeOrderStakeForfeit = 5 ether;
    string changeOrderDetails = "changeOrderURI";
    string[] evidence = ["evidence1URI", "evidence2URI"];

    uint256 pk_0 = vm.envUint("PK_ANVIL_0");
    uint256 pk_1 = vm.envUint("PK_ANVIL_1");
    address anvil_0 = vm.addr(pk_0);
    address anvil_1 = vm.addr(pk_1);

    string json = vm.readFile("./deploymentInfo.json");
    bytes marketplaceJSON = vm.parseJson(json, "MarketplaceAddress");
    bytes testTokenJSON = vm.parseJson(json, "TestToken");
    bytes courtJSON = vm.parseJson(json, "CourtAddress");
    bytes vrfJSON = vm.parseJson(json, "VRFMockAddress");
    address marketplaceAddr = bytesToAddress(marketplaceJSON);
    address testTokenAddr = bytesToAddress(testTokenJSON);
    address courtAddr = bytesToAddress(courtJSON);
    address vrfMockAddr = bytesToAddress(vrfJSON);

    MarketplaceIface marketplace = MarketplaceIface(marketplaceAddr);
    IERC20 testToken = IERC20(testTokenAddr);
    CourtIface court = CourtIface(courtAddr);
    VRFIface vrf = VRFIface(vrfMockAddr);

    function bytesToAddress(bytes memory bys) private pure returns (address addr) {
        assembly {
            addr := mload(add(bys, 32))
        } 
    }
}

contract CreateTestProjects is Script, TestProjectStorage {


    function run() public {

        // vm.startBroadcast(pk_0); // create project (will stay as "Created Status")
        // uint256 txFee = marketplace.calculateNebulaiTxFee(projectFee);
        // testToken.approve(marketplaceAddr, projectFee + txFee);
        // uint256 projectId = marketplace.createProject(
        //     anvil_1,
        //     testTokenAddr,
        //     projectFee,
        //     providerStake,
        //     block.timestamp + 7 days,
        //     block.timestamp + 2 days,
        //     detailsURI
        // );
        // vm.stopBroadcast();

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

contract InitiateArbitration is Script, TestProjectStorage {

    // make sure block timestamp has been advanced in anvil!

    uint256 latestProjectId = marketplace.projectIds();

    function run() public {
        vm.startBroadcast(pk_0);
        marketplace.disputeProject(
            // 1,
            latestProjectId,
            changeOrderProjectFee, 
            changeOrderStakeForfeit
        );
        vm.stopBroadcast();
    }
}

contract PayArbitrationFees is Script, TestProjectStorage {

    uint256 latestProjectId = marketplace.projectIds();

    function run() public {
        uint256 arbitrationFee = court.calculateArbitrationFee(false);
        uint256 petitionId = marketplace.getArbitrationPetitionId(latestProjectId);
        vm.startBroadcast(pk_0);
        court.payArbitrationFee{value: arbitrationFee}(petitionId, evidence);
        vm.stopBroadcast();
        vm.startBroadcast(pk_1);
        court.payArbitrationFee{value: arbitrationFee}(petitionId, evidence);
        // VmSafe.Log[] memory entries = vm.getRecordedLogs(); 
        // uint256 requestId = uint(bytes32(entries[1].));
        // // uint256 requestId = uint(bytes32(entries[2].data));
        vm.stopBroadcast();

        vm.startBroadcast(pk_0);
        vrf.fulfillRandomWords(latestProjectId, courtAddr);
        vm.stopBroadcast();
    }
}





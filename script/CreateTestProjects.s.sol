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
}

contract CreateTestProjects is Script {

    uint256 projectFee = 100 ether;
    uint256 providerStake = 10 ether;
    string detailsURI = "someURI";
    uint256 changeOrderProjectFee = 75 ether;
    uint256 changeOrderStakeForfeit = 5 ether;
    string changeOrderDetails = "changeOrderURI";

    uint256 pk_0 = vm.envUint("PK_ANVIL_0");
    uint256 pk_1 = vm.envUint("PK_ANVIL_1");
    address anvil_0 = vm.addr(pk_0);
    address anvil_1 = vm.addr(pk_1);

    string json = vm.readFile("./deploymentInfo.json");
    bytes marketplaceJSON = vm.parseJson(json, "MarketplaceAddress");
    bytes testTokenJSON = vm.parseJson(json, "TestToken");
    address marketplaceAddr = bytesToAddress(marketplaceJSON);
    address testTokenAddr = bytesToAddress(testTokenJSON);

    MarketplaceIface marketplace = MarketplaceIface(marketplaceAddr);
    IERC20 testToken = IERC20(testTokenAddr);

    function bytesToAddress(bytes memory bys) private pure returns (address addr) {
        assembly {
            addr := mload(add(bys, 32))
        } 
    }

    function run() public {

        vm.startBroadcast(pk_0); // create project (will stay as "Created Status")
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

        vm.startBroadcast(pk_0); // create another project 
        txFee = marketplace.calculateNebulaiTxFee(projectFee);
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





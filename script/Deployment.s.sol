// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import "../src/Governor.sol";
import "../src/Treasury.sol";

contract DeploymentScript is Script {

    Governor public governor;
    Treasury public treasury;

    address[] public admins = [
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // localhost
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8, // localhost
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC // localhost
        // 0x537Df8463a09D0370DeE4dE077178300340b0030, // mumbai
        // 0xe540A4E03adeFB734ecE9d67E1A86199ee907Caa, // mumbai
        // 0x298334B4895392b0BA15261194cF1642A4adf9Fc // mumbai
    ];
    uint256 public sigsRequired = 2;
    
    address[] public issuers = [
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // localhost
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8 // localhost
        // 0x537Df8463a09D0370DeE4dE077178300340b0030, // mumbai
        // 0xe540A4E03adeFB734ecE9d67E1A86199ee907Caa, // mumbai
    ];

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        // deploy governor
        governor = new Governor(admins, sigsRequired);
        // deploy treasury
        treasury = new Treasury(address(governor));
        
        vm.stopBroadcast();

        string memory obj1 = "some key";
        string memory govAddr = vm.serializeAddress(obj1, "GovernorAddress", address(governor));
        string memory treasuryAddr = vm.serializeAddress(obj1, "TreasuryAddress", address(treasury));

        vm.writeJson(govAddr, "./deploymentInfo.json");
        vm.writeJson(treasuryAddr, "./deploymentInfo.json");
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IGov {
    function proposeTransaction(address _to, uint256 _value, bytes calldata _data) external returns (uint256); 
}

contract DummyGov is Script {

    string json = vm.readFile("json_out/deployedAddresses.json");
    address governorAddr = vm.parseJsonAddress(json, ".anvil.Governor");
    address mediatorPoolAddr = vm.parseJsonAddress(json, ".anvil.MediatorPool");
    IGov governor = IGov(governorAddr);
    uint256 pk_0 = vm.envUint("PK_ANVIL_0");
    uint256 pk_1 = vm.envUint("PK_ANVIL_1");
    address newAdmin = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
    address admin1 = vm.addr(pk_0);

    function run() public {
        // console.log(json);
        // console.log(governorAddr);
        // console.log(mediatorPoolAddr);

        bytes memory data1 = abi.encodeWithSignature("changeSignaturesRequired(uint256)", 2);
        vm.startBroadcast(pk_0);
        uint256 txIndex1 = governor.proposeTransaction(governorAddr, 0, data1);
        console.log("transaction proposed - tx index: ", txIndex1);
        vm.stopBroadcast();
        
        bytes memory data2 = abi.encodeWithSignature("addAdmin(address)", newAdmin);
        vm.startBroadcast(pk_1);
        uint256 txIndex2 = governor.proposeTransaction(governorAddr, 0, data2);
        console.log("transaction proposed - tx index: ", txIndex2);
        vm.stopBroadcast();

        bytes memory data3 = abi.encodeWithSignature("withdrawMediationReserve(address,uint256)", admin1, 2 ether);
        vm.startBroadcast(pk_0);
        uint256 txIndex3 = governor.proposeTransaction(mediatorPoolAddr, 0, data3);
        console.log("transaction proposed - tx index: ", txIndex3);
        vm.stopBroadcast();
        
    }
}
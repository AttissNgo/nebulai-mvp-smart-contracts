// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IPool {
    function registerMediator(address _mediator) external;
}

contract RegisterMediators is Script {

    string json = vm.readFile("json_out/deployedAddresses.json");
    address mediatorPoolAddr = vm.parseJsonAddress(json, ".polygon.MediatorPool");
    IPool mediatorPool = IPool(mediatorPoolAddr);
    uint256 pk_0 = vm.envUint("PK_ANVIL_0");

    address[] mediators = [
        0xF5a3bC964CBD8CFBb40aFf2c70a39E2A2a271aA4, // Renatto
        0x066d662Ae81b864657f1a70d45052016d4c4D4fD, // Renatto
        0x2F8F28bFb7cC0b4a9A28E19d3f86279a7e54C6F8, // Spencer
        0xCEA03A0b856501EE12aDff18ee8A551B120195b4, // Spencer
        0x17D9EE43a1d1f6CBAA9a4E59C54F074f2682a0C5, // Stefano
        0x49EbaCB3A99E262977d8B16e51a4309a361F5362, // Stefano
        0x537Df8463a09D0370DeE4dE077178300340b0030, // Attiss
        0xe540A4E03adeFB734ecE9d67E1A86199ee907Caa, // Attiss
        0x298334B4895392b0BA15261194cF1642A4adf9Fc, // Attiss
        0xaBe12036bCba9566B99e60BE32598b3F53F525f0 // Shanmukhi
    ];

    function run() public {
        vm.startBroadcast(pk_0);
        for (uint i; i < mediators.length; ++i) {
            mediatorPool.registerMediator(mediators[i]);
        }
        vm.stopBroadcast();
    }

}
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";

contract JuryPoolTest is Test, TestSetup {

    function setUp() public {
        _setUp();
        _whitelistUsers();
    }

    function test_registerAsJuror() public {
        
    }

}
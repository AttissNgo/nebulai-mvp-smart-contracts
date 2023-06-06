// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";

contract EnvironmentTest is Test, TestSetup {

    uint256 initialNebMint = 10000000 ether;

    function setUp() public {
        _deployContracts();
    }

    function test_deployment() public {
        assertEq(nebToken.totalSupply(), initialNebMint);
        // treasury now holds all NEB
        assertEq(nebToken.balanceOf(address(treasury)), initialNebMint);
        // issuers are set in reward token
        assertEq(rewardToken.isIssuer(issuer), true);
        assertEq(rewardToken.isIssuer(issuer2), true);
    }
    
}
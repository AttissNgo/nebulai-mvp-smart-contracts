// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";

contract TreasuryTest is Test, TestSetup {

    function setUp() public {
        _setUp();
    }

    function test_transferTokens() public {
        uint256 amount = 42 ether;
        uint256 aliceBalBefore = usdt.balanceOf(alice);
        uint256 treasuryBalBefore = usdt.balanceOf(address(treasury));
        bytes memory data = abi.encodeWithSignature(
            "transferTokens(address,uint256,address)", 
            alice,
            amount,
            address(usdt)
        );
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(treasury), 0, data);
        util_executeGovernorTx(txIndex);
        assertEq(usdt.balanceOf(alice), aliceBalBefore + amount);
        assertEq(usdt.balanceOf(address(treasury)), treasuryBalBefore - amount);
    }

    function test_transferNative() public {
        uint256 amount = 42 ether;
        vm.deal(address(treasury), amount);
        uint256 aliceBalBefore = alice.balance;
        bytes memory data = abi.encodeWithSignature(
            "transferNative(address,uint256)", 
            alice,
            amount
        );
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(treasury), 0, data);
        util_executeGovernorTx(txIndex);
        assertEq(alice.balance, aliceBalBefore + amount);
        assertEq(address(treasury).balance, 0);
    }

}
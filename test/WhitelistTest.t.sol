// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";

contract WhitelistTest is Test, TestSetup {

    event Whitelisted(address indexed user);

    function setUp() public {
        _setUp();
    }

    function test_modifier_onlyAdmin() public {
        assertEq(governor.isAdmin(alice), false);
        vm.expectRevert(Whitelist.Whitelist__OnlyAdmin.selector);
        vm.prank(alice);
        whitelist.approveAddress(alice);
    }

    function test_approveAddress() public {
        assertEq(whitelist.isApproved(alice), false);
        vm.prank(admin1);
        vm.expectEmit(true, false, false, false);
        emit Whitelisted(alice);
        whitelist.approveAddress(alice);
        assertEq(whitelist.isApproved(alice), true);
    }

    function test_approveAddress_revert() public {
        test_approveAddress(); // alice is approved
        vm.expectRevert(Whitelist.Whitelist__AlreadyApproved.selector);
        vm.prank(admin1);
        whitelist.approveAddress(alice);
    }

    function test_revokeApproval() public {
        test_approveAddress(); // alice is approved
        bytes memory data = abi.encodeWithSignature(
            "revokeApproval(address)",
            alice
        );
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(whitelist), 0, data);
        util_executeGovernorTx(txIndex);
        assertEq(whitelist.isApproved(alice), false);
    }

    function test_revokeApproval_reverts() public {
        assertEq(whitelist.isApproved(alice), false);
        bytes memory data = abi.encodeWithSignature(
            "revokeApproval(address)",
            alice
        );
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(whitelist), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        vm.expectRevert();
        vm.prank(admin3);
        governor.signTransaction(txIndex);
    }


}
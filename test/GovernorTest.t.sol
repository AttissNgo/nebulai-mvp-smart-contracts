// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";

contract GovernorTest is Test, TestSetup {

    address[] public duplicateAdmin = [admin1, admin2, admin3, admin4, admin2];
    address[] public zeroAddr = [admin1, admin2, admin3, admin4, address(0)];
    uint256 public dummyValue1 = 100 ether;
    bytes public dummyData1;

    event TransactionProposed(
        uint256 txIndex,
        address to,
        uint256 value,
        bytes data,
        address proposedBy
    );
    event TransactionSigned(uint256 txIndex, address admin, uint256 numSignatures);
    event TransactionExecuted(uint256 txIndex, address to, uint256 value, bytes data);
    event SignatureRevoked(uint256 txIndex, address admin, uint256 numSignatures);
    event TransactionCancelled(uint256 txIndex);
    event AdminAdded(address newAdmin);
    event AdminRemoved(address adminRemoved);
    event SignaturesRequiredChanged(uint256 signaturesRequired);

    function setUp() public {
        _setUp();
    }

    function _txWithTwoSigs() public returns (uint256) {
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(
            alice,
            dummyValue1,
            dummyData1
        );
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        return txIndex;
    }

    function test_governor_deployment() public {
        for(uint i = 0; i < admins.length; ++i) {
            assertEq(governor.admins(i), admins[i]);
            assertEq(governor.isAdmin(admins[i]), true);
        }
        assertEq(governor.signaturesRequired(), sigsRequired);
    }

    function test_addAdmin_revert() public {
        // duplicate address
        vm.expectRevert(Governor.Governor__DuplicateAdminAddress.selector);
        new Governor(duplicateAdmin, 2);
        // zero address
        vm.expectRevert(Governor.Governor__ZeroAddress.selector);
        new Governor(zeroAddr, 2);
        // too many sigs required
        vm.expectRevert(Governor.Governor__TooManySignaturesRequired.selector);
        new Governor(admins, admins.length + 1);
        // too few sigs required
        vm.expectRevert(Governor.Governor__TooFewSignaturesRequired.selector);
        new Governor(admins, 1);
    }

    function test_modifiers() public {
        // only admin
        vm.expectRevert(Governor.Governor__OnlyAdmin.selector);
        vm.prank(alice);
        governor.proposeTransaction(
            alice,
            dummyValue1,
            dummyData1
        );
        // only active
        uint256 txIndex = test_cancelTransaction();
        vm.expectRevert(Governor.Governor__TransactionNotActive.selector);
        vm.prank(admin4);
        governor.signTransaction(txIndex);
        // only governor
        vm.expectRevert(Governor.Governor__OnlyGovernor.selector);
        vm.prank(admin1);
        governor.changeSignaturesRequired(2);
    }

    function test_proposeTransaction() public returns (uint256) {
        vm.prank(admin1);
        vm.expectEmit(false, false, false, true);
        emit TransactionProposed(0, alice, dummyValue1, dummyData1, admin1);
        vm.expectEmit(false, false, false, true);
        emit TransactionSigned(0, admin1, 1);
        uint256 txIndex = governor.proposeTransaction(
            alice,
            dummyValue1,
            dummyData1
        );
        Governor.Transaction memory t = governor.getTransaction(txIndex);
        assertEq(t.to, alice);
        assertEq(t.value, dummyValue1);
        assertEq(t.data, dummyData1);
        assertEq(t.proposedBy, admin1);
        assertEq(t.active, true);
        assertEq(t.executed, false);
        assertEq(t.numSignatures, 1); // automatically signed by proposer
        assertEq(governor.adminHasSigned(txIndex, admin1), true);
        return txIndex;
    }

    function test_signTransaction() public returns (uint256){
        uint256 txIndex = test_proposeTransaction();
        vm.expectEmit(false, false, false, true);
        emit TransactionSigned(0, admin2, 2);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        Governor.Transaction memory t = governor.getTransaction(txIndex);
        assertEq(t.numSignatures, 2);
        assertEq(governor.adminHasSigned(txIndex, admin2), true);
        return txIndex;
    }

    function test_signTransaction_revert() public {
        uint256 txIndex = test_proposeTransaction();
        assertEq(governor.adminHasSigned(txIndex, admin1), true);
        vm.expectRevert(Governor.Governor__DuplicateSignature.selector);
        vm.prank(admin1);
        governor.signTransaction(txIndex);
    }

    function test_executeTransaction() public {
        // testing automatic execution upon enough sigs
        uint256 txIndex = _txWithTwoSigs(); 
        Governor.Transaction memory t = governor.getTransaction(txIndex);
        vm.deal(address(governor), t.value);
        uint256 recipientBalBefore = t.to.balance;
        vm.expectEmit(true, true, true, true);
        emit TransactionExecuted(txIndex, t.to, t.value, t.data);
        vm.prank(admin3);
        governor.signTransaction(txIndex);
        t = governor.getTransaction(txIndex);
        assertEq(t.executed, true);
        assertEq(t.active, false);
        assertEq(t.numSignatures, 3);
        assertEq(t.to.balance, recipientBalBefore + t.value);
        assertEq(address(governor).balance, 0);
    }

    function test_executeTransaction_revert() public {
        // insufficient sigs
        uint256 txIndex = _txWithTwoSigs(); 
        vm.expectRevert(Governor.Governor__InsufficientSignatures.selector);
        vm.prank(admin1);
        governor.executeTransaction(txIndex);
    }

    function test_executeTransaction_manual() public {
        uint256 txIndex1 = _txWithTwoSigs(); 
        Governor.Transaction memory t = governor.getTransaction(txIndex1);
        vm.deal(address(governor), t.value);
        assertEq(t.numSignatures, 2);
        assertEq(governor.signaturesRequired(), 3);
        bytes memory data = abi.encodeWithSignature("changeSignaturesRequired(uint256)", 2);
        vm.prank(admin1);
        uint256 txIndex2 = governor.proposeTransaction(address(governor), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex2);
        vm.prank(admin3);
        governor.signTransaction(txIndex2);
        assertEq(governor.signaturesRequired(), 2);
        vm.prank(admin1);
        governor.executeTransaction(txIndex1);
        t = governor.getTransaction(txIndex1);
        assertEq(t.executed, true);
    }

    function test_revokeSignature() public {
        uint256 txIndex = _txWithTwoSigs(); 
        Governor.Transaction memory t = governor.getTransaction(txIndex);
        uint256 numSigs = t.numSignatures;
        vm.expectEmit(true, true, true, true);
        emit SignatureRevoked(txIndex, admin1, numSigs - 1);
        vm.prank(admin1);
        governor.revokeSignature(txIndex);
        t = governor.getTransaction(txIndex);
        assertEq(t.numSignatures, numSigs - 1);
        assertEq(governor.adminHasSigned(txIndex, admin1), false);
    }

    function test_revokeSignature_revert() public {
        uint256 txIndex = _txWithTwoSigs(); 
        assertEq(governor.adminHasSigned(txIndex, admin4), false);
        vm.expectRevert(Governor.Governor__UserHasNotSigned.selector);
        vm.prank(admin4);
        governor.revokeSignature(txIndex);
    }

    function test_cancelTransaction() public returns (uint256) {
        uint256 txIndex = _txWithTwoSigs(); // proposed by admin 1
        vm.expectEmit(true, false, false, false);
        emit TransactionCancelled(txIndex);
        vm.prank(admin1);
        governor.cancelTransaction(txIndex);
        Governor.Transaction memory t = governor.getTransaction(txIndex);
        assertEq(t.active, false);
        return txIndex;
    }

    function test_cancelTransaction_revert() public {
        uint256 txIndex = _txWithTwoSigs(); // proposed by admin 1
        vm.expectRevert(Governor.Governor__OnlyProposerCanCancel.selector);
        vm.prank(admin3);
        governor.cancelTransaction(txIndex);
    }

    function test_addAdmin() public {
        assertEq(governor.isAdmin(alice), false);
        bytes memory data = abi.encodeWithSignature("addAdmin(address)", alice);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        vm.expectEmit(true, true, false, false);
        emit AdminAdded(alice);
        vm.prank(admin3);
        governor.signTransaction(txIndex);
        assertEq(governor.isAdmin(alice), true);
    }

    function test_removeAdmin() public {
        assertEq(governor.isAdmin(admin4), true);
        bytes memory data = abi.encodeWithSignature("removeAdmin(address)", admin4);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        vm.expectEmit(false, false, false, true);
        emit AdminRemoved(admin4);
        vm.prank(admin3);
        governor.signTransaction(txIndex);
        assertEq(governor.isAdmin(admin4), false);
    }

    function test_removeAdmin_signatures_required_overflow() public {
        bytes memory sigsData = abi.encodeWithSignature("changeSignaturesRequired(uint256)", 4);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(governor), 0,sigsData);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        vm.prank(admin3);
        governor.signTransaction(txIndex);
        assertEq(governor.signaturesRequired(), 4);
        assertEq(governor.getAdmins().length, 4);
        // now requires unanimous approval (4 sigs). If admin is removed, sigs should be reduced to 3.
        bytes memory removeData = abi.encodeWithSignature("removeAdmin(address)", admin4);
        vm.prank(admin1);
        txIndex = governor.proposeTransaction(address(governor), 0, removeData);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        vm.prank(admin3);
        governor.signTransaction(txIndex);
        vm.prank(admin4);
        governor.signTransaction(txIndex);
        assertEq(governor.signaturesRequired(), 3);
    }

    function test_removeAdmin_revert() public {
        // not admin
        assertEq(governor.isAdmin(alice), false);
        bytes memory data = abi.encodeWithSignature("removeAdmin(address)", alice);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        vm.expectRevert(Governor.Governor__TransactionFailed.selector);
        vm.prank(admin3);
        governor.signTransaction(txIndex);
        // too few admins
            // set sigs to 2
        data = abi.encodeWithSignature("changeSignaturesRequired(uint256)", 2);
        vm.prank(admin1);
        txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        vm.prank(admin3);
        governor.signTransaction(txIndex);
        assertEq(governor.signaturesRequired(), 2);
            // remove admin3 & admin4
        data = abi.encodeWithSignature("removeAdmin(address)", admin4);
        vm.prank(admin1);
        txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        assertEq(governor.isAdmin(admin4), false);
        data = abi.encodeWithSignature("removeAdmin(address)", admin3);
        vm.prank(admin1);
        txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        assertEq(governor.isAdmin(admin3), false);
        assertEq(governor.getAdmins().length, 2);
            // try to remove admin2
        data = abi.encodeWithSignature("removeAdmin(address)", admin2);
        vm.prank(admin1);
        txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.expectRevert(Governor.Governor__TransactionFailed.selector);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
    }

    function test_changeSignaturesRequired() public {
        assertEq(governor.signaturesRequired(), 3);
        bytes memory data = abi.encodeWithSignature("changeSignaturesRequired(uint256)", 4);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(governor), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        vm.expectEmit(true, false, false, false);
        emit SignaturesRequiredChanged(4);
        vm.prank(admin3);
        governor.signTransaction(txIndex);
        assertEq(governor.signaturesRequired(), 4);
    }

}
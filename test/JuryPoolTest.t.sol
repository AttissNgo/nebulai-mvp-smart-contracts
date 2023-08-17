// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";

contract JuryPoolTest is Test, TestSetup {

    event JurorRegistered(address indexed juror);
    event JurorPaused(address indexed juror);
    event JurorReactivated(address indexed juror);
    event JurorSuspended(address indexed juror);
    event StakeWithdrawn(address indexed juror, uint256 withdrawAmount, uint256 totalStake);
    event Staked(address indexed juror, uint256 stakeAmount, uint256 totalStake);
    event JuryReserveFunded(uint256 amount, address from);
    event JuryReserveWithdrawn(address recipient, uint256 amount);

    function setUp() public {
        _setUp();
        _whitelistUsers();
    }

    function test_registerAsJuror() public {
        assertEq(juryPool.isJuror(alice), false);
        uint256 contractBalBefore = address(juryPool).balance;
        uint256 poolSizeBefore = juryPool.juryPoolSize();
        uint256 minStake = juryPool.minimumStake();
        uint256 stakeBefore = juryPool.getJurorStake(alice);
        vm.expectEmit(true, false, false, false);
        emit JurorRegistered(alice);
        vm.prank(alice);
        juryPool.registerAsJuror{value: minStake}();
        assertEq(juryPool.getJurorStake(alice), stakeBefore + minStake);
        assertEq(juryPool.isJuror(alice), true);
        assertEq(juryPool.juryPoolSize(), poolSizeBefore + 1);
        assertEq(address(juryPool).balance, contractBalBefore + minStake);
        assertEq(uint(juryPool.getJurorStatus(alice)), uint(JuryPool.JurorStatus.Active));
    }

    function test_registerAsJuror_reverts() public {
        // minimum stake not met
        uint256 minStake = juryPool.minimumStake();
        vm.expectRevert(JuryPool.JuryPool__MinimumStakeNotMet.selector);
        vm.prank(alice);
        juryPool.registerAsJuror{value: minStake - 1}();
        // setup - alice registers
        vm.prank(alice);
        juryPool.registerAsJuror{value: minStake}();
        // already registered
        assertEq(juryPool.isJuror(alice), true);
        vm.expectRevert(JuryPool.JuryPool__AlreadyRegistered.selector);
        vm.prank(alice);
        juryPool.registerAsJuror{value: minStake}();
    }

    function test_pauseJuror() public {
        // setup - alice registers as juror
        uint256 minStake = juryPool.minimumStake();
        vm.prank(alice);
        juryPool.registerAsJuror{value: minStake}();
        assertEq(uint(juryPool.getJurorStatus(alice)), uint(JuryPool.JurorStatus.Active));
        // alice pauses
        vm.expectEmit(true, false, false, false);
        emit JurorPaused(alice);
        vm.prank(alice);
        juryPool.pauseJuror();
        assertEq(uint(juryPool.getJurorStatus(alice)), uint(JuryPool.JurorStatus.Paused));
    }

    function test_pauseJuror_revert() public {
        // not registered
        assertEq(juryPool.isJuror(bob), false);
        vm.expectRevert(JuryPool.JuryPool__NotRegistered.selector);
        vm.prank(bob);
        juryPool.pauseJuror();
        // setup - alice registers, then pauses
        uint256 minStake = juryPool.minimumStake();
        vm.prank(alice);
        juryPool.registerAsJuror{value: minStake}();
        vm.prank(alice);
        juryPool.pauseJuror();
        // not active
        vm.expectRevert(JuryPool.JuryPool__JurorNotActive.selector);
        vm.prank(alice);
        juryPool.pauseJuror();
    }

    function test_reactivateJuror() public {
        // setup - alice registers, then pauses 
        uint256 minStake = juryPool.minimumStake();
        vm.prank(alice);
        juryPool.registerAsJuror{value: minStake}();
        vm.prank(alice);
        juryPool.pauseJuror();
        // alice reactivates
        vm.expectEmit(true, false, false, false);
        emit JurorReactivated(alice);
        vm.prank(alice);
        juryPool.reactivateJuror();
        assertEq(uint(juryPool.getJurorStatus(alice)), uint(JuryPool.JurorStatus.Active));
    }

    function test_reactivateJuror_reverts() public {
        // setup - alice registers
        uint256 minStake = juryPool.minimumStake();
        vm.prank(alice);
        juryPool.registerAsJuror{value: minStake}();
        // already active
        vm.expectRevert(JuryPool.JuryPool__JurorAlreadyActive.selector);
        vm.prank(alice);
        juryPool.reactivateJuror();
        // suspended
        vm.prank(admin1);
        bytes memory data = abi.encodeWithSignature("suspendJuror(address)", alice);
        uint256 txIndex = governor.proposeTransaction(address(juryPool), 0, data);
        util_executeGovernorTx(txIndex);
        vm.expectRevert(JuryPool.JuryPool__JurorSuspended.selector);
        vm.prank(alice);
        juryPool.reactivateJuror();
    }

    function test_stake() public {
        // setup - alice registers
        uint256 minStake = juryPool.minimumStake();
        vm.prank(alice);
        juryPool.registerAsJuror{value: minStake}();
        uint256 stakeBefore = juryPool.getJurorStake(alice);
        // alice stakes more
        uint256 stakeAmount = 10 ether;
        vm.expectEmit(true, false, false, true);
        emit Staked(alice, stakeAmount, stakeBefore + stakeAmount);
        vm.prank(alice);
        juryPool.stake{value: stakeAmount}();
        assertEq(juryPool.getJurorStake(alice), stakeBefore + stakeAmount);
    }

    function test_withdrawStake() public {
        // setup - alice registers
        uint256 minStake = juryPool.minimumStake();
        vm.prank(alice);
        juryPool.registerAsJuror{value: minStake}();
        uint256 stakeBefore = juryPool.getJurorStake(alice);
        uint256 aliceBalBefore = alice.balance;
        // withdraw
        vm.expectEmit(true, false, false, true);
        emit StakeWithdrawn(alice, minStake, 0);
        vm.prank(alice); 
        juryPool.withdrawStake(minStake);
        assertEq(juryPool.getJurorStake(alice), stakeBefore - minStake);
        assertEq(alice.balance, aliceBalBefore + minStake);
    }

    function test_withdrawStake_revert() public {
        // setup - alice registers
        uint256 minStake = juryPool.minimumStake();
        vm.prank(alice);
        juryPool.registerAsJuror{value: minStake}();
        // insufficient stake
        vm.expectRevert(JuryPool.JuryPool__InsufficientStake.selector);
        vm.prank(alice); 
        juryPool.withdrawStake(minStake + 1);
        // juror suspended 
        vm.prank(admin1);
        bytes memory data = abi.encodeWithSignature("suspendJuror(address)", alice);
        uint256 txIndex = governor.proposeTransaction(address(juryPool), 0, data);
        util_executeGovernorTx(txIndex);
        vm.expectRevert(JuryPool.JuryPool__JurorSuspended.selector);
        vm.prank(alice);
        juryPool.withdrawStake(minStake);
    }

    function test_fundJuryReserve() public {
        uint256 juryReserveBefore = juryPool.getJuryReserve();
        uint256 amount = 10 ether;
        vm.expectEmit(false, false, false, true);
        emit JuryReserveFunded(amount, alice);
        vm.prank(alice);
        juryPool.fundJuryReserve{value: amount}();
        assertEq(juryPool.getJuryReserve(), juryReserveBefore + amount);
    }

    function test_isEligible() public {
        // setup - alice registers
        uint256 minStake = juryPool.minimumStake();
        vm.prank(alice);
        juryPool.registerAsJuror{value: minStake}();
        assertEq(juryPool.isEligible(alice), true);
        // not registered
        assertEq(juryPool.isJuror(bob), false);
        assertEq(juryPool.isEligible(bob), false);
        // not active
        vm.prank(alice);
        juryPool.pauseJuror();
        assertEq(juryPool.isEligible(alice), false);
        // below minimum stake
        vm.prank(alice);
        juryPool.reactivateJuror();
        vm.prank(alice);
        juryPool.withdrawStake(1);
        assertTrue(juryPool.getJurorStake(alice) < juryPool.minimumStake());
        assertEq(juryPool.isEligible(alice), false);
        // back to normal
        vm.prank(alice);
        juryPool.stake{value: 1}();
        assertEq(juryPool.getJurorStake(alice), juryPool.minimumStake());
        assertEq(juryPool.isEligible(alice), true);
    }

    /////////////////////
    ///   GOVERNANCE  ///
    /////////////////////

    function test_setMinimumStake() public {
        assertEq(juryPool.minimumStake(), minimumJurorStake);
        uint256 newMinStake = minimumJurorStake + 10 ether;
        vm.prank(admin1);
        bytes memory data = abi.encodeWithSignature("setMinimumStake(uint256)", newMinStake);
        uint256 txIndex = governor.proposeTransaction(address(juryPool), 0, data);
        util_executeGovernorTx(txIndex);
        assertEq(juryPool.minimumStake(), newMinStake);
    }

    function test_suspendJuror() public {
        // setup - alice registers
        uint256 minStake = juryPool.minimumStake();
        vm.prank(alice);
        juryPool.registerAsJuror{value: minStake}();
        // governor suspends alice 
        bytes memory data = abi.encodeWithSignature("suspendJuror(address)", alice);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(juryPool), 0, data);
        util_executeGovernorTx(txIndex);
        assertEq(uint(juryPool.getJurorStatus(alice)), uint(JuryPool.JurorStatus.Suspended));
    }

    function test_suspendJuror_revert() public {
        // not registered
        assertEq(juryPool.isJuror(bob), false);
        bytes memory data = abi.encodeWithSignature("suspendJuror(address)", bob);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(juryPool), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        vm.expectRevert(Governor.Governor__TransactionFailed.selector);
        vm.prank(admin3);
        governor.signTransaction(txIndex);
        // already suspended
        test_suspendJuror();
        assertEq(uint(juryPool.getJurorStatus(alice)), uint(JuryPool.JurorStatus.Suspended));
        data = abi.encodeWithSignature("suspendJuror(address)", alice);
        vm.prank(admin1);
        txIndex = governor.proposeTransaction(address(juryPool), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        vm.expectRevert(Governor.Governor__TransactionFailed.selector);
        vm.prank(admin3);
        governor.signTransaction(txIndex);
    }

    function test_reinstateJuror() public {
        // setup - alice registers, governor suspends
        test_suspendJuror();
        // cannot withdraw stake
        uint256 aliceStake = juryPool.getJurorStake(alice);
        vm.expectRevert(JuryPool.JuryPool__JurorSuspended.selector);
        vm.prank(alice);
        juryPool.withdrawStake(aliceStake);
        // reinstate
        bytes memory data = abi.encodeWithSignature("reinstateJuror(address)", alice);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(juryPool), 0, data);
        util_executeGovernorTx(txIndex);
        assertEq(uint(juryPool.getJurorStatus(alice)), uint(JuryPool.JurorStatus.Active));
        // now can withdraw stake
        vm.prank(alice);
        juryPool.withdrawStake(aliceStake);
    }

    function test_reinstateJuror_revert() public {
        // not registered 
        assertEq(juryPool.isJuror(bob), false);
        bytes memory data = abi.encodeWithSignature("reinstateJuror(address)", bob);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(juryPool), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        vm.expectRevert(Governor.Governor__TransactionFailed.selector);
        vm.prank(admin3);
        governor.signTransaction(txIndex);
        // not suspended
        uint256 minStake = juryPool.minimumStake();
        vm.prank(alice);
        juryPool.registerAsJuror{value: minStake}();
        data = abi.encodeWithSignature("reinstateJuror(address)", alice);
        vm.prank(admin1);
        txIndex = governor.proposeTransaction(address(juryPool), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        vm.expectRevert(Governor.Governor__TransactionFailed.selector);
        vm.prank(admin3);
        governor.signTransaction(txIndex);
    }

    function test_withdrawJuryReserve() public {
        uint256 fundAmount = 1000 ether;
        vm.prank(alice);
        juryPool.fundJuryReserve{value: fundAmount}();
        uint256 withdrawAmount = fundAmount/2;
        uint256 recipientBalBefore = admin1.balance;
        uint256 contractBalBefore = address(juryPool).balance;
        uint256 reserveBefore = juryPool.getJuryReserve();
        bytes memory data = abi.encodeWithSignature("withdrawJuryReserve(address,uint256)", admin1, withdrawAmount);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(juryPool), 0, data);
        vm.expectEmit(false, false, false, true);
        emit JuryReserveWithdrawn(admin1, withdrawAmount);
        util_executeGovernorTx(txIndex);
        assertEq(admin1.balance, recipientBalBefore + withdrawAmount);
        assertEq(address(juryPool).balance, contractBalBefore - withdrawAmount);
        assertEq(juryPool.getJuryReserve(), reserveBefore - withdrawAmount);
    }

    function test_withdrawJuryReserve_revert() public {
        uint256 fundAmount = 1000 ether;
        vm.prank(alice);
        juryPool.fundJuryReserve{value: fundAmount}();
        // withdraw 0
        bytes memory data = abi.encodeWithSignature("withdrawJuryReserve(address,uint256)", admin1, 0);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(juryPool), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        vm.expectRevert();
        vm.prank(admin3);
        governor.signTransaction(txIndex);
        // insufficient balance
        data = abi.encodeWithSignature("withdrawJuryReserve(address,uint256)", admin1, juryPool.getJuryReserve() + 1);
        vm.prank(admin1);
        txIndex = governor.proposeTransaction(address(juryPool), 0, data);
        vm.prank(admin2);
        governor.signTransaction(txIndex);
        vm.expectRevert();
        vm.prank(admin3);
        governor.signTransaction(txIndex);
    }
 
}
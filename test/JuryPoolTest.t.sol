// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";

contract JuryPoolTest is Test, TestSetup {

    event JurorRegistered(address indexed juror, uint256 jurorIndex);
    event JurorPaused(address indexed juror, uint256 jurorIndex);
    event JurorReactivated(address indexed juror, uint256 indexed index);
    event JurorSuspended(address indexed juror, uint256 indexed index);
    event StakeWithdrawn(address indexed juror, uint256 withdrawAmount, uint256 totalStake);
    event Staked(address indexed juror, uint256 stakeAmount, uint256 totalStake);

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
        emit JurorRegistered(alice, 42);
        vm.prank(alice);
        uint256 index = juryPool.registerAsJuror{value: minStake}();
        assertEq(juryPool.getJurorStake(alice), stakeBefore + minStake);
        assertEq(juryPool.isJuror(alice), true);
        assertEq(juryPool.getJurorIndex(alice), index);
        assertEq(juryPool.juryPoolSize(), poolSizeBefore + 1);
        assertEq(address(juryPool).balance, contractBalBefore + minStake);
        JuryPool.Juror memory juror = juryPool.getJuror(index);
        assertEq(juror.jurorAddress, alice);
        assertEq(uint(juror.jurorStatus), uint(JuryPool.JurorStatus.Active));
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
        uint256 index = juryPool.registerAsJuror{value: minStake}();
        JuryPool.Juror memory juror = juryPool.getJuror(index);
        assertEq(uint(juror.jurorStatus), uint(JuryPool.JurorStatus.Active));
        // alice pauses
        vm.expectEmit(true, false, false, true);
        emit JurorPaused(alice, index);
        vm.prank(alice);
        juryPool.pauseJuror();
        juror = juryPool.getJuror(index);
        assertEq(uint(juror.jurorStatus), uint(JuryPool.JurorStatus.Paused));
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
        uint256 index = juryPool.registerAsJuror{value: minStake}();
        vm.prank(alice);
        juryPool.pauseJuror();
        // alice reactivates
        vm.expectEmit(true, false, false, true);
        emit JurorReactivated(alice, index);
        vm.prank(alice);
        juryPool.reactivateJuror();
        JuryPool.Juror memory juror = juryPool.getJuror(index);
        assertEq(uint(juror.jurorStatus), uint(JuryPool.JurorStatus.Active));
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

    ////////////////
    ///   ADMIN  ///
    ////////////////

    function test_suspendJuror() public {
        // setup - alice registers
        uint256 minStake = juryPool.minimumStake();
        vm.prank(alice);
        uint256 index = juryPool.registerAsJuror{value: minStake}();
        // governor suspends alice 
        bytes memory data = abi.encodeWithSignature("suspendJuror(address)", alice);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(juryPool), 0, data);
        util_executeGovernorTx(txIndex);
        JuryPool.Juror memory juror = juryPool.getJuror(index);
        assertEq(uint(juror.jurorStatus), uint(JuryPool.JurorStatus.Suspended));
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
        assertEq(uint(juryPool.getJuror(juryPool.getJurorIndex(alice)).jurorStatus), uint(JuryPool.JurorStatus.Suspended));
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
        uint256 minStake = juryPool.minimumStake();
        vm.prank(alice);
        uint256 index = juryPool.registerAsJuror{value: minStake}();
        bytes memory data = abi.encodeWithSignature("suspendJuror(address)", alice);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(juryPool), 0, data);
        util_executeGovernorTx(txIndex);
        // reinstate
        data = abi.encodeWithSignature("reinstateJuror(address)", alice);
        vm.prank(admin1);
        txIndex = governor.proposeTransaction(address(juryPool), 0, data);
        util_executeGovernorTx(txIndex);
        JuryPool.Juror memory juror = juryPool.getJuror(index);
        assertEq(uint(juror.jurorStatus), uint(JuryPool.JurorStatus.Active));
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

    // set minimum stake

    

}
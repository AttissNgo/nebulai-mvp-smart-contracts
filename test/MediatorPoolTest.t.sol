// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.13;

// import "forge-std/Test.sol";
// import "./TestSetup.t.sol";

// contract MediatorPoolTest is Test, TestSetup {

//     event MediatorRegistered(address indexed mediator);
//     event MediatorPaused(address indexed mediator);
//     event MediatorReactivated(address indexed mediator);
//     event MediatorSuspended(address indexed mediator);
//     event StakeWithdrawn(address indexed mediator, uint256 withdrawAmount, uint256 totalStake);
//     event Staked(address indexed mediator, uint256 stakeAmount, uint256 totalStake);
//     event MediationReserveFunded(uint256 amount, address from);
//     event MediationReserveWithdrawn(address recipient, uint256 amount);

//     function setUp() public {
//         _setUp();
//         _whitelistUsers();
//     }

//     function test_registerAsMediator() public {
//         assertEq(mediatorPool.isMediator(alice), false);
//         uint256 contractBalBefore = address(mediatorPool).balance;
//         uint256 poolSizeBefore = mediatorPool.mediatorPoolSize();
//         uint256 minStake = mediatorPool.minimumStake();
//         uint256 stakeBefore = mediatorPool.getMediatorStake(alice);
//         vm.expectEmit(true, false, false, false);
//         emit MediatorRegistered(alice);
//         vm.prank(alice);
//         mediatorPool.registerAsMediator{value: minStake}();
//         assertEq(mediatorPool.getMediatorStake(alice), stakeBefore + minStake);
//         assertEq(mediatorPool.isMediator(alice), true);
//         assertEq(mediatorPool.mediatorPoolSize(), poolSizeBefore + 1);
//         assertEq(address(mediatorPool).balance, contractBalBefore + minStake);
//         assertEq(uint(mediatorPool.getMediatorStatus(alice)), uint(MediatorPool.MediatorStatus.Active));
//     }

//     function test_registerAsMediator_reverts() public {
//         // minimum stake not met
//         uint256 minStake = mediatorPool.minimumStake();
//         vm.expectRevert(MediatorPool.MediatorPool__MinimumStakeNotMet.selector);
//         vm.prank(alice);
//         mediatorPool.registerAsMediator{value: minStake - 1}();
//         // setup - alice registers
//         vm.prank(alice);
//         mediatorPool.registerAsMediator{value: minStake}();
//         // already registered
//         assertEq(mediatorPool.isMediator(alice), true);
//         vm.expectRevert(MediatorPool.MediatorPool__AlreadyRegistered.selector);
//         vm.prank(alice);
//         mediatorPool.registerAsMediator{value: minStake}();
//     }

//     function test_pauseMediator() public {
//         // setup - alice registers as mediator
//         uint256 minStake = mediatorPool.minimumStake();
//         vm.prank(alice);
//         mediatorPool.registerAsMediator{value: minStake}();
//         assertEq(uint(mediatorPool.getMediatorStatus(alice)), uint(MediatorPool.MediatorStatus.Active));
//         // alice pauses
//         vm.expectEmit(true, false, false, false);
//         emit MediatorPaused(alice);
//         vm.prank(alice);
//         mediatorPool.pauseMediator();
//         assertEq(uint(mediatorPool.getMediatorStatus(alice)), uint(MediatorPool.MediatorStatus.Paused));
//     }

//     function test_pauseMediator_revert() public {
//         // not registered
//         assertEq(mediatorPool.isMediator(bob), false);
//         vm.expectRevert(MediatorPool.MediatorPool__NotRegistered.selector);
//         vm.prank(bob);
//         mediatorPool.pauseMediator();
//         // setup - alice registers, then pauses
//         uint256 minStake = mediatorPool.minimumStake();
//         vm.prank(alice);
//         mediatorPool.registerAsMediator{value: minStake}();
//         vm.prank(alice);
//         mediatorPool.pauseMediator();
//         // not active
//         vm.expectRevert(MediatorPool.MediatorPool__MediatorNotActive.selector);
//         vm.prank(alice);
//         mediatorPool.pauseMediator();
//     }

//     function test_reactivateMediator() public {
//         // setup - alice registers, then pauses 
//         uint256 minStake = mediatorPool.minimumStake();
//         vm.prank(alice);
//         mediatorPool.registerAsMediator{value: minStake}();
//         vm.prank(alice);
//         mediatorPool.pauseMediator();
//         // alice reactivates
//         vm.expectEmit(true, false, false, false);
//         emit MediatorReactivated(alice);
//         vm.prank(alice);
//         mediatorPool.reactivateMediator();
//         assertEq(uint(mediatorPool.getMediatorStatus(alice)), uint(MediatorPool.MediatorStatus.Active));
//     }

//     function test_reactivateMediator_reverts() public {
//         // setup - alice registers
//         uint256 minStake = mediatorPool.minimumStake();
//         vm.prank(alice);
//         mediatorPool.registerAsMediator{value: minStake}();
//         // already active
//         vm.expectRevert(MediatorPool.MediatorPool__MediatorAlreadyActive.selector);
//         vm.prank(alice);
//         mediatorPool.reactivateMediator();
//         // suspended
//         vm.prank(admin1);
//         bytes memory data = abi.encodeWithSignature("suspendMediator(address)", alice);
//         uint256 txIndex = governor.proposeTransaction(address(mediatorPool), 0, data);
//         util_executeGovernorTx(txIndex);
//         vm.expectRevert(MediatorPool.MediatorPool__MediatorSuspended.selector);
//         vm.prank(alice);
//         mediatorPool.reactivateMediator();
//     }

//     function test_stake() public {
//         // setup - alice registers
//         uint256 minStake = mediatorPool.minimumStake();
//         vm.prank(alice);
//         mediatorPool.registerAsMediator{value: minStake}();
//         uint256 stakeBefore = mediatorPool.getMediatorStake(alice);
//         // alice stakes more
//         uint256 stakeAmount = 10 ether;
//         vm.expectEmit(true, false, false, true);
//         emit Staked(alice, stakeAmount, stakeBefore + stakeAmount);
//         vm.prank(alice);
//         mediatorPool.stake{value: stakeAmount}();
//         assertEq(mediatorPool.getMediatorStake(alice), stakeBefore + stakeAmount);
//     }

//     function test_withdrawStake() public {
//         // setup - alice registers
//         uint256 minStake = mediatorPool.minimumStake();
//         vm.prank(alice);
//         mediatorPool.registerAsMediator{value: minStake}();
//         uint256 stakeBefore = mediatorPool.getMediatorStake(alice);
//         uint256 aliceBalBefore = alice.balance;
//         // withdraw
//         vm.expectEmit(true, false, false, true);
//         emit StakeWithdrawn(alice, minStake, 0);
//         vm.prank(alice); 
//         mediatorPool.withdrawStake(minStake);
//         assertEq(mediatorPool.getMediatorStake(alice), stakeBefore - minStake);
//         assertEq(alice.balance, aliceBalBefore + minStake);
//     }

//     function test_withdrawStake_revert() public {
//         // setup - alice registers
//         uint256 minStake = mediatorPool.minimumStake();
//         vm.prank(alice);
//         mediatorPool.registerAsMediator{value: minStake}();
//         // insufficient stake
//         vm.expectRevert(MediatorPool.MediatorPool__InsufficientStake.selector);
//         vm.prank(alice); 
//         mediatorPool.withdrawStake(minStake + 1);
//         // mediator suspended 
//         vm.prank(admin1);
//         bytes memory data = abi.encodeWithSignature("suspendMediator(address)", alice);
//         uint256 txIndex = governor.proposeTransaction(address(mediatorPool), 0, data);
//         util_executeGovernorTx(txIndex);
//         vm.expectRevert(MediatorPool.MediatorPool__MediatorSuspended.selector);
//         vm.prank(alice);
//         mediatorPool.withdrawStake(minStake);
//     }

//     function test_fundMediationReserve() public {
//         uint256 mediationReserveBefore = mediatorPool.getMediationReserve();
//         uint256 amount = 10 ether;
//         vm.expectEmit(false, false, false, true);
//         emit MediationReserveFunded(amount, alice);
//         vm.prank(alice);
//         mediatorPool.fundMediationReserve{value: amount}();
//         assertEq(mediatorPool.getMediationReserve(), mediationReserveBefore + amount);
//     }

//     function test_isEligible() public {
//         // setup - alice registers
//         uint256 minStake = mediatorPool.minimumStake();
//         vm.prank(alice);
//         mediatorPool.registerAsMediator{value: minStake}();
//         assertEq(mediatorPool.isEligible(alice), true);
//         // not registered
//         assertEq(mediatorPool.isMediator(bob), false);
//         assertEq(mediatorPool.isEligible(bob), false);
//         // not active
//         vm.prank(alice);
//         mediatorPool.pauseMediator();
//         assertEq(mediatorPool.isEligible(alice), false);
//         // below minimum stake
//         vm.prank(alice);
//         mediatorPool.reactivateMediator();
//         vm.prank(alice);
//         mediatorPool.withdrawStake(1);
//         assertTrue(mediatorPool.getMediatorStake(alice) < mediatorPool.minimumStake());
//         assertEq(mediatorPool.isEligible(alice), false);
//         // back to normal
//         vm.prank(alice);
//         mediatorPool.stake{value: 1}();
//         assertEq(mediatorPool.getMediatorStake(alice), mediatorPool.minimumStake());
//         assertEq(mediatorPool.isEligible(alice), true);
//     }

//     /////////////////////
//     ///   GOVERNANCE  ///
//     /////////////////////

//     function test_setMinimumStake() public {
//         assertEq(mediatorPool.minimumStake(), minimumMediatorStake);
//         uint256 newMinStake = minimumMediatorStake + 10 ether;
//         vm.prank(admin1);
//         bytes memory data = abi.encodeWithSignature("setMinimumStake(uint256)", newMinStake);
//         uint256 txIndex = governor.proposeTransaction(address(mediatorPool), 0, data);
//         util_executeGovernorTx(txIndex);
//         assertEq(mediatorPool.minimumStake(), newMinStake);
//     }

//     function test_suspendMediator() public {
//         // setup - alice registers
//         uint256 minStake = mediatorPool.minimumStake();
//         vm.prank(alice);
//         mediatorPool.registerAsMediator{value: minStake}();
//         // governor suspends alice 
//         bytes memory data = abi.encodeWithSignature("suspendMediator(address)", alice);
//         vm.prank(admin1);
//         uint256 txIndex = governor.proposeTransaction(address(mediatorPool), 0, data);
//         util_executeGovernorTx(txIndex);
//         assertEq(uint(mediatorPool.getMediatorStatus(alice)), uint(MediatorPool.MediatorStatus.Suspended));
//     }

//     function test_suspendMediator_revert() public {
//         // not registered
//         assertEq(mediatorPool.isMediator(bob), false);
//         bytes memory data = abi.encodeWithSignature("suspendMediator(address)", bob);
//         vm.prank(admin1);
//         uint256 txIndex = governor.proposeTransaction(address(mediatorPool), 0, data);
//         vm.prank(admin2);
//         governor.signTransaction(txIndex);
//         vm.expectRevert(Governor.Governor__TransactionFailed.selector);
//         vm.prank(admin3);
//         governor.signTransaction(txIndex);
//         // already suspended
//         test_suspendMediator();
//         assertEq(uint(mediatorPool.getMediatorStatus(alice)), uint(MediatorPool.MediatorStatus.Suspended));
//         data = abi.encodeWithSignature("suspendMediator(address)", alice);
//         vm.prank(admin1);
//         txIndex = governor.proposeTransaction(address(mediatorPool), 0, data);
//         vm.prank(admin2);
//         governor.signTransaction(txIndex);
//         vm.expectRevert(Governor.Governor__TransactionFailed.selector);
//         vm.prank(admin3);
//         governor.signTransaction(txIndex);
//     }

//     function test_reinstateMediator() public {
//         // setup - alice registers, governor suspends
//         test_suspendMediator();
//         // cannot withdraw stake
//         uint256 aliceStake = mediatorPool.getMediatorStake(alice);
//         vm.expectRevert(MediatorPool.MediatorPool__MediatorSuspended.selector);
//         vm.prank(alice);
//         mediatorPool.withdrawStake(aliceStake);
//         // reinstate
//         bytes memory data = abi.encodeWithSignature("reinstateMediator(address)", alice);
//         vm.prank(admin1);
//         uint256 txIndex = governor.proposeTransaction(address(mediatorPool), 0, data);
//         util_executeGovernorTx(txIndex);
//         assertEq(uint(mediatorPool.getMediatorStatus(alice)), uint(MediatorPool.MediatorStatus.Active));
//         // now can withdraw stake
//         vm.prank(alice);
//         mediatorPool.withdrawStake(aliceStake);
//     }

//     function test_reinstateMediator_revert() public {
//         // not registered 
//         assertEq(mediatorPool.isMediator(bob), false);
//         bytes memory data = abi.encodeWithSignature("reinstateMediator(address)", bob);
//         vm.prank(admin1);
//         uint256 txIndex = governor.proposeTransaction(address(mediatorPool), 0, data);
//         vm.prank(admin2);
//         governor.signTransaction(txIndex);
//         vm.expectRevert(Governor.Governor__TransactionFailed.selector);
//         vm.prank(admin3);
//         governor.signTransaction(txIndex);
//         // not suspended
//         uint256 minStake = mediatorPool.minimumStake();
//         vm.prank(alice);
//         mediatorPool.registerAsMediator{value: minStake}();
//         data = abi.encodeWithSignature("reinstateMediator(address)", alice);
//         vm.prank(admin1);
//         txIndex = governor.proposeTransaction(address(mediatorPool), 0, data);
//         vm.prank(admin2);
//         governor.signTransaction(txIndex);
//         vm.expectRevert(Governor.Governor__TransactionFailed.selector);
//         vm.prank(admin3);
//         governor.signTransaction(txIndex);
//     }

//     function test_withdrawMediationReserve() public {
//         uint256 fundAmount = 1000 ether;
//         vm.prank(alice);
//         mediatorPool.fundMediationReserve{value: fundAmount}();
//         uint256 withdrawAmount = fundAmount/2;
//         uint256 recipientBalBefore = admin1.balance;
//         uint256 contractBalBefore = address(mediatorPool).balance;
//         uint256 reserveBefore = mediatorPool.getMediationReserve();
//         bytes memory data = abi.encodeWithSignature("withdrawMediationReserve(address,uint256)", admin1, withdrawAmount);
//         vm.prank(admin1);
//         uint256 txIndex = governor.proposeTransaction(address(mediatorPool), 0, data);
//         // vm.expectEmit(false, false, false, true);
//         // emit MediationReserveWithdrawn(admin1, withdrawAmount);
//         util_executeGovernorTx(txIndex);
//         assertEq(admin1.balance, recipientBalBefore + withdrawAmount);
//         assertEq(address(mediatorPool).balance, contractBalBefore - withdrawAmount);
//         assertEq(mediatorPool.getMediationReserve(), reserveBefore - withdrawAmount);
//     }

//     function test_withdrawMediationReserve_revert() public {
//         uint256 fundAmount = 1000 ether;
//         vm.prank(alice);
//         mediatorPool.fundMediationReserve{value: fundAmount}();
//         // withdraw 0
//         bytes memory data = abi.encodeWithSignature("withdrawMediationReserve(address,uint256)", admin1, 0);
//         vm.prank(admin1);
//         uint256 txIndex = governor.proposeTransaction(address(mediatorPool), 0, data);
//         vm.prank(admin2);
//         governor.signTransaction(txIndex);
//         vm.expectRevert();
//         vm.prank(admin3);
//         governor.signTransaction(txIndex);
//         // insufficient balance
//         data = abi.encodeWithSignature("withdrawMediationReserve(address,uint256)", admin1, mediatorPool.getMediationReserve() + 1);
//         vm.prank(admin1);
//         txIndex = governor.proposeTransaction(address(mediatorPool), 0, data);
//         vm.prank(admin2);
//         governor.signTransaction(txIndex);
//         vm.expectRevert();
//         vm.prank(admin3);
//         governor.signTransaction(txIndex);
//     }
 
// }
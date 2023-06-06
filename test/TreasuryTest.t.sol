// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";

contract TreasuryTest is Test, TestSetup {

    // event RewardTokensRedeemed(address owner, uint256 rewardTokenAmount, uint256 nebTokenAmount);


    function setUp() public {
        _deployContracts();
    }

    function test_transferTokens() public {
        uint256 amount = 42 ether;
        uint256 aliceBalBefore = nebToken.balanceOf(alice);
        uint256 treasuryBalBefore = nebToken.balanceOf(address(treasury));
        bytes memory data = abi.encodeWithSignature(
            "transferTokens(address,uint256,address)", 
            alice,
            amount,
            address(nebToken)
        );
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(treasury), 0, data);
        util_executeGovernorTx(txIndex);
        assertEq(nebToken.balanceOf(alice), aliceBalBefore + amount);
        assertEq(nebToken.balanceOf(address(treasury)), treasuryBalBefore - amount);
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

    // function test_redeemRewardTokens() public {
    //     // issue reward tokens
    //     uint256 rewardAmount = 1000;
    //     uint256 nonce = 0;
    //     bytes32 rewardHash = keccak256(abi.encodePacked(alice, rewardAmount, "reward description", nonce));
    //     assertEq(rewardToken.issued(rewardHash), false);
    //     vm.prank(issuer);
    //     rewardToken.issueTokens(alice, rewardAmount, rewardHash);
    //     // redeem for NEB
    //     uint256 treasuryBalBefore = nebToken.balanceOf(address(treasury));
    //     uint256 aliceBalBefore = nebToken.balanceOf(alice);
    //     uint256 nebAmount = treasury.getRewardToNebAmount(rewardAmount);
    //     vm.expectEmit(false, false, false, true);
    //     emit RewardTokensRedeemed(alice, rewardAmount, nebAmount);
    //     vm.prank(alice);
    //     rewardToken.redeemForNeb(rewardAmount);
    //     assertEq(nebToken.balanceOf(address(treasury)), treasuryBalBefore - nebAmount);
    //     assertEq(nebToken.balanceOf(alice), aliceBalBefore + nebAmount);
    // }
}
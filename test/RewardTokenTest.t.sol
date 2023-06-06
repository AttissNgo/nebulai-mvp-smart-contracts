// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";

contract RewardTokenTest is Test, TestSetup {

    event TokensRedeemed(address owner, uint256 amount);

    function setUp() public {
        _deployContracts();
    }

    function test_reward_token_remove_issuer() public {
        bytes memory data = abi.encodeWithSignature("removeIssuer(address)", issuer2);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(rewardToken), 0, data);
        util_executeGovernorTx(txIndex);
        assertEq(rewardToken.isIssuer(issuer2), false);
    }

    function test_reward_add_issuer() public {
        test_reward_token_remove_issuer();
        bytes memory data = abi.encodeWithSignature("addIssuer(address)", issuer2);
        vm.prank(admin1);
        uint256 txIndex = governor.proposeTransaction(address(rewardToken), 0, data);
        util_executeGovernorTx(txIndex);
        assertEq(rewardToken.isIssuer(issuer2), true);
    }

    function test_issueTokens() public returns (uint256) {
        assertEq(rewardToken.totalSupply(), 0);
        uint256 amount = 1000;
        uint256 nonce = 0;
        uint256 aliceBalBefore = rewardToken.balanceOf(alice);
        bytes32 rewardHash = keccak256(abi.encodePacked(alice, amount, "reward description", nonce));
        assertEq(rewardToken.issued(rewardHash), false);
        vm.prank(issuer);
        rewardToken.issueTokens(alice, amount, rewardHash);
        assertEq(rewardToken.balanceOf(alice), aliceBalBefore + amount);
        assertEq(rewardToken.issued(rewardHash), true);
        assertEq(rewardToken.totalSupply(), amount);
        return amount;
    }

    // function test_redeemForNeb() public {
    //     uint256 amount = test_issueTokens();
    //     uint256 totalSupplyBefore = rewardToken.totalSupply();
    //     uint256 aliceBalBefore = rewardToken.balanceOf(alice);
    //     vm.expectEmit(false, false, false, true);
    //     emit TokensRedeemed(alice, amount);
    //     vm.prank(alice);
    //     rewardToken.redeemForNeb(amount);
    //     assertEq(rewardToken.totalSupply(), totalSupplyBefore - amount);
    //     assertEq(rewardToken.balanceOf(alice), aliceBalBefore - amount);
    // }

}
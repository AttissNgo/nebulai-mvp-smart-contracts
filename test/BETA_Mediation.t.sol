// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./TestSetup.t.sol";
import "../src/MediationServiceBETA.sol";

contract BETA_MediationTest is Test, TestSetup {

    MediationServiceBETA public mediationServiceBETA;

    function setUp() public {
        vm.startPrank(admin1);
        // deploy contracts
        usdt = new USDTMock(); 
        vrf = new VRFCoordinatorV2Mock(1, 1); 
        subscriptionId = vrf.createSubscription();
        vrf.fundSubscription(subscriptionId, 100 ether);
        governor = new Governor(admins, sigsRequired);
        whitelist = new Whitelist(address(governor));
        mediatorPool = new MediatorPool(address(governor), address(whitelist), minimumMediatorStake);

        uint64 nonce = vm.getNonce(admin1);
        address predictedMarketplace = computeCreateAddress(admin1, nonce + 2);

        mediationServiceBETA = new MediationServiceBETA(
            address(governor), 
            address(mediatorPool),
            address(vrf),
            keyHash,
            subscriptionId,
            predictedMarketplace ////////////////
        );
        approvedTokens.push(address(usdt));
        escrowFactory = new EscrowFactory();
        marketplace = new Marketplace(
            address(governor), 
            address(whitelist), 
            address(mediationServiceBETA), 
            address(escrowFactory),
            approvedTokens
        );
        vm.stopPrank();

        // supply ether & usdt
        for(uint i; i < users.length; ++i) {
            vm.deal(users[i], 10000 ether);
            usdt.mint(users[i], 10000 ether);
        }
        for(uint i; i < admins.length; ++i) {
            vm.deal(admins[i], 10000 ether);
            usdt.mint(admins[i], 10000 ether);
        }

        // label addresses
        _labelTestAddresses();

        // initialize test project variables
        dueDate = block.timestamp + 30 days;

        _whitelistUsers();
        // _registerMediators();
        _initializeTestProjects();
        // _initializeMediationProjects();
    }

    function test_createDispute() public {
        Project memory project = marketplace.getProject(id_challenged_ERC20);
        _disputeProject(project.projectId, changeOrderAdjustedProjectFee, changeOrderProviderStakeForfeit);
        Dispute memory dispute = mediationServiceBETA.getDispute(marketplace.getDisputeId(project.projectId));
        assertEq(dispute.disputeId, marketplace.getDisputeId(project.projectId));
        assertEq(dispute.projectId, project.projectId);
        assertEq(dispute.adjustedProjectFee, changeOrderAdjustedProjectFee);
        assertEq(dispute.providerStakeForfeit, changeOrderProviderStakeForfeit);
        assertEq(dispute.claimant, project.buyer);
        assertEq(dispute.respondent, project.provider);
        assertEq(dispute.mediationFee, mediationServiceBETA.calculateMediationFee(false));
        assertEq(dispute.feePaidClaimant, false);
        assertEq(dispute.feePaidRespondent, false);
        assertEq(dispute.disclosureStart, block.timestamp);
        assertEq(dispute.selectionStart, 0);
        assertEq(dispute.votingStart, 0);
        assertEq(dispute.decisionRenderedDate, 0);
        assertEq(dispute.isAppeal, false);
        assertEq(dispute.granted, false);
        assertEq(uint(dispute.phase), uint(Phase.Disclosure));
        assertEq(dispute.evidence.length, 0);
    }

    function test_resolves_disputes_automatically() public {
        test_createDispute();
        Dispute memory dispute = mediationServiceBETA.getDispute(marketplace.getDisputeId(id_challenged_ERC20));
        
        // disputants pay fees
        vm.prank(dispute.claimant);
        mediationServiceBETA.payMediationFee{value: dispute.mediationFee}(dispute.disputeId, evidence1);
        vm.prank(dispute.respondent);
        mediationServiceBETA.payMediationFee{value: dispute.mediationFee}(dispute.disputeId, evidence2);

        dispute = mediationServiceBETA.getDispute(marketplace.getDisputeId(id_challenged_ERC20));
        // Dispute object updated
        assertEq(uint(dispute.phase), uint(Phase.Decision));  
        assertEq(dispute.decisionRenderedDate, block.timestamp);
        // fees held == one disputant's fee
        assertEq(mediationServiceBETA.getFeesHeld(dispute.disputeId), dispute.mediationFee);
    }

    function test_winner_can_reclaim_fee() public {
        test_resolves_disputes_automatically();
        Dispute memory dispute = mediationServiceBETA.getDispute(marketplace.getDisputeId(id_challenged_ERC20));

        console.log(dispute.granted); // true
        uint256 feesHeldBefore = mediationServiceBETA.getFeesHeld(dispute.disputeId);
        uint256 claimantBalBefore = dispute.claimant.balance;
        uint256 contractBalBefore = address(mediationServiceBETA).balance;

        // respondent CANNOT withdraw
        vm.expectRevert(MediationService.MediationService__OnlyPrevailingParty.selector);
        vm.prank(dispute.respondent);
        mediationServiceBETA.reclaimMediationFee(dispute.disputeId);

        // claimant can withdraw
        vm.prank(dispute.claimant);
        mediationServiceBETA.reclaimMediationFee(dispute.disputeId);
        assertEq(dispute.claimant.balance, claimantBalBefore + dispute.mediationFee);
        assertEq(address(mediationServiceBETA).balance, contractBalBefore - dispute.mediationFee);
        assertEq(mediationServiceBETA.getFeesHeld(dispute.disputeId), feesHeldBefore - dispute.mediationFee);
        assertEq(mediationServiceBETA.getFeesHeld(dispute.disputeId), 0);
    }

    function test_can_appeal() public {
        test_resolves_disputes_automatically();
        Dispute memory dispute = mediationServiceBETA.getDispute(marketplace.getDisputeId(id_challenged_ERC20));
        vm.prank(dispute.respondent);
        uint256 newDisputeId = marketplace.appealDecision(id_challenged_ERC20);
        dispute = mediationServiceBETA.getDispute(marketplace.getDisputeId(id_challenged_ERC20));
        assertEq(dispute.disputeId, newDisputeId);
        assertEq(dispute.isAppeal, true);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../DataStructuresLibrary.sol";

interface IMediationService {
    function createDispute(
        uint256 _projectId,
        uint256 _adjustedProjectFee,
        uint256 _providerStakeForfeit,
        address _claimant,
        address _respondent
    ) external returns (uint256);
    function appeal(uint256 _projectId) external returns (uint256);
    function settledExternally(uint256 _disputeId) external;
    function getDispute(uint256 _disputeId) external view returns (DataStructuresLibrary.Dispute memory);
    function calculateMediationFee(bool isAppeal) external view returns (uint256);
    function payMediationFee(uint256 _petitionId, string[] calldata _evidenceURIs) external payable;
    function getPanel(uint256 _disputeId) external view returns (DataStructuresLibrary.Panel memory);
    function mediatorsNeeded(uint256 disputeId) external view returns (uint256);

    function mediatorFlatFee() external returns (uint256);
    function acceptCase(uint256 _disputeId) external payable;
    function commitVote(uint256 _disputeId, bytes32 _commit) external;
    function revealVote(uint256 _disputeId, bool _vote, string calldata _salt) external;
}
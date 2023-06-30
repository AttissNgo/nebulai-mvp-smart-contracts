// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ICourt {
    function createPetition(
        uint256 _projectId,
        uint256 _adjustedProjectFee,
        uint256 _providerStakeForfeit,
        address _plaintiff,
        address _defendant
    ) external returns (uint256);
}
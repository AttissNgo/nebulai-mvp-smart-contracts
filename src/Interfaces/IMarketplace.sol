// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IMarketplace {

    function getArbitrationPetitionId(uint256 _projectId) external view returns (uint256);
    function isDisputed(uint256 _projectId) external view returns (bool);
}
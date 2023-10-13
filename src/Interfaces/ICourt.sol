// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../DataStructuresLibrary.sol";

interface ICourt {
    function createPetition(
        uint256 _projectId,
        uint256 _adjustedProjectFee,
        uint256 _providerStakeForfeit,
        address _plaintiff,
        address _defendant
    ) external returns (uint256);
    function appeal(uint256 _projectId) external returns (uint256);
    function settledExternally(uint256 _petitionId) external;
    function getPetition(uint256 _petitionId) external view returns (DataStructuresLibrary.Petition memory);


}
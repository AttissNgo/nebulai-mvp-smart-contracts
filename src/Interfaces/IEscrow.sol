// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IEscrow {
    function MARKETPLACE() external view returns (address);
    function PROJECT_ID() external view returns (uint256);
    function BUYER() external view returns (address);
    function PROVIDER() external view returns (address);
    function PAYMENT_TOKEN() external view returns (address);
    function PROJECT_FEE() external view returns (uint256);
    function PROVIDER_STAKE() external view returns (uint256);    
    function MEDIATION_SERVICE() external view returns (address);

    function providerHasStaked() external returns (bool);
    function verifyProviderStake() external returns (bool); 
    function withdraw() external;
    function hasWithdrawn(address _user) external view returns (bool);
    function isReleasable() external view returns (bool);
    function amountDue(address _user) external view returns (uint256, uint256);
}


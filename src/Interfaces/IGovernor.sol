// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IGovernor {
    function isAdmin(address _address) external returns (bool);
}
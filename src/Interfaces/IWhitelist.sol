// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IWhitelist {
    function isApproved(address _user) external returns (bool);
}
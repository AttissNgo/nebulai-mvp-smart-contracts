// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Interfaces/IGovernor.sol";

contract Whitelist {

    address public immutable GOVERNOR;

    mapping(address => bool) private approvedAddresses;

    event Whitelisted(address indexed user);
    event ApprovalRevoked(address indexed user);

    error Whitelist__OnlyGovernor();
    error Whitelist__OnlyAdmin();
    error Whitelist__AlreadyApproved();
    error Whitelist__NotApproved();

    modifier onlyAdmin {
        if(!IGovernor(GOVERNOR).isAdmin(msg.sender)) revert Whitelist__OnlyAdmin();
        _;
    }

    modifier onlyGovernor {
        if(msg.sender != GOVERNOR) revert Whitelist__OnlyGovernor();
        _;
    }

    constructor(address _governor) {
        GOVERNOR = _governor;
    }

    function approveAddress(address _address) external onlyAdmin {
        if(approvedAddresses[_address]) revert Whitelist__AlreadyApproved();
        approvedAddresses[_address] = true;
        emit Whitelisted(_address);
    }

    function revokeApproval(address _address) external onlyAdmin {
        if(!approvedAddresses[_address]) revert Whitelist__NotApproved();
        approvedAddresses[_address] = false;
        emit ApprovalRevoked(_address);
    }


    function isApproved(address _address) public view returns (bool) {
        return approvedAddresses[_address];
    }
} 
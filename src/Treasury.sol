// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Treasury {

    address public immutable GOVERNOR;

    event TokenTransferred(address to, uint256 amount, address tokenAddress);

    error Treasury__OnlyGovernor();
    error Treasury__InsufficientContractBalance();
    error Treasury__TransferFailed();

    modifier onlyGovernor() {
        if(msg.sender != GOVERNOR) revert Treasury__OnlyGovernor();
        _;
    }

    constructor(address _governor) {
        GOVERNOR = _governor;
    }

    fallback() external payable {}
    receive() external payable {}

    function transferTokens(address _to, uint256 _amount, address _tokenAddress) external onlyGovernor {
        IERC20 token = IERC20(_tokenAddress);
        if(token.balanceOf(address(this)) < _amount) revert Treasury__InsufficientContractBalance();
        bool success = token.transfer(_to, _amount);
        if(!success) revert Treasury__TransferFailed();
        emit TokenTransferred(_to, _amount, _tokenAddress);
    }

    function transferNative(address _to, uint256 _amount) external onlyGovernor {
        if(address(this).balance < _amount) revert Treasury__InsufficientContractBalance();
        (bool success, ) = _to.call{value: _amount}("");
        if(!success) revert Treasury__TransferFailed();
        emit TokenTransferred(_to, _amount, address(0));
    }

}
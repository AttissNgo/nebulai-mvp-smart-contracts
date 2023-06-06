// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Treasury {

    address public immutable GOVERNOR;
    // address public immutable REWARD_TOKEN;
    // address public immutable NEB_TOKEN;

    event TokenTransferred(address to, uint256 amount, address tokenAddress);
    // event RewardTokensRedeemed(address owner, uint256 rewardTokenAmount, uint256 nebTokenAmount);

    error Treasury__OnlyGovernor();
    error Treasury__InsufficientContractBalance();
    error Treasury__OnlyRewardToken();
    error Treasury__TransferFailed();

    modifier onlyGovernor() {
        if(msg.sender != GOVERNOR) revert Treasury__OnlyGovernor();
        _;
    }

    constructor(address _governor) {
        GOVERNOR = _governor;
        // REWARD_TOKEN = _rewardToken;
        // NEB_TOKEN = _nebToken;
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

    // function redeemRewardTokens(address _recipient, uint256 _rewardTokenAmount) external returns (bool) {
    //     if(msg.sender != REWARD_TOKEN) revert Treasury__OnlyRewardToken();
    //     // some logic for calculating the exchange goes here, but for now...
    //     uint256 nebAmount = getRewardToNebAmount(_rewardTokenAmount);
    //     bool success = IERC20(NEB_TOKEN).transfer(_recipient, nebAmount);
    //     if(!success) revert Treasury__TransferFailed();
    //     emit RewardTokensRedeemed(_recipient, _rewardTokenAmount, nebAmount);
    //     return true;
    // }

    // function getRewardToNebAmount(uint256 _rewardTokenAmount) public pure returns (uint256) {
    //     return (_rewardTokenAmount / 1000) * 1 ether;
    // }

}
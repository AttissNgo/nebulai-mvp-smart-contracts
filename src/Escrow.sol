// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Escrow {

    address public immutable MARKETPLACE;
    uint256 public immutable PROJECT_ID;
    address public immutable BUYER;
    address public immutable PROVIDER;
    address public immutable PAYMENT_TOKEN;
    uint256 public immutable PROJECT_FEE;
    uint256 public immutable PROVIDER_STAKE;

    bool public providerHasStaked = false;

    error Escrow__OnlyMarketplace();
    error Escrow__InsufficientAmount();
    error Escrow__TransferFailed();

    constructor(
        address _marketplace,
        uint256 _projectId,
        address _buyer,
        address _provider,
        address _paymentToken,
        uint256 _projectFee,
        uint256 _providerStake
    )
    {
        MARKETPLACE = _marketplace;
        PROJECT_ID = _projectId;
        BUYER = _buyer;
        PROVIDER = _provider;
        PAYMENT_TOKEN = _paymentToken;
        PROJECT_FEE = _projectFee;
        PROVIDER_STAKE = _providerStake;
    }

    // fallback() payable {}
    receive() external payable {}

    function verifyProviderStake() external returns (bool) {
        if(msg.sender != MARKETPLACE) revert Escrow__OnlyMarketplace();
        if(PAYMENT_TOKEN != address(0)) {
            if(IERC20(PAYMENT_TOKEN).balanceOf(address(this)) < (PROJECT_FEE + PROVIDER_STAKE)) return false;
        } else {
            if(address(this).balance < (PROJECT_FEE + PROVIDER_STAKE)) return false;
        }
        providerHasStaked = true;
        return providerHasStaked;
    } 

}
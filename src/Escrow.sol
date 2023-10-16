// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Interfaces/IMarketplace.sol";
import "./Interfaces/ICourt.sol";
import "./DataStructuresLibrary.sol";

contract Escrow is DataStructuresLibrary {

    address public immutable MARKETPLACE;
    uint256 public immutable PROJECT_ID;
    address public immutable BUYER;
    address public immutable PROVIDER;
    address public immutable PAYMENT_TOKEN;
    uint256 public immutable PROJECT_FEE;
    uint256 public immutable PROVIDER_STAKE;
    address public immutable COURT;

    bool public providerHasStaked = false;
    bool private buyerHasWithdrawn = false;
    bool private providerHasWithdrawn = false;
    // uint256 public commissionFee;

    event EscrowReleased(address recipient, uint256 amountReleased, uint256 commissionFeePaid);

    error Escrow__OnlyMarketplace();
    error Escrow__InsufficientAmount();
    error Escrow__TransferFailed();
    error Escrow__ProjectFeeNotDeposited();
    error Escrow__OnlyBuyerOrProvider();
    error Escrow__NotReleasable();
    error Escrow__UserHasAlreadyWithdrawn();
    error Escrow__NoPaymentDue();
    error Escrow__CommissionTransferFailed();

    constructor(
        address _marketplace,
        uint256 _projectId,
        address _buyer,
        address _provider,
        address _paymentToken,
        uint256 _projectFee,
        uint256 _providerStake,
        address _court
    )
    {
        MARKETPLACE = _marketplace;
        PROJECT_ID = _projectId;
        BUYER = _buyer;
        PROVIDER = _provider;
        PAYMENT_TOKEN = _paymentToken;
        PROJECT_FEE = _projectFee;
        PROVIDER_STAKE = _providerStake;
        COURT = _court;
    }

    receive() external payable {}

    /**
     * @dev called by Marketplace contract to verify Provider has staked
     */
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

    /**
     * @notice transfers amountDue() to caller
     * @dev transfers commissionFee to Marketplace when Provider withdraws
     */
    function withdraw() external {
        if(msg.sender != BUYER && msg.sender !=PROVIDER) revert Escrow__OnlyBuyerOrProvider();
        if(!isReleasable()) revert Escrow__NotReleasable();
        if(hasWithdrawn(msg.sender)) revert Escrow__UserHasAlreadyWithdrawn();

        (uint256 amount, uint256 commissionFee) = amountDue(msg.sender);
        if(amount == 0) revert Escrow__NoPaymentDue();

        (msg.sender == BUYER) ? buyerHasWithdrawn = true : providerHasWithdrawn = true;

        if(PAYMENT_TOKEN == address(0)) {
            (bool success,) = msg.sender.call{value: amount}("");
            if(!success) revert Escrow__TransferFailed();
        } else {
            bool success = IERC20(PAYMENT_TOKEN).transfer(msg.sender, amount);
            if(!success) revert Escrow__TransferFailed();
        }
        if(msg.sender == PROVIDER) {
            if(PAYMENT_TOKEN == address(0)) {
                (bool success,) = MARKETPLACE.call{value: commissionFee}("");
                if(!success) revert Escrow__CommissionTransferFailed();
            } else {
                bool success = IERC20(PAYMENT_TOKEN).transfer(MARKETPLACE, commissionFee);
                if(!success) revert Escrow__CommissionTransferFailed();
            }
            IMarketplace(MARKETPLACE).receiveCommission(PROJECT_ID, commissionFee);
        }
        emit EscrowReleased(msg.sender, amount, commissionFee);
    }

    function isReleasable() public view returns (bool) {
        Status status = IMarketplace(MARKETPLACE).getProjectStatus(PROJECT_ID);
        if(
            status == Status.Cancelled ||
            status == Status.Approved ||
            status == Status.Resolved_ChangeOrder ||
            status == Status.Resolved_CourtOrder ||
            status == Status.Resolved_DelinquentPayment ||
            status == Status.Resolved_ArbitrationDismissed
        ) return true;
        return false;
    }

    /**
     * @notice calculates amount Escrow will release to _user
     */
    function amountDue(address _user) public view returns (uint256, uint256) { 
        uint256 amount;
        uint256 commissionFee;
        IMarketplace marketplace = IMarketplace(MARKETPLACE);
        Status status = marketplace.getProjectStatus(PROJECT_ID);
        if(status == Status.Cancelled) {
            (_user == BUYER) ? amount = PROJECT_FEE : amount = 0;
        } 
        else if(
            status == Status.Approved || 
            status == Status.Resolved_DelinquentPayment ||
            status == Status.Resolved_ArbitrationDismissed
        ) {
            if(_user == PROVIDER) {
                commissionFee = calculateCommissionFee(PROJECT_FEE);
                amount = (PROJECT_FEE - commissionFee) + PROVIDER_STAKE;
            }
        } 
        else if(status == Status.Resolved_ChangeOrder) {
            ChangeOrder memory changeOrder = marketplace.getActiveChangeOrder(PROJECT_ID);
            if(_user == BUYER) {
                amount = (PROJECT_FEE - changeOrder.adjustedProjectFee) + changeOrder.providerStakeForfeit;
            } else if(_user == PROVIDER) {
                commissionFee = calculateCommissionFee(changeOrder.adjustedProjectFee);
                amount = (changeOrder.adjustedProjectFee - commissionFee) + (PROVIDER_STAKE - changeOrder.providerStakeForfeit);
            }
        } 
        else if(status == Status.Resolved_CourtOrder) {
            uint256 petitionId = IMarketplace(MARKETPLACE).getArbitrationPetitionId(PROJECT_ID);
            Petition memory petition = ICourt(COURT).getPetition(petitionId);
            if(petition.petitionGranted) {
                if(_user == BUYER) {
                    amount = (PROJECT_FEE - petition.adjustedProjectFee) + petition.providerStakeForfeit;
                } else if(_user == PROVIDER) {
                    if((petition.adjustedProjectFee - petition.providerStakeForfeit) > 0) {
                         commissionFee = calculateCommissionFee(petition.adjustedProjectFee);
                    }
                    amount = (petition.adjustedProjectFee - commissionFee) + (PROVIDER_STAKE - petition.providerStakeForfeit);
                }
            } else { // petition NOT granted
                if(_user == PROVIDER) {
                    commissionFee = calculateCommissionFee(PROJECT_FEE);
                    amount = (PROJECT_FEE - commissionFee) + PROVIDER_STAKE;
                }
            }

        }
        return (amount, commissionFee);
    }

    /**
     * 
     * @dev if _totalPaid is >= 100, returns 1% of _totalPaid, else returns 0 
     */
    function calculateCommissionFee(uint256 _totalPaid) private pure returns (uint256) {
        if(_totalPaid < 100) return 0;
        return _totalPaid/100;
    }

    function hasWithdrawn(address _user) public view returns (bool) {
        if(_user == BUYER && buyerHasWithdrawn) return true;
        if(_user == PROVIDER && providerHasWithdrawn) return true;
        return false;
    }

}
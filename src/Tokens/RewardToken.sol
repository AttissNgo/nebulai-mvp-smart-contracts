// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// import "solmate/src/tokens/ERC20.sol";

interface TreasuryInterface {
    function redeemRewardTokens(address _recipient, uint256 _rewardTokenAmount) external returns (bool);
}

contract RewardToken {

    address public immutable GOVERNOR;
    // address public TREASURY;
    // bool public treasurySet;
    
    uint256 public totalSupply;
    uint256 public maxIssuance = 10000;
    mapping(address => uint256) public balanceOf;

    mapping(address => bool) public isIssuer;

    mapping(bytes32 => bool) public issued;

    event IssuerAdded(address issuer);
    event IssuerRemoved(address issuer);
    event TokenIssued(address recipient, uint256 amount, bytes32 rewardHash, address issuedBy);
    // event TokensRedeemed(address owner, uint256 amount);

    error RewardToken__OnlyGovernor();
    error RewardToken__OnlyIssuer();
    error RewardToken__RewardAlreadyIssued();
    error RewardToken__MaxIssuanceExceeded();
    error RewardToken__TreasuryNotSet();
    error RewardToken__InsufficientBalance();

    modifier onlyGovernor() {
        if(msg.sender != GOVERNOR) revert RewardToken__OnlyGovernor();
        _;
    }

    modifier onlyIssuer() {
        if(!isIssuer[msg.sender]) revert RewardToken__OnlyIssuer();
        _;
    }

    constructor(address _governor, address[] memory _issuers) {
        GOVERNOR = _governor;
        for(uint i; i < _issuers.length; ++i) {
            isIssuer[_issuers[i]] = true;
        }
    }

    function addIssuer(address _issuer) external onlyGovernor {
        require(!isIssuer[_issuer]);
        isIssuer[_issuer] = true;
        emit IssuerAdded(_issuer);
    }

    function removeIssuer(address _issuer) external onlyGovernor {
        require(isIssuer[_issuer]);
        isIssuer[_issuer] = false;
        emit IssuerRemoved(_issuer);
    }

    // function setTreasury(address _treasury) external onlyGovernor {
    //     require(!treasurySet);
    //     treasurySet = true;
    //     TREASURY = _treasury;
    // }

    function issueTokens(address _recipient, uint256 _amount, bytes32 _rewardHash) external onlyIssuer {
        if(_amount > maxIssuance) revert RewardToken__MaxIssuanceExceeded(); 
        if(issued[_rewardHash]) revert RewardToken__RewardAlreadyIssued();
        issued[_rewardHash] = true;
        balanceOf[_recipient] += _amount;
        totalSupply += _amount;
        emit TokenIssued(_recipient, _amount, _rewardHash, msg.sender);
    }

    // function redeemForNeb(uint256 _rewardTokenAmount) external {
    //     if(!treasurySet) revert RewardToken__TreasuryNotSet();
    //     if(balanceOf[msg.sender] < _rewardTokenAmount) revert RewardToken__InsufficientBalance();
    //     bool success = TreasuryInterface(TREASURY).redeemRewardTokens(msg.sender, _rewardTokenAmount);
    //     if(success) {
    //         //burn
    //         balanceOf[msg.sender] -= _rewardTokenAmount;
    //         totalSupply -= _rewardTokenAmount;
    //     }
    //     emit TokensRedeemed(msg.sender, _rewardTokenAmount);
    // }


}
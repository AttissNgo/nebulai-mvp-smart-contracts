// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "./USDTMock.sol";
import "chainlink/VRFCoordinatorV2Mock.sol";

import "../src/Governor.sol";
import "../src/DAO/Treasury.sol";
import "../src/Tokens/NEBToken.sol";
import "../src/Tokens/RewardToken.sol";

contract TestSetup is Test {

    // mocks
    USDTMock public usdt; 
    VRFCoordinatorV2Mock public vrf;
    uint64 public subscriptionId;

    // contracts
    Governor public governor;
    uint8 sigsRequired = 3;

    Treasury public treasury;
    NEBToken public nebToken;
    RewardToken public rewardToken;

    // test users
    address public alice = vm.addr(1);
    address public bob = vm.addr(2);
    address public carlos = vm.addr(3);
    address public david = vm.addr(4);
    address public erin = vm.addr(5);
    address public frank = vm.addr(6);
    address public grace = vm.addr(7);
    address public heidi = vm.addr(8);
    address public ivan = vm.addr(9);
    address public judy = vm.addr(10);
    address public kim = vm.addr(11);
    address public laura = vm.addr(12);
    address public mike = vm.addr(13);
    address public niaj = vm.addr(14);
    address public olivia = vm.addr(15);
    address public patricia = vm.addr(16);
    address public quentin = vm.addr(17);
    address public russel = vm.addr(18);
    address public sean = vm.addr(19);
    address public tabitha = vm.addr(20);
    address public ulrich = vm.addr(21);
    address public vincent = vm.addr(22);
    address public winona = vm.addr(23);
    address public xerxes = vm.addr(24);
    address public yanni = vm.addr(25);
    address public zorro = vm.addr(26);

    // test admins
    address public admin1 = vm.addr(100);
    address public admin2 = vm.addr(101);
    address public admin3 = vm.addr(102);
    address public admin4 = vm.addr(103);

    // issuer for reward token
    address public issuer = vm.addr(200);
    address public issuer2 = vm.addr(201);
    address[] public issuers = [issuer, issuer2];

    address[] public admins = [admin1, admin2, admin3, admin4];
    address[] public users = [alice,bob,carlos,david,erin,frank,grace,heidi,ivan,judy,kim,laura,mike,niaj,olivia,patricia,quentin,russel,sean,tabitha,ulrich,vincent,winona,xerxes,yanni,zorro];


    function _deployContracts() internal {
        // deploy usdt mock
        usdt = new USDTMock(); 
        // deploy VRF mock and fund subscription
        vrf = new VRFCoordinatorV2Mock(1, 1); 
        vm.prank(admin1);
        subscriptionId = vrf.createSubscription();
        vrf.fundSubscription(subscriptionId, 1 ether);
        // deploy governor
        governor = new Governor(admins, sigsRequired);
        // deploy treasury
        treasury = new Treasury(address(governor));
        // deploy neb
        nebToken = new NEBToken(address(treasury));
        // deploy reward token
        rewardToken = new RewardToken(address(governor), issuers);
        
        
        
        
    }

    function util_executeGovernorTx(uint256 _txIndex) internal {
        for(uint i; i < admins.length; ++i) {
            Governor.Transaction memory transaction = governor.getTransaction(_txIndex);
            if(!governor.adminHasSigned(_txIndex, admins[i]) && transaction.numSignatures < governor.signaturesRequired()) {
                vm.prank(admins[i]);
                governor.signTransaction(_txIndex);
            }
        } 
    }

    // function testSetNumber(uint256 x) public {
    //     counter.setNumber(x);
    //     assertEq(counter.number(), x);
    // }
}

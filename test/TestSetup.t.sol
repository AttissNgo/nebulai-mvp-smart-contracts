// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "./USDTMock.sol";
import "chainlink/VRFCoordinatorV2Mock.sol";

import "../src/Governor.sol";
import "../src/Whitelist.sol";
import "../src/JuryPool.sol";
import "../src/Court.sol";
import "../src/EscrowFactory.sol";
import "../src/Marketplace.sol";


contract TestSetup is Test {

    // mocks
    USDTMock public usdt; 
    VRFCoordinatorV2Mock public vrf;
    uint64 public subscriptionId;

    // contracts
    Governor public governor;
    uint8 sigsRequired = 3;

    Whitelist public whitelist;

    JuryPool public juryPool;
    Court public court;

    EscrowFactory public escrowFactory;
    Marketplace public marketplace;
    address[] public approvedTokens;

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
    
    address[] public admins = [admin1, admin2, admin3, admin4];
    address[] public users = [alice,bob,carlos,david,erin,frank,grace,heidi,ivan,judy,kim,laura,mike,niaj,olivia,patricia,quentin,russel,sean,tabitha,ulrich,vincent,winona,xerxes,yanni,zorro];

    function _setUp() internal {
        vm.startPrank(admin1);
        // deploy contracts
        usdt = new USDTMock(); 
        vrf = new VRFCoordinatorV2Mock(1, 1); 
        // vm.prank(admin1);
        subscriptionId = vrf.createSubscription();
        vrf.fundSubscription(subscriptionId, 100 ether);
        governor = new Governor(admins, sigsRequired);
        whitelist = new Whitelist(address(governor));
        juryPool = new JuryPool(address(governor), address(whitelist));

        uint64 nonce = vm.getNonce(admin1);
        address predictedMarketplace = computeCreateAddress(admin1, nonce + 2);

        court = new Court(
            address(governor), 
            address(juryPool),
            address(vrf),
            subscriptionId,
            predictedMarketplace ////////////////
        );
        approvedTokens.push(address(usdt));
        escrowFactory = new EscrowFactory();
        marketplace = new Marketplace(
            address(governor), 
            address(whitelist), 
            address(court), 
            address(escrowFactory),
            approvedTokens
        );
        // emit log_address(address(marketplace));
        // register new marketplace address in court
        // vm.prank(admin1);
        // bytes memory data = abi.encodeWithSignature("registerMarketplace(address)", address(marketplace));
        // uint256 txIndex = governor.proposeTransaction(address(court), 0, data);
        vm.stopPrank();
        // util_executeGovernorTx(txIndex);


        // supply ether & usdt
        for(uint i; i < users.length; ++i) {
            vm.deal(users[i], 10000 ether);
            usdt.mint(users[i], 10000 ether);
        }

        // label addresses
        _labelTestAddresses();
        
    }

    function _whitelistUsers() public {
        for(uint i; i < users.length; ++i) {
            vm.prank(admin1);
            whitelist.approveAddress(users[i]);
        }
    }

    function _registerJurors() public {
        uint256 stakeAmount = 100 ether;
        for(uint i; i < users.length; ++i) {
            vm.prank(users[i]);
            juryPool.registerAsJuror{value: stakeAmount}();
            stakeAmount += 10 ether;
        }
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

    function _labelTestAddresses() public {
        vm.label(address(usdt), "USDT");
        vm.label(address(governor), "Governor");

        vm.label(alice, "alice");
        vm.label(bob,"bob");
        vm.label(carlos, "carlos");
        vm.label(david, "david");
        vm.label(erin, "erin");
        vm.label(frank, "frank");
        vm.label(grace, "grace");
        vm.label(heidi, "heidi");
        vm.label(ivan, "ivan");
        vm.label(judy, "judy");
        vm.label(kim, "kim");
        vm.label(laura, "laura");
        vm.label(mike, "mike");
        vm.label(niaj, "niaj");
        vm.label(olivia, "olivia");
        vm.label(patricia, "patricia");
        vm.label(quentin, "quentin");
        vm.label(russel, "russel");
        vm.label(sean, "sean");
        vm.label(tabitha, "tabitha");
        vm.label(ulrich, "ulrich");
        vm.label(vincent, "vincent");
        vm.label(winona, "winona");
        vm.label(xerxes, "xerxes");
        vm.label(yanni, "yanni");
        vm.label(zorro, "zorro");
        vm.label(admin1, "admin1");
        vm.label(admin2, "admin2");
        vm.label(admin3, "admin3");
        vm.label(admin4, "admin4");
    }

}

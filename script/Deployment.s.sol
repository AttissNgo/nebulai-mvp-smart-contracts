// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import "../test/USDTMock.sol";
import "chainlink/VRFCoordinatorV2Mock.sol";

import "../src/NebulaiTestTokenFaucet.sol";

import "../src/Governor.sol";
import "../src/Whitelist.sol";
import "../src/JuryPool.sol";
import "../src/Court.sol";
import "../src/EscrowFactory.sol";
import "../src/Marketplace.sol";

contract DeploymentLocal is Script {

    // mocks
    USDTMock public usdt; 
    VRFCoordinatorV2Mock public vrf;
    uint64 public subscriptionId;

    NebulaiTestTokenFaucet public testToken;
    Governor public governor;
    Whitelist public whitelist;
    JuryPool public juryPool;
    Court public court;
    EscrowFactory public escrowFactory;
    Marketplace public marketplace;

    address[] public admins = [
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // localhost
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8, // localhost
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC // localhost
        // 0x537Df8463a09D0370DeE4dE077178300340b0030, // mumbai
        // 0xe540A4E03adeFB734ecE9d67E1A86199ee907Caa, // mumbai
        // 0x298334B4895392b0BA15261194cF1642A4adf9Fc // mumbai
    ];
    uint256 public sigsRequired = 2;
    
    address[] public users = [
        0x90F79bf6EB2c4f870365E785982E1f101E93b906, // localhost
        0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65, // localhost
        0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc, // localhost
        0x976EA74026E726554dB657fA54763abd0C3a0aa9, // localhost 
        0x14dC79964da2C08b23698B3D3cc7Ca32193d9955, // localhost
        0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f, // localhost
        0xa0Ee7A142d267C1f36714E4a8F75612F20a79720 // localhost
    ];

    address[] public approvedTokens;


    function setUp() public {}

    function run() public {

        uint256 pk_0 = vm.envUint("PK_ANVIL_0");
        // address anvil_1 = vm.addr(vm.envUint("PK_ANVIL_1"));

        vm.startBroadcast(pk_0);
        // deploy mocks
        usdt = new USDTMock(); 
        vrf = new VRFCoordinatorV2Mock(1, 1); 
        subscriptionId = vrf.createSubscription();
        vrf.fundSubscription(subscriptionId, 10 ether);
        // !!!! 
        // DON'T FORGET TO REGISTER CONSUMER WITH CHAINLINK WHEN DEPLOYING ON MUMBAI!!!
        // !!!!
        // deploy test token
        testToken = new NebulaiTestTokenFaucet();
        // deploy governor
        governor = new Governor(admins, sigsRequired);
        // deploy whitelist
        whitelist = new Whitelist(address(governor));
        // deploy jury pool
        juryPool = new JuryPool(address(governor), address(whitelist));
        // calculate future marketplace address
        uint64 nonce = vm.getNonce(vm.addr(pk_0));
        // console.log(nonce);
        address predictedMarketplace = computeCreateAddress(vm.addr(pk_0), nonce + 2);
        console.log(predictedMarketplace);
        // deploy court
        court = new Court(
            address(governor), 
            address(juryPool),
            address(vrf),
            subscriptionId,
            predictedMarketplace ////////////////
        );
        // deploy escrow factory
        escrowFactory = new EscrowFactory();
        // deploy marketplace
        approvedTokens.push(address(usdt));
        marketplace = new Marketplace(
            address(governor), 
            address(whitelist), 
            address(court), 
            address(escrowFactory),
            approvedTokens
        );

        // supply all users with usdt
        for(uint i; i < users.length; ++i) {
            usdt.mint(users[i], 10000 ether);
        }

        // supply all users with NEBTT
        for(uint i; i < users.length; ++i) {
            testToken.mint(users[1], 10000 ether);
        }

        // whitelist all anvil addresses
        for(uint i; i < admins.length; ++i) {
            whitelist.approveAddress(admins[i]);
        }
        for(uint i; i < users.length; ++i) {
            whitelist.approveAddress(users[i]);
        }
        
        vm.stopBroadcast();

        string memory obj1 = "some key";
        string memory usdtMockAddr = vm.serializeAddress(obj1, "USDTMockAddress", address(usdt));
        string memory vrfMockAddr = vm.serializeAddress(obj1, "VRFMockAddress", address(vrf));
        
        string memory testTokenAddr = vm.serializeAddress(obj1, "TestToken", address(testToken));
        string memory govAddr = vm.serializeAddress(obj1, "GovernorAddress", address(governor));
        string memory whitelistAddr = vm.serializeAddress(obj1, "WhitelistAddress", address(whitelist));
        string memory juryPoolAddr = vm.serializeAddress(obj1, "JuryPoolAddress", address(juryPool));
        string memory courtAddr = vm.serializeAddress(obj1, "CourtAddress", address(court));
        string memory escrowFactoryAddr = vm.serializeAddress(obj1, "EscrowFactoryAddress", address(escrowFactory));
        string memory marketplaceAddr = vm.serializeAddress(obj1, "MarketplaceAddress", address(marketplace));

        vm.writeJson(usdtMockAddr, "./deploymentInfo.json");
        vm.writeJson(vrfMockAddr, "./deploymentInfo.json");

        vm.writeJson(testTokenAddr, "./deploymentInfo.json");
        vm.writeJson(govAddr, "./deploymentInfo.json");
        vm.writeJson(whitelistAddr, "./deploymentInfo.json");
        vm.writeJson(juryPoolAddr, "./deploymentInfo.json");
        vm.writeJson(courtAddr, "./deploymentInfo.json");
        vm.writeJson(escrowFactoryAddr, "./deploymentInfo.json");
        vm.writeJson(marketplaceAddr, "./deploymentInfo.json");
    }
}

contract DeploymentMumbai is Script {

    NebulaiTestTokenFaucet public testToken;
    Governor public governor;
    Whitelist public whitelist;
    JuryPool public juryPool;
    Court public court;
    EscrowFactory public escrowFactory;
    Marketplace public marketplace;

    uint64 public subscriptionId = 2867;
    address public vrfMumbai = vrfMumbai;

    address[] public admins = [
        0x537Df8463a09D0370DeE4dE077178300340b0030, // attiss - deployer
        0x834B1AaB6E94462Cd092F9e7013F759ED4D61D1E, // test admin for whitelisting
        0x869752aF1b78BBA42329b9c5143A9c28af482E7f, // hussain
        0xb3fF81238C7F68A3EB73df4b58636Eddd88D9F55, // hussain
        0xe540A4E03adeFB734ecE9d67E1A86199ee907Caa, // attiss
        0x298334B4895392b0BA15261194cF1642A4adf9Fc // attiss
    ];
    uint256 public sigsRequired = 2;
    
    // address[] public users = [
    //     0x90F79bf6EB2c4f870365E785982E1f101E93b906, // localhost
    //     0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65, // localhost
    //     0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc, // localhost
    //     0x976EA74026E726554dB657fA54763abd0C3a0aa9, // localhost 
    //     0x14dC79964da2C08b23698B3D3cc7Ca32193d9955, // localhost
    //     0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f, // localhost
    //     0xa0Ee7A142d267C1f36714E4a8F75612F20a79720 // localhost
    // ];

    address[] public approvedTokens;


    function setUp() public {}

    function run() public {

        uint256 pk_0 = vm.envUint("PK_MUMBAI_0"); 

        vm.startBroadcast(pk_0);
        // !!!! 
        // DON'T FORGET TO REGISTER CONSUMER WITH CHAINLINK WHEN DEPLOYING ON MUMBAI!!!
        // !!!!
        // deploy test token
        testToken = new NebulaiTestTokenFaucet();
        // deploy governor
        governor = new Governor(admins, sigsRequired);
        // deploy whitelist
        whitelist = new Whitelist(address(governor));
        // deploy jury pool
        juryPool = new JuryPool(address(governor), address(whitelist));
        // calculate future marketplace address
        uint64 nonce = vm.getNonce(vm.addr(pk_0));
        // console.log(nonce);
        address predictedMarketplace = computeCreateAddress(vm.addr(pk_0), nonce + 2);
        console.log(predictedMarketplace);
        // deploy court
        court = new Court(
            address(governor), 
            address(juryPool),
            vrfMumbai,
            subscriptionId,
            predictedMarketplace ////////////////
        );
        // deploy escrow factory
        escrowFactory = new EscrowFactory();
        // deploy marketplace
        approvedTokens.push(address(testToken));
        marketplace = new Marketplace(
            address(governor), 
            address(whitelist), 
            address(court), 
            address(escrowFactory),
            approvedTokens
        );
        
        vm.stopBroadcast();

        string memory obj1 = "some key";
        string memory testTokenAddr = vm.serializeAddress(obj1, "TestToken", address(testToken));
        string memory govAddr = vm.serializeAddress(obj1, "GovernorAddress", address(governor));
        string memory whitelistAddr = vm.serializeAddress(obj1, "WhitelistAddress", address(whitelist));
        string memory juryPoolAddr = vm.serializeAddress(obj1, "JuryPoolAddress", address(juryPool));
        string memory courtAddr = vm.serializeAddress(obj1, "CourtAddress", address(court));
        string memory escrowFactoryAddr = vm.serializeAddress(obj1, "EscrowFactoryAddress", address(escrowFactory));
        string memory marketplaceAddr = vm.serializeAddress(obj1, "MarketplaceAddress", address(marketplace));

        vm.writeJson(testTokenAddr, "./deploymentInfo.json");
        vm.writeJson(govAddr, "./deploymentInfo.json");
        vm.writeJson(whitelistAddr, "./deploymentInfo.json");
        vm.writeJson(juryPoolAddr, "./deploymentInfo.json");
        vm.writeJson(courtAddr, "./deploymentInfo.json");
        vm.writeJson(escrowFactoryAddr, "./deploymentInfo.json");
        vm.writeJson(marketplaceAddr, "./deploymentInfo.json");
    }
}




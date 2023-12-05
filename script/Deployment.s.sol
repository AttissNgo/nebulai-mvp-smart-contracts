// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import "../test/USDTMock.sol";
import "chainlink/VRFCoordinatorV2Mock.sol";

import "../src/NebulaiTestTokenFaucet.sol";

import "../src/Governor.sol";
import "../src/Whitelist.sol";
import "../src/MediatorPool.sol";
import "../src/MediationService.sol";
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
    MediatorPool public mediatorPool;
    uint256 public minimumMediatorStake = 20 ether;
    MediationService public mediationService;
    EscrowFactory public escrowFactory;
    Marketplace public marketplace;

    address[] public admins = [
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // localhost
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8, // localhost
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC // localhost
    ];
    uint256 public sigsRequired = 2;
    
    address[] public users = [
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, 
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8, 
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC, 
        0x90F79bf6EB2c4f870365E785982E1f101E93b906, 
        0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65, 
        0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc, 
        0x976EA74026E726554dB657fA54763abd0C3a0aa9, 
        0x14dC79964da2C08b23698B3D3cc7Ca32193d9955, 
        0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f, 
        0xa0Ee7A142d267C1f36714E4a8F75612F20a79720, 
        0xBcd4042DE499D14e55001CcbB24a551F3b954096, 
        0x71bE63f3384f5fb98995898A86B02Fb2426c5788, 
        0xFABB0ac9d68B0B445fB7357272Ff202C5651694a, 
        0x1CBd3b2770909D4e10f157cABC84C7264073C9Ec, 
        0xdF3e18d64BC6A983f673Ab319CCaE4f1a57C7097, 
        0xcd3B766CCDd6AE721141F452C550Ca635964ce71, 
        0x2546BcD3c84621e976D8185a91A922aE77ECEc30, 
        0xbDA5747bFD65F08deb54cb465eB87D40e51B197E, 
        0xdD2FD4581271e230360230F9337D5c0430Bf44C0, 
        0x8626f6940E2eb28930eFb4CeF49B2d1F2C9C1199
    ];

    uint256[] public anvilPKs = [
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80,
        0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d,
        0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a,
        0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6,
        0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a,
        0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba,
        0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e,
        0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356,
        0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97,
        0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6,
        0xf214f2b2cd398c806f84e317254e0f0b801d0643303237d97a22a48e01628897,
        0x701b615bbdfb9de65240bc28bd21bbc0d996645a3dd57e7b12bc2bdf6f192c82,
        0xa267530f49f8280200edf313ee7af6b827f2a8bce2897751d06a843f644967b1,
        0x47c99abed3324a2707c28affff1267e45918ec8c3f20b8aa892e8b065d2942dd,
        0xc526ee95bf44d8fc405a158bb884d9d1238d99f0612e9f33d006bb0789009aaa,
        0x8166f546bab6da521a8369cab06c5d2b9e46670292d85c875ee9ec20e84ffb61,
        0xea6c44ac03bff858b476bba40716402b03e41b8e97e276d1baec7c37d42484a0,
        0x689af8efa8c651a91ad287602527f3af2fe9f6501a7ac4b061667b5a93e037fd,
        0xde9be858da4a475276426320d5e9262ecfc3ba460bfac56360bfa6c4c28b4ee0,
        0xdf57089febbacf7ba0bc227dafbffa9fc08a93fdc68e1e42411a14efcf23656e
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
        // deploy test token
        testToken = new NebulaiTestTokenFaucet();
        // deploy governor
        governor = new Governor(admins, sigsRequired);
        // deploy whitelist
        whitelist = new Whitelist(address(governor));
        // deploy jury pool
        mediatorPool = new MediatorPool(address(governor), address(whitelist), minimumMediatorStake);
        // calculate future marketplace address
        uint64 nonce = vm.getNonce(vm.addr(pk_0));
        address predictedMarketplace = computeCreateAddress(vm.addr(pk_0), nonce + 2);
        console.log(predictedMarketplace);
        // deploy mediationService
        mediationService = new MediationService(
            address(governor), 
            address(mediatorPool),
            address(vrf),
            subscriptionId,
            predictedMarketplace ////////////////
        );
        // deploy escrow factory
        escrowFactory = new EscrowFactory();
        // deploy marketplace
        approvedTokens.push(address(usdt));
        approvedTokens.push(address(testToken));
        marketplace = new Marketplace(
            address(governor), 
            address(whitelist), 
            address(mediationService), 
            address(escrowFactory),
            approvedTokens
        );

        // supply all users with usdt
        for(uint i; i < users.length; ++i) {
            usdt.mint(users[i], 10000 ether);
        }

        // supply all addresses with NEBTT
        for(uint i; i < users.length; ++i) {
            testToken.mint(users[i], 10000 ether);
        }

        // whitelist all anvil addresses
        for(uint i; i < users.length; ++i) {
            whitelist.approveAddress(users[i]);
        }
        vm.stopBroadcast();

        string memory obj1 = "local";
        string memory valueKey = ".anvil";

        string memory usdtMockAddr = vm.serializeAddress(obj1, "USDTMockAddress", address(usdt));
        string memory vrfMockAddr = vm.serializeAddress(obj1, "VRFMockAddress", address(vrf));
        
        string memory testTokenAddr = vm.serializeAddress(obj1, "TestToken", address(testToken));
        string memory govAddr = vm.serializeAddress(obj1, "GovernorAddress", address(governor));
        string memory whitelistAddr = vm.serializeAddress(obj1, "WhitelistAddress", address(whitelist));
        string memory mediatorPoolAddr = vm.serializeAddress(obj1, "MediatorPoolAddress", address(mediatorPool));
        string memory mediationServiceAddr = vm.serializeAddress(obj1, "MediationServiceAddress", address(mediationService));
        string memory escrowFactoryAddr = vm.serializeAddress(obj1, "EscrowFactoryAddress", address(escrowFactory));
        string memory marketplaceAddr = vm.serializeAddress(obj1, "MarketplaceAddress", address(marketplace));

        vm.writeJson(usdtMockAddr, "./deploymentInfo.json", valueKey);
        vm.writeJson(vrfMockAddr, "./deploymentInfo.json", valueKey);

        vm.writeJson(testTokenAddr, "./deploymentInfo.json", valueKey);
        vm.writeJson(govAddr, "./deploymentInfo.json", valueKey);
        vm.writeJson(whitelistAddr, "./deploymentInfo.json", valueKey);
        vm.writeJson(mediatorPoolAddr, "./deploymentInfo.json", valueKey);
        vm.writeJson(mediationServiceAddr, "./deploymentInfo.json", valueKey);
        vm.writeJson(escrowFactoryAddr, "./deploymentInfo.json", valueKey);
        vm.writeJson(marketplaceAddr, "./deploymentInfo.json", valueKey);

        // register mediators - users[0] will NOT be registered
        uint256 mediatorMinStake = mediatorPool.minimumStake();
        for(uint i = 1; i < anvilPKs.length; ++i) {
            vm.startBroadcast(anvilPKs[i]);
            mediatorPool.registerAsMediator{value: mediatorMinStake}();
            vm.stopBroadcast();
        }
    }
}

contract DeploymentMumbai is Script {

    NebulaiTestTokenFaucet public testToken;
    Governor public governor;
    Whitelist public whitelist;
    MediatorPool public mediatorPool;
    uint256 public minimumMediatorStake = 0.01 ether; 
    MediationService public mediationService;
    EscrowFactory public escrowFactory;
    Marketplace public marketplace;

    uint64 public subscriptionId = 2867;
    address public vrfMumbai = 0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed;

    address[] public admins = [
        0x537Df8463a09D0370DeE4dE077178300340b0030, // attiss - deployer
        0x834B1AaB6E94462Cd092F9e7013F759ED4D61D1E, // test admin for whitelisting
        0x869752aF1b78BBA42329b9c5143A9c28af482E7f, // hussain
        0xb3fF81238C7F68A3EB73df4b58636Eddd88D9F55, // hussain
        0xe540A4E03adeFB734ecE9d67E1A86199ee907Caa, // attiss
        0x298334B4895392b0BA15261194cF1642A4adf9Fc // attiss
    ];
    uint256 public sigsRequired = 2;

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
        mediatorPool = new MediatorPool(address(governor), address(whitelist), minimumMediatorStake);
        // calculate future marketplace address
        uint64 nonce = vm.getNonce(vm.addr(pk_0));
        address predictedMarketplace = computeCreateAddress(vm.addr(pk_0), nonce + 2);
        console.log(predictedMarketplace);
        // deploy mediationService
        mediationService = new MediationService(
            address(governor), 
            address(mediatorPool),
            vrfMumbai,
            subscriptionId,
            predictedMarketplace 
        );
        // deploy escrow factory
        escrowFactory = new EscrowFactory();
        // deploy marketplace
        approvedTokens.push(address(testToken));
        marketplace = new Marketplace(
            address(governor), 
            address(whitelist), 
            address(mediationService), 
            address(escrowFactory),
            approvedTokens
        );
        
        vm.stopBroadcast();

        string memory obj1 = "mumbai";
        string memory valueKey = ".mumbai";

        string memory testTokenAddr = vm.serializeAddress(obj1, "TestToken", address(testToken));
        string memory govAddr = vm.serializeAddress(obj1, "GovernorAddress", address(governor));
        string memory whitelistAddr = vm.serializeAddress(obj1, "WhitelistAddress", address(whitelist));
        string memory mediatorPoolAddr = vm.serializeAddress(obj1, "MediatorPoolAddress", address(mediatorPool));
        string memory mediationServiceAddr = vm.serializeAddress(obj1, "MediationServiceAddress", address(mediationService));
        string memory escrowFactoryAddr = vm.serializeAddress(obj1, "EscrowFactoryAddress", address(escrowFactory));
        string memory marketplaceAddr = vm.serializeAddress(obj1, "MarketplaceAddress", address(marketplace));

        vm.writeJson(testTokenAddr, "./deploymentInfo.json", valueKey);
        vm.writeJson(govAddr, "./deploymentInfo.json", valueKey);
        vm.writeJson(whitelistAddr, "./deploymentInfo.json", valueKey);
        vm.writeJson(mediatorPoolAddr, "./deploymentInfo.json", valueKey);
        vm.writeJson(mediationServiceAddr, "./deploymentInfo.json", valueKey);
        vm.writeJson(escrowFactoryAddr, "./deploymentInfo.json", valueKey);
        vm.writeJson(marketplaceAddr, "./deploymentInfo.json", valueKey);
    }
}




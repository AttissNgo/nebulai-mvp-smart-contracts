// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console, console2} from "forge-std/Script.sol";

import "../src/Governor.sol";
import "../src/Whitelist.sol";
import "../src/MediatorPool.sol";
import "../src/MediationService.sol";
import "../src/EscrowFactory.sol";
import "../src/Marketplace.sol";
import "../test/USDTMock.sol";
import "chainlink/VRFCoordinatorV2Mock.sol";
import "../src/NebulaiTestTokenFaucet.sol";
import "../src/MediationServiceBETA.sol";

contract DeploymentLib is Script {
    
    // local deployment flag
    bool public isLocalDeployment = false;

    // contracts
    Governor public governor;
    Whitelist public whitelist;
    MediatorPool public mediatorPool;
    MediationService public mediationService;
    EscrowFactory public escrowFactory;
    Marketplace public marketplace;
    address[] public contractAddresses;

    // mocks & testnet contracts
    NebulaiTestTokenFaucet public testToken;
    address public testTokenAddress;
    USDTMock public usdt; 
    address public usdtAddress;
    VRFCoordinatorV2Mock public vrfMock;
    address vrfMockAddress;
    MediationServiceBETA public mediationServiceBETA;

    // config variables
        // vrf
    uint64 public subscriptionId; 
    bytes32 public keyHash; 
        // governor
    uint256 public sigsRequired;
        // mediator pool
    uint256 public minimumMediatorStake; 
        // marketplace
    address[] public approvedTokens;
        // addresses and ABI output
    mapping(address => string) public contractNames;
    string public json_obj;
    string public json_addressValueKey;
    string public constant JSON_OUT_PATH = "./json_out/deployedAddresses.json";

    // EOAs
    address[] public admins;
    address[] public users;
    address[] public mediators;

    function _setAdmins(address[] memory _admins) internal {
        for (uint i; i < _admins.length; ++i) {
            admins.push(_admins[i]);
        }
    }

    function _setUsers(address[] memory _users) internal {
        for (uint i; i < _users.length; ++i) {
            users.push(_users[i]);
        }
    }

    // deployment
    function _deployMocks() internal {
        console.log("deploying mocks...");
        usdt = new USDTMock(); 
        usdtAddress = address(usdt);
        vrfMock = new VRFCoordinatorV2Mock(1, 1); 
        vrfMockAddress = address(vrfMock);
        subscriptionId = vrfMock.createSubscription();
        vrfMock.fundSubscription(subscriptionId, 10 ether);
        console.log("=== === mocks deployed === ===");
    }

    function _deployTestToken() internal {
        console.log("deploying test token (NEBTT)...");
        testToken = new NebulaiTestTokenFaucet();
        testTokenAddress = address(testToken);
        console.log("=== === test token deployed === ===");
    }

    function _deployContracts(address _deployer) internal {
        console.log("deploying contracts...");
        governor = new Governor(admins, sigsRequired);
        whitelist = new Whitelist(address(governor));
        mediatorPool = new MediatorPool(address(governor), address(whitelist), minimumMediatorStake);
        uint64 nonce = vm.getNonce(_deployer);
        address predictedMarketplace = computeCreateAddress(_deployer, nonce + 2);
        mediationService = new MediationService(
            address(governor), 
            address(mediatorPool),
            vrfMockAddress,
            keyHash,
            subscriptionId,
            predictedMarketplace 
        );
        escrowFactory = new EscrowFactory();
        marketplace = new Marketplace(
            address(governor), 
            address(whitelist), 
            address(mediationService), 
            address(escrowFactory),
            approvedTokens
        );
        console.log("=== === contracts deployed === ===");
    }

    function _deployContractsBETA(address _deployer) internal {
        console.log("deploying contracts for BETA testing...");
        governor = new Governor(admins, sigsRequired);
        whitelist = new Whitelist(address(governor));
        mediatorPool = new MediatorPool(address(governor), address(whitelist), minimumMediatorStake);
        uint64 nonce = vm.getNonce(_deployer);
        address predictedMarketplace = computeCreateAddress(_deployer, nonce + 2);
        mediationServiceBETA = new MediationServiceBETA(
            address(governor), 
            address(mediatorPool),
            vrfMockAddress,
            keyHash,
            subscriptionId,
            predictedMarketplace 
        );
        escrowFactory = new EscrowFactory();
        marketplace = new Marketplace(
            address(governor), 
            address(whitelist), 
            address(mediationServiceBETA), 
            address(escrowFactory),
            approvedTokens
        );
        console.log("=== === BETA testing contracts deployed === ===");
    }

    // environment
        // supply test tokens
    function _supplyTestTokens(address[] memory _users, uint256 _amount) internal {
        for (uint i; i < _users.length; ++i) {
            usdt.mint(_users[i], _amount);
            testToken.mint(_users[i], _amount);
        }
    }
        // whitelist users
    function _whitelistUsers(address[] memory _users) internal {
        for (uint i; i < _users.length; ++i) {
            whitelist.approveAddress(_users[i]);
        }
    }
        // register mediators + stake
    function _registerMediators(address[] memory _mediators) internal {
        for (uint i; i < _mediators.length; ++i) {
            mediatorPool.registerMediator(_mediators[i]);
        }
    }

    // addresss & ABI output
        // set contract names/addresses in mapping & array
    function _setContractNames() internal {
        contractNames[address(governor)] = "Governor";
        contractNames[address(whitelist)] = "Whitelist";
        contractNames[address(mediatorPool)] = "MediatorPool";
        contractNames[address(mediationService)] = "MediationService";
        contractNames[address(escrowFactory)] = "EscrowFactory";
        contractNames[address(marketplace)] = "Marketplace";

        contractAddresses.push(address(governor));
        contractAddresses.push(address(whitelist));
        contractAddresses.push(address(mediatorPool));
        contractAddresses.push(address(mediationService));
        contractAddresses.push(address(escrowFactory));
        contractAddresses.push(address(marketplace));
    
        if(isLocalDeployment) {
            contractNames[address(testToken)] = "TestToken";
            contractAddresses.push(address(testToken));
            contractNames[address(vrfMock)] = "VRFMock";
            contractAddresses.push(address(vrfMock));
        }
    }
        // write deployed addresses
    function _serializeAddr(
        string memory _object, 
        string memory _keyName, 
        address _addr
    ) 
        internal
        returns (string memory)
    {
        string memory serializedAddress = vm.serializeAddress(_object, _keyName, _addr);
        return serializedAddress;
    }

    function _writeToJsonOut(string memory _serializedValue, string memory _filePath, string memory _valueKey) internal {
        vm.writeJson(_serializedValue, _filePath, _valueKey);
    }
        // copy ABIs
    function _copyABIsFromOut() internal {
        string memory governorAbi = vm.readFile("./out/Governor.sol/Governor.json");
        string memory path = "./json_out/GovernorAbi.json";
        vm.writeFile(path, governorAbi);
        string memory whitelistAbi = vm.readFile("./out/Whitelist.sol/Whitelist.json");
        path = "./json_out/WhitelistAbi.json";
        vm.writeFile(path, whitelistAbi);
        string memory mediatorPoolAbi = vm.readFile("./out/MediatorPool.sol/MediatorPool.json");
        path = "./json_out/MediatorPoolAbi.json";
        vm.writeFile(path, mediatorPoolAbi);
        string memory mediationServiceAbi = vm.readFile("./out/MediationService.sol/MediationService.json");
        path = "./json_out/MediationServiceAbi.json";
        vm.writeFile(path, mediationServiceAbi);
        string memory escrowFactoryAbi = vm.readFile("./out/EscrowFactory.sol/EscrowFactory.json");
        path = "./json_out/EscrowFactoryAbi.json";
        vm.writeFile(path, escrowFactoryAbi);
        string memory marketplaceAbi = vm.readFile("./out/Marketplace.sol/Marketplace.json");
        path = "./json_out/MarketplaceAbi.json";
        vm.writeFile(path, marketplaceAbi);
    }
    
    // handle all outputs
    function _handleJSON_out() internal {
        _setContractNames();
        console.log("copying deployed addresses...");
        for (uint i; i < contractAddresses.length; ++i) {
            string memory serializedAddress = _serializeAddr(json_obj, contractNames[contractAddresses[i]], contractAddresses[i]);
            if (contractAddresses[i] == address(0)) {
                serializedAddress = _serializeAddr(json_obj, "Mediation Service", address(mediationServiceBETA));
            }
            _writeToJsonOut(
                serializedAddress,
                JSON_OUT_PATH, 
                json_addressValueKey
            );
        }
        console.log("copying ABIs...");
        _copyABIsFromOut();
    }

} 

contract DeploymentLocal is DeploymentLib {

    address[] public anvilAdmins = [
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // localhost
        0x70997970C51812dc3A010C7d01b50e0d17dc79C8, // localhost
        0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC // localhost
    ];

    address[] public anvilUsers = [
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

    address[] public anvilMediators = [ // anvil accounts (except account 0)
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
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80, // skip this one for staking in mediator pool!
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

    function setUp() public {
        isLocalDeployment = true;
        keyHash = 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f; // mumbai testnet 500 gwei keyhash - doesn't actually matter in local since we use mocks
        sigsRequired = 2;
        minimumMediatorStake = 20 ether;
        _setAdmins(anvilAdmins);
        _setUsers(anvilUsers);
        json_obj = "local";
        json_addressValueKey = ".anvil";
    }

    function run() public {
        uint256 deployerPK = vm.envUint("PK_ANVIL_0");
        address deployer = vm.addr(deployerPK);
        
        vm.startBroadcast(deployerPK);
        // deploy mocks
        _deployMocks();
        _deployTestToken();
        approvedTokens.push(usdtAddress);
        approvedTokens.push(testTokenAddress);
        // deploy contracts
        _deployContracts(deployer);
        // set up env
        _supplyTestTokens(users, 10000 ether);
        _whitelistUsers(users);
        _registerMediators(anvilMediators);
        vm.stopBroadcast();

        // json out
        _handleJSON_out();

        // mediators stake
        for (uint i = 1; i < anvilPKs.length; ++i) {
            uint256 additionalStake = i * 1 ether;
            vm.startBroadcast(anvilPKs[i]);
            mediatorPool.stake{value: minimumMediatorStake + additionalStake}();
            vm.stopBroadcast();
        }
    }
}

contract DeploymentBETA is DeploymentLib {
    address[] public mumbaiAdmins = [
        0x537Df8463a09D0370DeE4dE077178300340b0030, // attiss - deployer
        0x834B1AaB6E94462Cd092F9e7013F759ED4D61D1E, // test admin for whitelisting
        0x869752aF1b78BBA42329b9c5143A9c28af482E7f, // hussain
        0xb3fF81238C7F68A3EB73df4b58636Eddd88D9F55, // hussain
        0xe540A4E03adeFB734ecE9d67E1A86199ee907Caa, // attiss
        0x298334B4895392b0BA15261194cF1642A4adf9Fc // attiss
    ];

    function setUp() public {
        keyHash = 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f; // mumbai testnet 500 gwei keyhash - doesn't actually matter in local since we use mocks
        subscriptionId = 2867;
        vrfMockAddress = 0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed;
        sigsRequired = 2;
        usdtAddress = 0xA02f6adc7926efeBBd59Fd43A84f4E0c0c91e832; // usdt mumai - 6 decimals
        minimumMediatorStake = 0.001 ether;
        _setAdmins(mumbaiAdmins);
        json_obj = "beta";
        json_addressValueKey = ".beta_mumbai";
    }

    function run() public {
        uint256 deployerPK = vm.envUint("PK_MUMBAI_0");
        address deployer = vm.addr(deployerPK);
        
        vm.startBroadcast(deployerPK);
        _deployTestToken();
        approvedTokens.push(usdtAddress);
        approvedTokens.push(testTokenAddress);
        // deploy contracts
        _deployContractsBETA(deployer);
        vm.stopBroadcast();

        // json out
        _handleJSON_out();
        string memory mediationServiceBETAAbi = vm.readFile("./out/MediationServiceBETA.sol/MediationServiceBETA.json");
        string memory path = "./json_out/MediationServiceBETAAbi.json";
        vm.writeFile(path, mediationServiceBETAAbi);
    }

}

contract DeploymentMumbai is DeploymentLib {
    
    function setUp() public {
        // handle VRF subscription from real source !
    }
}





// contract DeploymentMumbai is Script {

//     NebulaiTestTokenFaucet public testToken;
//     Governor public governor;
//     Whitelist public whitelist;
//     MediatorPool public mediatorPool;
//     uint256 public minimumMediatorStake = 0.01 ether; 
//     MediationService public mediationService;
//     EscrowFactory public escrowFactory;
//     Marketplace public marketplace;

//     uint64 public subscriptionId = 2867;
//     address public vrfMumbai = 0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed;

//     address[] public admins = [
//         0x537Df8463a09D0370DeE4dE077178300340b0030, // attiss - deployer
//         0x834B1AaB6E94462Cd092F9e7013F759ED4D61D1E, // test admin for whitelisting
//         0x869752aF1b78BBA42329b9c5143A9c28af482E7f, // hussain
//         0xb3fF81238C7F68A3EB73df4b58636Eddd88D9F55, // hussain
//         0xe540A4E03adeFB734ecE9d67E1A86199ee907Caa, // attiss
//         0x298334B4895392b0BA15261194cF1642A4adf9Fc // attiss
//     ];
//     uint256 public sigsRequired = 2;

//     address[] public approvedTokens;

//     function setUp() public {}

//     function run() public {

//         uint256 pk_0 = vm.envUint("PK_MUMBAI_0"); 

//         vm.startBroadcast(pk_0);
//         // !!!! 
//         // DON'T FORGET TO REGISTER CONSUMER WITH CHAINLINK WHEN DEPLOYING ON MUMBAI!!!
//         // !!!!
//         // deploy test token
//         testToken = new NebulaiTestTokenFaucet();
//         // deploy governor
//         governor = new Governor(admins, sigsRequired);
//         // deploy whitelist
//         whitelist = new Whitelist(address(governor));
//         // deploy jury pool
//         mediatorPool = new MediatorPool(address(governor), address(whitelist), minimumMediatorStake);
//         // calculate future marketplace address
//         uint64 nonce = vm.getNonce(vm.addr(pk_0));
//         address predictedMarketplace = computeCreateAddress(vm.addr(pk_0), nonce + 2);
//         console.log(predictedMarketplace);
//         // deploy mediationService
//         mediationService = new MediationService(
//             address(governor), 
//             address(mediatorPool),
//             vrfMumbai,
//             subscriptionId,
//             predictedMarketplace 
//         );
//         // deploy escrow factory
//         escrowFactory = new EscrowFactory();
//         // deploy marketplace
//         approvedTokens.push(address(testToken));
//         marketplace = new Marketplace(
//             address(governor), 
//             address(whitelist), 
//             address(mediationService), 
//             address(escrowFactory),
//             approvedTokens
//         );
        
//         vm.stopBroadcast();

//         string memory obj1 = "mumbai";
//         string memory valueKey = ".mumbai";

//         string memory testTokenAddr = vm.serializeAddress(obj1, "TestToken", address(testToken));
//         string memory govAddr = vm.serializeAddress(obj1, "GovernorAddress", address(governor));
//         string memory whitelistAddr = vm.serializeAddress(obj1, "WhitelistAddress", address(whitelist));
//         string memory mediatorPoolAddr = vm.serializeAddress(obj1, "MediatorPoolAddress", address(mediatorPool));
//         string memory mediationServiceAddr = vm.serializeAddress(obj1, "MediationServiceAddress", address(mediationService));
//         string memory escrowFactoryAddr = vm.serializeAddress(obj1, "EscrowFactoryAddress", address(escrowFactory));
//         string memory marketplaceAddr = vm.serializeAddress(obj1, "MarketplaceAddress", address(marketplace));

//         vm.writeJson(testTokenAddr, "./deploymentInfo.json", valueKey);
//         vm.writeJson(govAddr, "./deploymentInfo.json", valueKey);
//         vm.writeJson(whitelistAddr, "./deploymentInfo.json", valueKey);
//         vm.writeJson(mediatorPoolAddr, "./deploymentInfo.json", valueKey);
//         vm.writeJson(mediationServiceAddr, "./deploymentInfo.json", valueKey);
//         vm.writeJson(escrowFactoryAddr, "./deploymentInfo.json", valueKey);
//         vm.writeJson(marketplaceAddr, "./deploymentInfo.json", valueKey);
//     }
// }




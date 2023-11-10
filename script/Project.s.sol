// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";
import "src/DataStructuresLibrary.sol";
import "src/Interfaces/IMediationService.sol";

interface MarketplaceIface {
    function calculateNebulaiTxFee(uint256 _projectFee) external view returns (uint256);
    function createProject(
        address _provider,
        address _paymentToken,
        uint256 _projectFee,
        uint256 _providerStake,
        uint256 _dueDate,
        uint256 _reviewPeriodLength,
        string memory _detailsURI
    ) 
        external 
        payable
        returns (uint256); 
    function activateProject(uint256) external payable;
    function approveProject(uint256) external;
    function cancelProject(uint256) external;
    function discontinueProject(uint256, uint256, uint256, string memory) external;
    function completeProject(uint256) external;
    function challengeProject(uint256, uint256, uint256, string memory) external;
    function disputeProject(uint256, uint256, uint256) external returns (uint256);
    function getDisputeId(uint256) external view returns (uint256);
    function projectIds() external view returns (uint256);
    function getProject(uint256) external view returns (DataStructuresLibrary.Project memory);
}

interface VRFIface {
    function fulfillRandomWords(uint256 _requestId, address _consumer) external;
}

contract ProjectStorage is Script, DataStructuresLibrary {

    uint256 projectFee = 100 ether;
    uint256 providerStake = 10 ether;
    uint256 reviewPeriodLength = 3 days;
    string detailsURI = "ipfs://someDetails/";
    uint256 changeOrderProjectFee = 75 ether;
    uint256 changeOrderStakeForfeit = 5 ether;
    string changeOrderDetails = "ipfs://changeOrderURI";
    string[] evidence = ["ipfs://evidence1URI", "ipfs://evidence2URI"];

    string json = vm.readFile("./deploymentInfo.json");
    address marketplaceAddr = vm.parseJsonAddress(json, ".anvil.MarketplaceAddress");
    address testTokenAddr = vm.parseJsonAddress(json, ".anvil.TestToken");
    address mediationServiceAddr = vm.parseJsonAddress(json, ".anvil.MediationServiceAddress");
    address vrfMockAddr = vm.parseJsonAddress(json, ".anvil.VRFMockAddress");

    MarketplaceIface marketplace = MarketplaceIface(marketplaceAddr);
    IERC20 testToken = IERC20(testTokenAddr);
    IMediationService mediationService = IMediationService(mediationServiceAddr);
    VRFIface vrf = VRFIface(vrfMockAddr);

    address[] public anvilAddresses = [
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
}

contract CreateProject is Script, ProjectStorage {

    uint nonce = 1;
 
    /**
     * creates project with random buyer and provider from anvil addresses
     */
    function createProject() public returns (uint256)
    {
        (address buyer, address provider) = randomBuyerAndProvider();
        vm.startBroadcast(buyer);
        uint256 txFee = marketplace.calculateNebulaiTxFee(projectFee);
        testToken.approve(marketplaceAddr, projectFee + txFee);
        uint256 projectId = marketplace.createProject(
            provider,
            testTokenAddr,
            projectFee,
            providerStake,
            block.timestamp + 10 days,
            reviewPeriodLength,
            detailsURI
        );
        vm.stopBroadcast();
        console.log("new project created - id: ", projectId);
        return projectId;
    }

    function cancelProject(uint256 _projectId) public returns (uint256) {
        Project memory project = marketplace.getProject(_projectId);
        vm.startBroadcast(getWallet(project.buyer));
        marketplace.cancelProject(_projectId);
        vm.stopBroadcast();
        console.log("project %s canceled", project.projectId);
        return project.projectId;
    }

    function activateProject(uint256 _projectId) public returns (uint256) {
        Project memory project = marketplace.getProject(_projectId);
        vm.startBroadcast(getWallet(project.provider));
        // console.log(project.provider);
        testToken.approve(marketplaceAddr, providerStake);
        marketplace.activateProject(_projectId);
        vm.stopBroadcast();
        console.log("project %s activated", project.projectId);
        return project.projectId;
    }

    function discontinueProject(uint256 _projectId) public returns (uint256) {
        Project memory project = marketplace.getProject(_projectId);
        vm.startBroadcast(getWallet(project.buyer)); 
        marketplace.discontinueProject(_projectId, changeOrderProjectFee, changeOrderStakeForfeit, changeOrderDetails);
        vm.stopBroadcast();
        console.log("project %s discontinued", project.projectId);
        return project.projectId;
    }

    function completeProject(uint256 _projectId) public returns (uint256) {
        Project memory project = marketplace.getProject(_projectId);
        vm.startBroadcast(getWallet(project.provider));
        marketplace.completeProject(_projectId);
        vm.stopBroadcast();
        console.log("project %s completed", project.projectId);
        return project.projectId;
    }

    function approveProject(uint256 _projectId) public returns (uint256) {
        Project memory project = marketplace.getProject(_projectId);
        vm.startBroadcast(getWallet(project.buyer));
        marketplace.approveProject(_projectId);
        vm.stopBroadcast();
        console.log("project %s approved", project.projectId);
        return project.projectId;
    }

    function challengeProject(uint256 _projectId) public returns (uint256) {
        Project memory project = marketplace.getProject(_projectId);
        vm.startBroadcast(getWallet(project.buyer)); 
        marketplace.challengeProject(_projectId, changeOrderProjectFee, changeOrderStakeForfeit, changeOrderDetails);
        vm.stopBroadcast();
        console.log("project %s challenged", project.projectId);
        return project.projectId;
    }

    function disputeProject(uint256 _projectId) public returns (uint256, uint256) {
        // make sure time has been advanced in EVM!
        Project memory project = marketplace.getProject(_projectId);
        vm.startBroadcast(getWallet(project.buyer)); 
        uint256 disputeId = marketplace.disputeProject(_projectId, changeOrderProjectFee, changeOrderStakeForfeit);
        vm.stopBroadcast();
        console.log("project %s disputed. Dispute id: %s", project.projectId, disputeId);
        return (project.projectId, disputeId);
    }

    function createMultipleProjects() public {
        // created
        uint256 projectId = createProject();
        // cancelled
        projectId = createProject();
        cancelProject(projectId);
        // active
        projectId = createProject();
        activateProject(projectId);
        // discontinued
        projectId = createProject();
        activateProject(projectId);
        discontinueProject(projectId);
        // complete 
        projectId = createProject();
        activateProject(projectId);
        completeProject(projectId);
        // approved
        projectId = createProject();
        activateProject(projectId);
        completeProject(projectId);
        approveProject(projectId);
        // challenged - create 10 projects!
        for(uint i; i < 10; ++i) {
            projectId = createProject();
            activateProject(projectId);
            completeProject(projectId);
            challengeProject(projectId);
        }
    }

    function createMultipleDisputes() public {
        // make sure to advance time before calling!!!
        bool oneChallengedProjectPreserved = false;
        uint256 numProjects = marketplace.projectIds();
        for(uint i = 1; i <= numProjects; ++i) {
            Project memory project = marketplace.getProject(i);
            if(project.status == Status.Challenged) {
                if(!oneChallengedProjectPreserved) {
                    oneChallengedProjectPreserved = true;
                } else {
                    disputeProject(i);
                }
            }
        }
    }

    /////////////////////
    ///   MEDIATION   ///
    /////////////////////

    function payFeesAndSelectMediators(uint256 _projectId) public {
        Project memory project = marketplace.getProject(_projectId);
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(project.projectId));
        address claimant = getWallet(dispute.claimant);
        address respondent = getWallet(dispute.respondent);
        uint256 mediationFee = mediationService.calculateMediationFee(dispute.isAppeal);
        vm.startBroadcast(claimant);
        mediationService.payMediationFee{value: mediationFee}(dispute.disputeId, evidence);
        vm.stopBroadcast();
        vm.startBroadcast(respondent);
        vm.recordLogs();
        mediationService.payMediationFee{value: mediationFee}(dispute.disputeId, evidence);
        VmSafe.Log[] memory entries = vm.getRecordedLogs(); 
        uint256 requestId = uint(bytes32(entries[2].data));
        vrf.fulfillRandomWords(requestId, mediationServiceAddr);
        console.log("fees paid and mediators selected");
        Panel memory panel = mediationService.getPanel(dispute.disputeId);
        console.log("drawn mediators: ");
        for(uint i; i < panel.drawnMediators.length; ++i) {
            console.log(panel.drawnMediators[i]);
        }
        vm.stopBroadcast();
    }

    function mediatorsAccept(uint256 _projectId) public {
        Project memory project = marketplace.getProject(_projectId);
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(project.projectId));
        Panel memory panel = mediationService.getPanel(dispute.disputeId);
        for(uint i; i < mediationService.mediatorsNeeded(dispute.disputeId); ++i) {
            address mediator = getWallet(panel.drawnMediators[i]);
            vm.startBroadcast(mediator);
            mediationService.acceptCase{value: mediationService.mediatorFlatFee()}(dispute.disputeId);
            vm.stopBroadcast();
        } 
        console.log("mediators confirmed");
        panel = mediationService.getPanel(dispute.disputeId);
        console.log("confirmed mediators: ");
        for(uint i; i < panel.confirmedMediators.length; ++i) {
            console.log(panel.confirmedMediators[i]);
        }
    } 

    function mediatorsCommitVotes(uint256 _projectId, bool _petitionGranted) public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(_projectId));
        Panel memory panel = mediationService.getPanel(dispute.disputeId);
        bool vote = _petitionGranted ? true : false;
        bytes32 commit = keccak256(abi.encodePacked(vote, "someSalt"));
        for(uint i; i < panel.confirmedMediators.length; ++i) {
            address mediator = getWallet(panel.confirmedMediators[i]);
            vm.startBroadcast(mediator);
            mediationService.commitVote(dispute.disputeId, commit);
            vm.stopBroadcast();
        }
        console.log("votes committed");
    }

    function mediatorsRevealVotes(uint256 _projectId, bool _petitionGranted) public {
        Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(_projectId));
        Panel memory panel = mediationService.getPanel(dispute.disputeId);
        bool vote = _petitionGranted ? true : false;
        for(uint i; i < panel.confirmedMediators.length; ++i) {
            address mediator = getWallet(panel.confirmedMediators[i]);
            vm.startBroadcast(mediator);
            mediationService.revealVote(dispute.disputeId, vote, "someSalt");
            vm.stopBroadcast();
        }
        console.log("votes revealed");
        dispute = mediationService.getDispute(dispute.disputeId);
        console.log("petition granted: %s", dispute.granted);
    }   

    function resolveMediation(uint256 _projectId, bool _petitionGranted) public {
        console.log("--------------------");
        console.log("resolving mediation for project id %s", _projectId);
        console.log("--------------------");
        payFeesAndSelectMediators(_projectId);
        mediatorsAccept(_projectId);
        mediatorsCommitVotes(_projectId, _petitionGranted);
        mediatorsRevealVotes(_projectId, _petitionGranted);
    }

    function resolveAllMediation() public {
        uint256 numProjects = marketplace.projectIds();
        for(uint i = 1; i <= numProjects; ++i) {
            Project memory project = marketplace.getProject(i);
            if(project.status == Status.Disputed) {
                Dispute memory dispute = mediationService.getDispute(marketplace.getDisputeId(project.projectId));
                if(dispute.phase == Phase.Disclosure) {
                    bool outcome = i % 2 == 0 ? true : false;
                    resolveMediation(project.projectId, outcome);
                }
            }
        }
    }

    function panelSelectionForAll() public {
        uint256 numDisputes = mediationService.disputeIds();
        for(uint i = 1; i <= numDisputes; ++i) {
            Dispute memory dispute = mediationService.getDispute(i);
            if(dispute.phase == Phase.Disclosure) {
                payFeesAndSelectMediators(dispute.projectId);
            }
        }
    }

    ////////////////
    ///   UTIL   ///
    ////////////////

    function getWallet(address _user) public returns (address) {
        address walletAddr;        
        for(uint i; i < anvilAddresses.length; ++i) {
            if(anvilAddresses[i] == _user) {
                walletAddr = vm.rememberKey(anvilPKs[i]);
            }
        }
        require(walletAddr != address(0), "address not found");
        return walletAddr;
    }

    function randomBuyerAndProvider() public returns (address, address) {
        uint256 indexBuyer = uint256(keccak256(abi.encodePacked(nonce, block.timestamp))) % anvilPKs.length;
        ++nonce;
        uint256 indexProvider = uint256(keccak256(abi.encodePacked(nonce, block.timestamp))) % anvilPKs.length;
        while(indexBuyer == indexProvider) {
            ++nonce;
            indexProvider = uint256(keccak256(abi.encodePacked(nonce, block.timestamp))) % anvilPKs.length;
        }
        return(vm.rememberKey(anvilPKs[indexBuyer]), vm.rememberKey(anvilPKs[indexProvider]));
    }

    function logProjectDetails(uint256 _projectId) public view {
        Project memory project = marketplace.getProject(_projectId);
        console.log("id: %s", project.projectId);
        console.log("status: %s", getStatusString(project.status));
        if(project.status == Status.Disputed || project.status == Status.Appealed) {
            uint256 disputeId = marketplace.getDisputeId(project.projectId);
            console.log("dispute id: %s", disputeId);
            Dispute memory dispute = mediationService.getDispute(disputeId);
            console.log("dispute phase: ", getPhaseString(dispute.phase));
            if(dispute.phase == Phase.Decision) {
                console.log("petition granted: ", dispute.granted);
            }
        }
        console.log("escrow: %s", project.escrow);
        console.log("buyer: %s", project.buyer);
        console.log("provider: %s", project.provider);
    }

    function getStatusString(Status _status) public pure returns (string memory) {
        string memory status;
        if(_status == Status.Created) status = "Created";
        else if(_status == Status.Cancelled) status = "Cancelled";
        else if(_status == Status.Active) status = "Active";
        else if(_status == Status.Discontinued) status = "Discontinued";
        else if(_status == Status.Completed) status = "Completed";
        else if(_status == Status.Approved) status = "Approved";
        else if(_status == Status.Challenged) status = "Challenged";
        else if(_status == Status.Disputed) status = "Disputed";
        else if(_status == Status.Appealed) status = "Appealed";
        else if(_status == Status.Resolved_ChangeOrder) status = "Resolved_ChangeOrder";
        else if(_status == Status.Resolved_Mediation) status = "Resolved_Mediation";
        else if(_status == Status.Resolved_ReviewOverdue) status = "Resolved_ReviewOverdue";
        else if(_status == Status.Resolved_MediationDismissed) status = "Resolved_MediationDismissed";
        return status;
    }

    function getPhaseString(Phase _phase) public pure returns (string memory) {
        string memory phase;
        if(_phase == Phase.Disclosure) phase = "Disclosure";
        if(_phase == Phase.PanelSelection) phase = "PanelSelection"; 
        if(_phase == Phase.Voting) phase = "Voting"; 
        if(_phase == Phase.Reveal) phase = "Reveal"; 
        if(_phase == Phase.Decision) phase = "Decision";
        if(_phase == Phase.DefaultDecision) phase = "DefaultDecision"; 
        if(_phase == Phase.Dismissed) phase = "Dismissed"; 
        if(_phase == Phase.SettledExternally) phase = "SettledExternally";
        return phase;
    }

    function run() public {
        // vm.startBroadcast(anvilPKs[0]);
        // console.log("testing deployment");
        // console.log(marketplaceAddr);
        // vm.stopBroadcast();
    }
}





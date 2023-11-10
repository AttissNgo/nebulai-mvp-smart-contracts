### To set the environment to develop the Mediator UI:
First, instantiate Anvil

    anvil --accounts 20 --balance 1000000

Then, set the EVM state by running these scripts:

    RPC="http://127.0.0.1:8545"
    forge script script/Deployment.s.sol:DeploymentLocal --fork-url $RPC --broadcast
    forge script script/Project.s.sol:CreateProject --rpc-url $RPC --sig "createMultipleProjects()" --broadcast
    cast rpc anvil_setBlockTimestampInterval 604800 --rpc-url $RPC
    cast rpc anvil_mine 1 --rpc-url $RPC
    cast rpc anvil_removeBlockTimestampInterval --rpc-url $RPC
    forge script script/Project.s.sol:CreateProject --rpc-url $RPC --sig "createMultipleDisputes()" --broadcast
    forge script script/Project.s.sol:CreateProject --rpc-url $RPC --sig "panelSelectionForAll()" --broadcast

## Create and manage Projects and Disputes locally

1. Instantiate anvil
    ```
    anvil --accounts 20 --balance 1000000
    ```

2. Declare RPC variable
    ```
    RPC="http://127.0.0.1:8545"
    ```

3. Deploy smart contracts
    ```
    forge script script/Deployment.s.sol:DeploymentLocal --fork-url $RPC --broadcast
    ```

4. You can create projects using the various functions in the script, or even easier, create a project at each stage (without mediation):
    ```
    forge script script/Project.s.sol:CreateProject --rpc-url $RPC --sig "createMultipleProjects()" --broadcast
    ```

    These projects will have a random buyer and provider address. The rest of the project parameters are defined in the script.
    This function creates 10 projects with status Challenged. These can be used to simulate projects with Mediation.

5. If you want to create projects with Mediataion, first move time ahead in anvil by 1 week:

    ```
    cast rpc anvil_setBlockTimestampInterval 604800 --rpc-url $RPC
    cast rpc anvil_mine 1 --rpc-url $RPC
    cast rpc anvil_removeBlockTimestampInterval --rpc-url $RPC
    ```

    Then, dispute the projects:
    ```
    forge script script/Project.s.sol:CreateProject --rpc-url $RPC --sig "createMultipleDisputes()" --broadcast
    ```

6. Now if you like you can resolve the disputes manually by calling
    ```
    forge script script/Project.s.sol:CreateProject --rpc-url $RPC --sig "resolveMediation(uint256,bool)" <project ID> <outcome> --broadcast
    ```
    ... where 'outcome' is a boolean indicating whether the petition is granted or not.

    OR... you can resolve all disputes at once by calling:
    ```
    forge script script/Project.s.sol:CreateProject --rpc-url $RPC --sig "resolveAllMediation()" --broadcast
    ```
    ... this will resolve all disputes in which Phase == Disclosure (it will ignore disputes that you have updated manually), and if the project ID is even it will grant the petition and not grant if it is odd.

In my case, I need disputes with mediators already drawn, so I can use this function:

    forge script script/Project.s.sol:CreateProject --rpc-url $RPC --sig "panelSelectionForAll()" --broadcast
    


To see project details in the command line, run this script:

    forge script script/Project.s.sol:CreateProject --rpc-url $RPC --sig "logProjectDetails(uint256)" <projectId>

To get a bunch of projects both in mediation and not in mediation, the whole flow would be:

    RPC="http://127.0.0.1:8545"
    forge script script/Deployment.s.sol:DeploymentLocal --fork-url $RPC --broadcast
    forge script script/Project.s.sol:CreateProject --rpc-url $RPC --sig "createMultipleProjects()" --broadcast
    cast rpc anvil_setBlockTimestampInterval 604800 --rpc-url $RPC
    cast rpc anvil_mine 1 --rpc-url $RPC
    cast rpc anvil_removeBlockTimestampInterval --rpc-url $RPC
    forge script script/Project.s.sol:CreateProject --rpc-url $RPC --sig "createMultipleDisputes()" --broadcast
    forge script script/Project.s.sol:CreateProject --rpc-url $RPC --sig "resolveAllMediation()" --broadcast
    

## If you scripts with more granular control of the mediation process, let me know and I will write them for you.




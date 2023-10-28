## Create and manage Projects and Disputes locally

1. Instantiate anvil

    ```anvil --accounts 20 --balance 1000000```

2. Declare RPC variable

    ```RPC="http://127.0.0.1:8545"```

3. Deploy smart contracts

    ```forge script script/Deployment.s.sol:DeploymentLocal --fork-url $RPC --broadcast```

4. Create test projects (you can create individual ones for any scenario using the functions in the script, but this will create a bunch of them at different stages for you with a single command):

    ```forge script script/Project.s.sol:CreateProject --rpc-url $RPC --sig "createMultipleProjects()" --broadcast -vvv```

5. To move time ahead in anvil by 1 week:

    ```
    cast rpc anvil_setBlockTimestampInterval 604800 --rpc-url $RPC
    cast rpc anvil_mine 1 --rpc-url $RPC
    cast rpc anvil_removeBlockTimestampInterval --rpc-url $RPC
    ```

6. Dispute all the challenged projects:

    ```forge script script/Project.s.sol:CreateProject --rpc-url $RPC --sig "disputeAllChallengedProjects()" --broadcast -vvv```

    This will log all the disputed project Ids and all the Dispute Ids to the console. You can then control the outcome of these disputes.

7. Control outcome of a dispute:

    




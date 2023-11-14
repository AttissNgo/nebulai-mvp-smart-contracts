-include .env

.PHONY: anvil deploy-local 

RPC := "http://127.0.0.1:8545"

anvil :; anvil -a 20 --balance 1000000

deploy-local :; forge script script/Deployment.s.sol:DeploymentLocal --fork-url $(RPC) --broadcast

mine :; cast rpc evm_mine --rpc-url $(RPC)

create-project :; forge script script/Project.s.sol:CreateProject --rpc-url $(RPC) --sig "createProject()" --broadcast

pay-fee-select-mediators :; forge script script/Project.s.sol:CreateProject --rpc-url $(RPC) --sig "payFeesAndSelectMediators(uint256)" $(PROJECT_ID) --broadcast

mediators-accept :; forge script script/Project.s.sol:CreateProject --rpc-url $(RPC) --sig "mediatorsAccept(uint256)" $(PROJECT_ID) --broadcast

mediators-commit-vote :; forge script script/Project.s.sol:CreateProject --rpc-url $(RPC) --sig "mediatorsCommitVotes(uint256, bool)" $(PROJECT_ID) $(GRANTED) --broadcast

mediators-reveal-vote :; forge script script/Project.s.sol:CreateProject --rpc-url $(RPC) --sig "mediatorsRevealVotes(uint256, bool)" $(PROJECT_ID) $(GRANTED) --broadcast

log-project-info :; forge script script/Project.s.sol:CreateProject --rpc-url $(RPC) --sig "logProjectDetails(uint256)" $(PROJECT_ID) --broadcast

resolve-mediation :; forge script script/Project.s.sol:CreateProject --rpc-url $(RPC) --sig "resolveMediation(uint256, bool)" $(PROJECT_ID) $(OUTCOME) --broadcast

resolve-all-mediation :; forge script script/Project.s.sol:CreateProject --rpc-url $(RPC) --sig "resolveAllMediation()" --broadcast
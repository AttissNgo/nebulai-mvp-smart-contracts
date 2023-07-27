// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solmate/src/utils/CREATE3.sol";
import "./Escrow.sol";

contract EscrowFactory {

    function createEscrowContract(
        address _marketplace,
        uint256 _projectId,
        address _buyer,
        address _provider,
        address _paymentToken,
        uint256 _projectFee,
        uint256 _providerStake,
        address _court,
        string memory _detailsURI
    ) 
        external 
        returns (address) 
    {
        bytes32 _salt = keccak256(abi.encodePacked(_projectId, _detailsURI));
        address newEscrowContract = payable(CREATE3.deploy(
            _salt,
            abi.encodePacked(
                type(Escrow).creationCode,
                abi.encode(
                    _marketplace,
                    _projectId,
                    _buyer,
                    _provider,
                    _paymentToken,
                    _projectFee,
                    _providerStake,
                    _court
                )
            ),
            0
        ));
        address escrow = payable(newEscrowContract);
        return escrow;
    }

}
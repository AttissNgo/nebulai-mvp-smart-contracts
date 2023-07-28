// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solmate/src/tokens/ERC20.sol";

contract NebulaiTestTokenFaucet is ERC20 {

    constructor() ERC20("NebulaiTestToken", "NEBTT", 18) {}

    function mint(address _to, uint256 _amount) public {
        // permission with company address later
        _mint(_to, _amount);
    }
}
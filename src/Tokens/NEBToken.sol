// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solmate/src/tokens/ERC20.sol";

contract NEBToken is ERC20 {

    constructor(address _treasury) ERC20("Nebulai Token", "NEB", 18) {
        _mint(_treasury, 10000000 ether); 
    }


}

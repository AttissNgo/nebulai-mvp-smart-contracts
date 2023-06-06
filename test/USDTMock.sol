// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solmate/src/tokens/ERC20.sol";

contract USDTMock is ERC20 {
    constructor() ERC20 ("Tether USDT Mock", "USDT", 6) {}

    function mint(address to, uint256 amount) public {
        // anyone can mint
        _mint(to, amount);
    }
}
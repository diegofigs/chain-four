// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract TestToken is ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol, 18) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

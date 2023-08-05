// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { ERC20 } from "src/lib/ERC20.sol";

contract ERC20Mock is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000e18);
    }
}

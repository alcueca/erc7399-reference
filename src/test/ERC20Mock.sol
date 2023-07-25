// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20 } from "../lib/ERC20.sol";

contract ERC20Mock is ERC20 {

    constructor (string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000e18);
    }
}
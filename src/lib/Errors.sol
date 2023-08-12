// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

error OnlyOwner(address caller, address owner);
error UnsupportedToken(address token);
error InsufficientBalance(uint256 expected, uint256 balance);
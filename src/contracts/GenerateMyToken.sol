// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GenerateMyToken is ERC20, Ownable {
    // 100,000 tokens com 18 decimais => 100_000 * 10^18 unidades
    uint256 public constant INITIAL_SUPPLY = 100_000 * 10**18;

    constructor() ERC20("MyToken", "MYT") Ownable(msg.sender) {
        require(msg.sender != address(0), "Invalid receiver");
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
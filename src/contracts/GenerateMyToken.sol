// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ERC20 (v5.x)
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v5.0.2/contracts/token/ERC20/ERC20.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v5.0.2/contracts/access/Ownable.sol";

contract GenerateMyToken is ERC20, Ownable {
    uint256 public constant INITIAL_SUPPLY = 100_000 * 10**18;

    constructor() ERC20("MyToken", "MYT") Ownable(msg.sender) {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
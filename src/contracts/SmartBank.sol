// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract SmartBank {
    event InternalTransfer(address from, address to, uint256 amount);
    event ExternalTransfer(address from, address to, uint256 amount);
    event Deposit(address from, uint256 amount);
    event Withdraw(address from, uint256 amount);

    struct Account {
        uint256 balance;
    }

    mapping(address => Account) public accounts;

    function getBalance() public view returns (uint256) {
        return accounts[msg.sender].balance;
    }

    function deposit() public payable {
        require(msg.value != 0, "value can not be zero");
        accounts[msg.sender].balance += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdrawAll() public {
        withdraw(accounts[msg.sender].balance);
    }

    function withdraw(uint256 value) public {
        require(value <= accounts[msg.sender].balance, "insufficient balance");
        accounts[msg.sender].balance -= value;

        payable(msg.sender).transfer(value);
        emit Withdraw(msg.sender, value);
    }

    function externalTransferTo(address payable to, uint256 value)
        public
    {
        require(value <= accounts[msg.sender].balance, "insufficient balance");
        accounts[msg.sender].balance -= value;

        to.transfer(value);
        emit ExternalTransfer(msg.sender, to, value);
    }

    function internalTransferToAccount(address account, uint256 value) public {
        require(value <= accounts[msg.sender].balance, "insufficient balance");

        accounts[msg.sender].balance -= value;
        accounts[account].balance += value;

        emit InternalTransfer(msg.sender, account, value);
    }
}

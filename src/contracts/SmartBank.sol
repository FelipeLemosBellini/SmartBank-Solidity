// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract SmartBank {
    address onwer;

    uint256 balanceOfBank;
    uint32 feeTax;
    mapping(address => Account) public accounts;

    constructor() {
        onwer = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == onwer, "not the owner");
        _;
    }

    event InternalTransfer(address from, address to, uint256 amount);
    event ExternalTransfer(address from, address to, uint256 amount);
    event Deposit(address from, uint256 amount);
    event Withdraw(address from, uint256 amount);

    struct Account {
        uint256 balance;
    }

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

        uint256 valueToWithdraw = (value * (10000 - feeTax)) / 10000;
        uint256 valueToTax = value - valueToWithdraw;
        balanceOfBank += valueToTax;

        payable(onwer).transfer(valueToWithdraw);
        emit Withdraw(msg.sender, value);
    }

    function externalTransferTo(address payable to, uint256 value) public {
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

    function setFee(uint32 percentage) public onlyOwner {
        require(percentage >= 0 && percentage <= 10000, "out of range");
        feeTax = percentage;
    }

    function getBalanceOfBank() public view returns (uint256) {
        return balanceOfBank;
    }

    function withdrawFees(uint256 value) public onlyOwner {
        balanceOfBank -= value;
        payable(onwer).transfer(value);
    }
}

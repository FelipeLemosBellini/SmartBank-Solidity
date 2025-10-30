// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Ethernium {
    uint256 private constant CREATION_FEE = 100000000000000;
    //0x5eEe7963108A2F14F498862F02E5c9D33004f728
    // Taxa de depósito: 0.5% (expressa em basis points = 50 bps)
    uint16 private constant DEPOSIT_FEE_BPS = 50; // 50/10000 = 0.50%
    uint16 private constant BPS_DENOMINATOR = 10000;

    struct Vault {
        bool exist;
        uint256 balance;
    }
    struct VaultView {
        uint256 balances;
    }

    // testator (chave = endereço público) => seu cofre
    mapping(address => Vault) private testators;

    // Flags para saber se o dono já pagou a taxa de criação
    mapping(address => bool) private vaultCreatedAndPaid;

    // Saldo próprio do contrato em ETH (para taxas)
    Vault private vaultOfContract;

    event VaultCreated(address indexed testator);
    event Deposit(
        address indexed testator,
        uint256 grossAmount,
        uint256 feeAmount,
        uint256 netAmount
    );
    event Withdraw(
        address indexed testator,
        uint256 amount
    );

    // Desabilita recebimento direto para garantir a cobrança da taxa de 0.5%
    receive() external payable {
        revert("Don't do it!");
    }

    // Cria o cofre e cobra exatamente 0.1 ETH uma única vez
    function createVault() external payable {
        require(!vaultCreatedAndPaid[msg.sender], "Vault already created");
        require(msg.value == CREATION_FEE, "Exact 0.1 ETH required");
        vaultCreatedAndPaid[msg.sender] = true;

        Vault storage v = testators[msg.sender];
        if (!v.exist) {
            _creditContractVault(CREATION_FEE);
            v.exist = true;
            emit VaultCreated(msg.sender);
        }
        // A taxa de 0.1 ETH permanece no contrato (saldo proprio)
    }

    // Depositar ETH:
    // - Exige já ter criado o cofre (e pago a taxa).
    // - Calcula 0.5% de taxa em ETH e retém no contrato.
    // - Credita 99.5% no Vault.
    function depositETH() external payable {
        require(vaultCreatedAndPaid[msg.sender], "Create vault first");
        require(msg.value > 0, "No ETH sent");
        _ensureVault(msg.sender);

        uint256 fee = (msg.value * DEPOSIT_FEE_BPS) / BPS_DENOMINATOR;
        uint256 net = msg.value - fee;
        require(net > 0, "Net is zero"); // evita depósitos minúsculos

        // Credita a taxa no cofre do contrato
        _creditContractVault(fee);

        _credit(msg.sender, net);
        emit Deposit(msg.sender, msg.value, fee, net);
    }

    // Retorna a visão completa do cofre de um usuário específico
    function myVault() public view returns (VaultView memory v) {
        Vault storage src = testators[msg.sender];
        v = VaultView({balances: src.balance});
        return v;
    }

    // (Opcional) Permite o próprio testador sacar seus fundos em ETH (líquido)
    function withdrawETH(uint256 amount) external {
        Vault storage v = testators[msg.sender];
        require(v.exist, "Vault does not exist");
        require(v.balance >= amount, "Insufficient ETH");

        v.balance -= amount;

        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "ETH transfer failed");

        emit Withdraw(msg.sender, amount);
    }

    // Utilitário interno: garante a existência do cofre
    function _ensureVault(address testator) internal {
        Vault storage v = testators[testator];
        if (!v.exist) {
            v.exist = true;
            emit VaultCreated(testator);
        }
    }

    // Credita depósito líquido ao vault do testador
    function _credit(
        address testator,
        uint256 amount
    ) internal {
        Vault storage v = testators[testator];

        v.balance += amount;
    }

    function _creditContractVault(uint256 amount) internal {
        if (amount == 0) return;
        vaultOfContract.balance += amount;
        vaultOfContract.exist = true;
    }
}

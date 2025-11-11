    // SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract EthereumTcc {
    uint256 private constant CREATION_FEE = 10000000000000;
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

    // Endereço do deployer do contrato
    address private immutable deployer;

    event VaultCreated(address indexed testator);
    event Deposit(
        address indexed testator,
        uint256 grossAmount,
        uint256 feeAmount,
        uint256 netAmount
    );
    event Withdraw(address indexed testator, uint256 amount);
    event VaultDistributed(
        address indexed testator,
        address[] recipients,
        uint256[] amounts
    );

    // Construtor para definir o deployer
    constructor() {
        deployer = msg.sender;
        vaultOfContract.exist = true;
    }

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
        require(net > 0, "Net is zero"); 
        
        _creditContractVault(fee);

        _credit(msg.sender, net);
        emit Deposit(msg.sender, msg.value, fee, net);
    }

    function vaultBalance(address testator) external view returns (uint256) {
        require(msg.sender == deployer, "Only deployer can call this function");
        require(vaultCreatedAndPaid[testator], "Vault does not exist");
        return testators[testator].balance;
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

    function myVault() public view returns (VaultView memory v) {
        Vault storage src = testators[msg.sender];
        v = VaultView({balances: src.balance});
        return v;
    }

    // Função para distribuir fundos de um cofre para vários endereços
    // Apenas o deployer pode chamar esta função
    function distributeVault(
        address testator,
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external {
        // Verifica se o chamador é o deployer
        require(msg.sender == deployer, "Only deployer can call this function");

        // Verifica se o cofre existe
        Vault storage v = testators[testator];
        require(v.exist, "Vault does not exist");

        // Verifica se o número de destinatários e valores é o mesmo
        require(
            recipients.length == amounts.length,
            "Recipients and amounts length mismatch"
        );

        // Calcula o total a ser distribuído
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount = totalAmount + amounts[i];
        }

        // Verifica se o cofre tem saldo suficiente
        require(v.balance == totalAmount, "Insufficient ETH in vault");

        // Deduz o saldo do cofre
        v.balance -= totalAmount;

        // Transfere os fundos para os destinatários

        for (uint i = 0; i < recipients.length; i++) {
            (bool ok, ) = recipients[i].call{value: amounts[i]}("");
            require(ok, "ETH transfer failed");
        }

        emit VaultDistributed(testator, recipients, amounts);
    }

    function withdrawFees(address beneficiary) external {
        require(msg.sender == deployer, "Only deployer can call this function");
        uint256 fees = vaultOfContract.balance;
        vaultOfContract.balance = 0;
        (bool ok, ) = beneficiary.call{value: fees}("");
        require(ok, "ETH transfer failed");
    }

    function showFees() public view returns (uint256) {
        return vaultOfContract.balance;
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
    function _credit(address testator, uint256 amount) internal {
        Vault storage v = testators[testator];

        v.balance += amount;
    }

    function _creditContractVault(uint256 amount) internal {
        if (amount == 0) return;
        vaultOfContract.balance += amount;
        vaultOfContract.exist = true;
    }
}

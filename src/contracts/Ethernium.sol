// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Ethernium {
    using SafeERC20 for IERC20;

    uint256 private constant CREATION_FEE = 100000000000000;
    //0x5eEe7963108A2F14F498862F02E5c9D33004f728
    // Taxa de depósito: 0.5% (expressa em basis points = 50 bps)
    uint16 private constant DEPOSIT_FEE_BPS = 50; // 50/10000 = 0.50%
    uint16 private constant BPS_DENOMINATOR = 10000;

    // Endereço "sentinela" para representar ETH nos mapas
    address private constant ETH_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct Vault {
        bool exist;
        // token => amount depositado por este testador (líquido, após taxa)
        mapping(address => uint256) balances;
        // tokens já depositados (para listagem off-chain)
        address[] tokens;
        mapping(address => bool) tokenSeen;
    }
    struct VaultView {
        bool exist;
        address[] tokens; // lista de tokens já depositados
        uint256[] balances; // saldos líquidos correspondentes a cada token acima
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
        address indexed token,
        uint256 grossAmount,
        uint256 feeAmount,
        uint256 netAmount
    );
    event Withdraw(
        address indexed testator,
        address indexed token,
        uint256 amount
    );

    // Cria o cofre e cobra exatamente 0.1 ETH uma única vez
    function createVault() external payable {
        require(!vaultCreatedAndPaid[msg.sender], "Vault already created");
        require(msg.value == CREATION_FEE, "Exact 0.1 ETH required");
        vaultCreatedAndPaid[msg.sender] = true;

        Vault storage v = testators[msg.sender];
        if (!v.exist) {
            // Credita a taxa (em token) ao cofre do contrato
            _creditContractVault(ETH_ADDRESS, CREATION_FEE);
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
        _creditContractVault(ETH_ADDRESS, fee);

        _credit(msg.sender, ETH_ADDRESS, net);
        emit Deposit(msg.sender, ETH_ADDRESS, msg.value, fee, net);
    }

    // Desabilita recebimento direto para garantir a cobrança da taxa de 0.5%
    receive() external payable {
        revert("Don't do it!");
    }

    // Depositar um token ERC-20:
    // - Exige já ter criado o cofre (e pago a taxa).
    // - Requer approve prévio para 'amount' (quantidade bruta a transferir).
    // - Retem 0.5% no contrato e credita 99.5% no Vault.
   function depositERC20(address token, uint256 amount) external payable {
    require(vaultCreatedAndPaid[msg.sender], "Create vault first");
    require(token != address(0), "Invalid token");
    require(amount > 0, "Amount must be > 0");

    IERC20 _erc20 = IERC20(token);
    _erc20.safeTransferFrom(msg.sender, address(this), amount); // Reverts on failure

    uint256 fee = (amount * DEPOSIT_FEE_BPS) / BPS_DENOMINATOR;
    uint256 net = amount - fee;
    require(net > 0, "Net is zero");

    _creditContractVault(token, fee); // Credit fee to contract
    _credit(msg.sender, token, net);  // Credit net to user
    emit Deposit(msg.sender, token, amount, fee, net);
}

    // Retorna a visão completa do cofre de um usuário específico
    function myVault() public view returns (VaultView memory v) {
        Vault storage src = testators[msg.sender];

        uint256 len = src.tokens.length;
        address[] memory tokens_ = new address[](len);
        uint256[] memory balances_ = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            address t = src.tokens[i];
            tokens_[i] = t;
            balances_[i] = src.balances[t];
        }

        v = VaultView({exist: src.exist, tokens: tokens_, balances: balances_});
        return v;
    }

    // Retorna a lista de tokens já depositados por um testador (para uso off-chain)
    function getTokens() external view returns (address[] memory) {
        return testators[msg.sender].tokens;
    }

    // (Opcional) Permite o próprio testador sacar seus fundos em ETH (líquido)
    function withdrawETH(uint256 amount) external {
        Vault storage v = testators[msg.sender];
        require(v.exist, "Vault does not exist");
        require(v.balances[ETH_ADDRESS] >= amount, "Insufficient ETH");

        v.balances[ETH_ADDRESS] -= amount;

        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "ETH transfer failed");

        emit Withdraw(msg.sender, ETH_ADDRESS, amount);
    }

    // (Opcional) Saque de ERC-20 pelo próprio testador (líquido)
    function withdrawERC20(address token, uint256 amount) external {
        require(token != address(0), "Invalid token");
        Vault storage v = testators[msg.sender];
        require(v.exist, "Vault does not exist");
        require(v.balances[token] >= amount, "Insufficient balance");

        v.balances[token] -= amount;

        bool ok = IERC20(token).transfer(msg.sender, amount);
        require(ok, "ERC20 transfer failed");

        emit Withdraw(msg.sender, token, amount);
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
        address token,
        uint256 amount
    ) internal {
        Vault storage v = testators[testator];

        if (!v.tokenSeen[token]) {
            v.tokenSeen[token] = true;
            v.tokens.push(token);
        }

        v.balances[token] += amount;
    }

    function _creditContractVault(address token, uint256 amount) internal {
        if (amount == 0) return;
        if (!vaultOfContract.tokenSeen[token]) {
            vaultOfContract.tokenSeen[token] = true;
            vaultOfContract.tokens.push(token);
        }
        vaultOfContract.balances[token] += amount;
        vaultOfContract.exist = true;
    }

    // Retorna a visão do cofre do contrato (taxas acumuladas em ETH e ERC20)
    function contractVaultView() external view returns (VaultView memory v) {
        uint256 len = vaultOfContract.tokens.length;

        address[] memory tokens_ = new address[](len);
        uint256[] memory balances_ = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            address t = vaultOfContract.tokens[i];
            tokens_[i] = t;
            balances_[i] = vaultOfContract.balances[t];
        }

        v = VaultView({
            exist: vaultOfContract.exist,
            tokens: tokens_,
            balances: balances_
        });
    }
}

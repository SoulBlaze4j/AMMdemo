// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./StandardToken.sol";

contract LPToken is StandardToken {
    string private constant NAME = "LP Token";
    string private constant SYMBOL = "LPT";

    constructor() {
        _name = NAME;
        _symbol = SYMBOL;
    }

    function mint(address to, uint256 amount) external {
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(_balances[from] >= amount, "Insufficient balance");
        _balances[from] -= amount;
        _totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
}
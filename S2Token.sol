// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./StandardToken.sol";


contract S2Token is StandardToken {
    string private constant NAME = "S Two";
    string private constant SYMBOL = "S2";

    uint256 private INITIAL_SUPPLY = 10000 * 10**decimals();

    /**
     * Token Constructor
     * @dev Create and issue tokens to msg.sender.
     */
    constructor() {
        _name = NAME;
        _symbol = SYMBOL;
        _totalSupply = INITIAL_SUPPLY;
        _balances[msg.sender] = INITIAL_SUPPLY;
    }
}
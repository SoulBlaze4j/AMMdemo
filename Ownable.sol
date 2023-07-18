// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Ownable
 * @dev Ownable has an owner address to simplify "user permissions".
 */
contract Ownable {
    address public owner;

    /**
     * Ownable
     * @dev Ownable constructor sets the `owner` of the contract to sender
     */
    constructor() {
        owner = msg.sender;
    }

    /**
     * ownerOnly
     * @dev Throws an error if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    /**
     * transferOwnership
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0));
        owner = newOwner;
    }
}

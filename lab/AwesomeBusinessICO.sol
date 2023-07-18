// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./StandardToken.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

/**
 * @title Awesome Business ICO
 * @dev An ICO that creates tokens as it receives ether.
 */
contract AwesomeBusinessICO is StandardToken, Ownable {
    using SafeMath for uint256;
    string private constant NAME = "Awesome Token";
    string private constant SYMBOL = "AWT";
    uint256 private INITIAL_SUPPLY = 0;

    // crowdsale parameters
    uint256 public startTime;
    uint256 public endTime;
    uint256 public constant convRate = 8000; // 8000 AWT tokens per 1 ETH
    uint256 public constant tokenCreationMin = convRate * 10 ether; // the equivalent of 10 ETH
    uint256 public constant tokenCreationCap = convRate * 50 ether; // the equivalent of 50 ETH
    bool public initialized = false;
    bool public finalized = false;

    // events
    event LogRefund(address indexed _to, uint256 _value);
    event CreatedTokens(address indexed _to, uint256 _value);

    /**
     * ICO Constructor
     * @dev Create and issue tokens to msg.sender.
     */
    constructor() StandardToken() Ownable() {
        _name = NAME;
        _symbol = SYMBOL;
        _totalSupply = INITIAL_SUPPLY;
        startTime = block.timestamp; // ICO starts now
        endTime = startTime + 10*60; // for 10 minutes
    }

    /**
     * initialize
     * @dev Initialize the contract
     **/
    function initialize() public onlyOwner {
        require(initialized == false); // Can only be initialized once
        initialized = true;
    }

    /**
     * isActive
     * @dev Determines if the contract is still active
     **/
    function isActive() public view returns (bool) {
        return (initialized == true &&
            block.timestamp >= startTime && // Must be after the start date
            block.timestamp <= endTime && // Must be before the end date
            goalReached() == false); // Goal must not already be reached
    }

    /**
     * whenSaleIsActive
     * @dev ensures that the contract is still active
     **/
    modifier whenSaleIsActive() {
        // Check if sale is active
        assert(isActive());
        _;
    }

    /**
     * goalReached
     * @dev Function to determines if goal has been reached
     **/
    function goalReached() public view returns (bool) {
        return (_totalSupply >= tokenCreationCap);
    }

    /**
     * @dev Fallback function if ether is sent to address insted of buyTokens function
     **/
    receive() external payable {
        buyTokens();
    }

    /**
     * buyTokens
     * @dev Accepts ether and creates new AWT tokens.
     **/
    function buyTokens() public payable whenSaleIsActive {
        require(msg.sender != owner, "ICO: The owner of the ICO cannot contribute");
        uint256 weiAmount = msg.value;
        require(weiAmount > 0,       "ICO: Please contribute something!");

        @TODO: Convert weiAmount to a number of tokens, following the conversion rate
        @TODO: Adjust the total supply to reflect an increase by that number of tokens
        @TODO: Allocate the new tokens to msg.sender

        emit CreatedTokens(msg.sender, tokens);     // logs token creation
    }

    /// @dev Ends the funding period and sends the ETH home
    function finalize() external onlyOwner {
        require(initialized && !finalized,       "ICO: No longer operational");
        require(_totalSupply >= tokenCreationMin, "ICO: Not enough tokens got minted");
        require(
            (block.timestamp <= endTime && goalReached()) || // wait until the cap is reached
                block.timestamp > endTime,  // or we passed the end date
            "ICO: Either the cap is not reached or the sale period is not over yet"
        );

        finalized = true;
        require(payable(owner).send(address(this).balance)); // send all the raised eth in this contract to the owner
    }

    /// @dev Allows contributors to recover their ether in the case of a failed funding campaign.
    function refund() external {
        require(initialized && !finalized,      "ICO: No longer operational");
        require(_totalSupply < tokenCreationMin, "ICO: Enough tokens got minted");
        require(block.timestamp > endTime,       "ICO: Sale period is not over yet");

        uint256 tokens = _balances[msg.sender];
        if (tokens == 0) revert("ICO: Nothing to refund");

        _balances[msg.sender] = 0;                 // reduce balance now to prevent re-entry attacks
        _totalSupply = _totalSupply.sub(tokens);   // decrease total supply by the amount of refund
        uint256 ethVal = tokens / convRate;        // should be safe due to the use of convRate everywhere

        emit LogRefund(msg.sender, ethVal);        // logs the refund

        require(payable(msg.sender).send(ethVal)); // if you're using a contract; make sure it works with .send gas limits
    }
}

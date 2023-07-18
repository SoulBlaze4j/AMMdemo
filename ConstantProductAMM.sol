// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./StandardToken.sol";
import "./S1Token.sol";
import "./S2Token.sol";
import "./LPToken.sol";
import "./SafeMath.sol";

interface ILiquidityPool {
    function swap(address tokenToSwap, uint256 amountIn, uint256 minAmountOut) external returns (uint256);
    function addLiquidity(uint256 s1Amount, uint256 s2Amount) external;
}

// 创建一个基于恒定乘积公式的AMM合约
contract ConstantProductAMM is ILiquidityPool {
    S1Token public s1Token;
    S2Token public s2Token;
    LPToken public lpToken;

    uint256 public k; // Constant product invariant

    constructor(address _s1Token, address _s2Token, address _lpToken) {
        s1Token = S1Token(_s1Token);
        s2Token = S2Token(_s2Token);
        lpToken = LPToken(_lpToken);
    }

    function swap(address tokenToSwap, uint256 amountIn, uint256 minAmountOut) external override returns (uint256) {
        require(tokenToSwap == address(s1Token) || tokenToSwap == address(s2Token), "Invalid token address");
        
        if (tokenToSwap == address(s1Token)) {
            uint256 s1Balance = s1Token.balanceOf(address(this));
            uint256 s2Balance = s2Token.balanceOf(address(this));

            // uint256 scalingFactor = 1e18;
            // amountIn = amountIn * scalingFactor;
            uint256 amountOut = (amountIn * s2Balance) / (s1Balance + amountIn);
            require(amountOut >= minAmountOut, "Insufficient output amount");

            uint256 newS1Balance = s1Balance + amountIn;
            uint256 newS2Balance = s2Balance - amountOut;
            require(newS1Balance * newS2Balance >= k, "Invariant check failed");

            s1Token.transferFrom(msg.sender, address(this), amountIn);
            s2Token.transfer(msg.sender, amountOut);

            return amountOut;
        } else {
            uint256 s1Balance = s1Token.balanceOf(address(this));
            uint256 s2Balance = s2Token.balanceOf(address(this));

            // uint256 scalingFactor = 1e18;
            // amountIn = amountIn * scalingFactor;
            uint256 amountOut = (amountIn * s1Balance) / (s2Balance + amountIn);
            require(amountOut >= minAmountOut, "Insufficient output amount");

            uint256 newS1Balance = s1Balance - amountOut;
            uint256 newS2Balance = s2Balance + amountIn;
            require(newS1Balance * newS2Balance >= k, "Invariant check failed");

            s2Token.transferFrom(msg.sender, address(this), amountIn);
            s1Token.transfer(msg.sender, amountOut);

            return amountOut;
        }
    }
    
    function getRate(address tokenToSwap, uint256 amountIn) public view returns (uint256) {
        uint256 s1Balance = s1Token.balanceOf(address(this));
        uint256 s2Balance = s2Token.balanceOf(address(this));
        uint256 scalingFactor = 1e18;

        if (tokenToSwap == address(s1Token)) {
            uint256 amountOut = (amountIn * s2Balance) / (s1Balance + amountIn);
            return amountOut * scalingFactor / amountIn;
        } else if (tokenToSwap == address(s2Token)) {
            uint256 amountOut = (amountIn * s1Balance) / (s2Balance + amountIn);
            return amountOut * scalingFactor / amountIn;
        } else {
            revert("Invalid token address");
        }
    }

    function addLiquidity(uint256 s1Amount, uint256 s2Amount) external override {
        require(s1Amount > 0, "s1Amount must be greater than 0");
        require(s2Amount > 0, "s2Amount must be greater than 0");

        uint256 s1Balance = s1Token.balanceOf(address(this));
        uint256 s2Balance = s2Token.balanceOf(address(this));

        if (s1Balance > 0 && s2Balance > 0) {
            require(s1Amount * s2Balance == s2Amount * s1Balance, "Invalid amounts");
        }

        s1Token.transferFrom(msg.sender, address(this), s1Amount);
        s2Token.transferFrom(msg.sender, address(this), s2Amount);

        uint256 lpAmount = calculateLPTokens(s1Amount, s2Amount); // Add a function to calculate the amount of LP tokens to be issued
        lpToken.mint(msg.sender, lpAmount);

        k = (s1Balance + s1Amount) * (s2Balance + s2Amount); // Update invariant
    }


    function removeLiquidity(uint256 lpAmount) external {
        require(lpAmount > 0, "LP amount must be greater than 0");
        uint256 totalLPSupply = lpToken.totalSupply();
        require(totalLPSupply > 0, "No liquidity in the pool");

        uint256 s1Balance = s1Token.balanceOf(address(this));
        uint256 s2Balance = s2Token.balanceOf(address(this));

        uint256 s1Share = lpAmount * s1Balance / totalLPSupply;
        uint256 s2Share = lpAmount * s2Balance / totalLPSupply;

        lpToken.burn(msg.sender, lpAmount);
        s1Token.transfer(msg.sender, s1Share);
        s2Token.transfer(msg.sender, s2Share);

        k = (s1Balance - s1Share) * (s2Balance - s2Share); // Update invariant
    }

    function calculateLPTokens(uint256 s1Amount, uint256 s2Amount) internal view returns (uint256) {
        uint256 s1Balance = s1Token.balanceOf(address(this));
        uint256 s2Balance = s2Token.balanceOf(address(this));
        uint256 totalLPSupply = lpToken.totalSupply();

        if (totalLPSupply == 0) {
            // In the initial case, when there are no LP tokens, issue LP tokens based on the smallest token amount
            return min(s1Amount, s2Amount);
        } else {
            // When there are existing LP tokens, issue LP tokens proportionally to the liquidity provided
            uint256 s1Share = s1Amount * totalLPSupply / s1Balance;
            uint256 s2Share = s2Amount * totalLPSupply / s2Balance;
            return min(s1Share, s2Share);
        }
    }

    // 比较两个数值并返回较小的一个
    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
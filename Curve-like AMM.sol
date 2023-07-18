// SPDX-License-Identifier: MIT
// 这个实现的Curve-Like AMM合约包含以下功能：
// 构造函数：用于初始化代币和流动性池
// swap：允许用户在池中进行代币交换
// addLiquidity：允许用户向池中添加流动性
// _calculateLPTokens：计算添加流动性时应发放的LP令牌数量
// _getD：根据x和y计算D值，D值代表了流动性池的状态
// _getY：根据D值和x计算y值，用于交换时计算输出代币数量
pragma solidity ^0.8.0;

import "./StandardToken.sol";
import "./S1Token.sol";
import "./S2Token.sol";
import "./LPToken2.sol";
import "./SafeMath.sol";

interface IERC20 {
    function totalSupply() external view returns (uint);

    function balanceOf(address account) external view returns (uint);

    function transfer(address recipient, uint amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint amount);
    event Approval(address indexed owner, address indexed spender, uint amount);
}
interface ILiquidityPool {
    function swap(address tokenToSwap, uint256 amountIn, uint256 minAmountOut) external returns (uint256);
    function addLiquidity(uint256 s1Amount, uint256 s2Amount) external;
}

library Math {
    function abs(uint x, uint y) internal pure returns (uint) {
        return x >= y ? x - y : y - x;
    }
}
contract CurveLikeAMM is ILiquidityPool {
    S1Token public s1Token;
    S2Token public s2Token;
    LPToken2 public lpToken;
    using SafeMath for uint256;

    // Only 2 tokens
    uint private constant N = 2;  
    // χ *(x + y) + xy = χ * D + (D / 2)^2
    // 2 Boarder: 
    // 1. χ -> infinity => χ *(x + y) = χ * D (From x + y = K)
    // 2. χ -> 0        => xy =  (D / 2)^2    (From x * y = K)

    // Can derive: A*N^N*(x+y) + D = A*N^N * D + (D / N)^N * (D / x*y)
    // So we can use 
    // Amplification coefficient multiplied by N^(N - 1)
    uint private constant A = 1000 * (N ** (N - 1));
    uint private constant DECIMALS = 18;


    constructor(address _s1Token, address _s2Token, address _lpToken) {
        s1Token = S1Token(_s1Token);
        s2Token = S2Token(_s2Token);
        lpToken = LPToken2(_lpToken);
    }

    function swap(address tokenToSwap, uint256 amountIn, uint256 minAmountOut) external override returns (uint256) {
        require(tokenToSwap == address(s1Token) || tokenToSwap == address(s2Token), "Invalid token address");
        uint256 s1Balance = s1Token.balanceOf(address(this));
        uint256 s2Balance = s2Token.balanceOf(address(this));
        uint256 newS1Balance;
        uint256 newS2Balance;
        uint256 amountOut;

        if (tokenToSwap == address(s1Token)) {
            newS1Balance = s1Balance + amountIn;
            
            uint y = _getY(newS1Balance, s1Balance, s2Balance);
            amountOut = s2Balance - y;

            s1Token.transferFrom(msg.sender, address(this), amountIn);
            s2Token.transfer(msg.sender, amountOut);
        } else {
            newS2Balance = s2Balance + amountIn;
            
            uint y = _getY(newS2Balance, s2Balance, s1Balance);
            amountOut = s1Balance - y;

            s2Token.transferFrom(msg.sender, address(this), amountIn);
            s1Token.transfer(msg.sender, amountOut);
        }

        require(amountOut >= minAmountOut, "Insufficient output amount");
        return amountOut;
    }

    function addLiquidity(uint256 s1Amount, uint256 s2Amount) external override {
        require(s1Amount > 0, "s1Amount must be greater than 0");
        require(s2Amount > 0, "s2Amount must be greater than 0");
        uint _totalSupply = lpToken.totalSupply();
        uint d0;
        uint256 s1Balance = s1Token.balanceOf(address(this));
        uint256 s2Balance = s2Token.balanceOf(address(this));
        if(_totalSupply > 0) {
            d0 = _getD(s1Balance, s2Balance);
        }
        // Transfer tokens in
        uint256 s1BalanceNew;
        uint256 s2BalanceNew;
        if (s1Amount > 0) {
            s1Token.transferFrom(msg.sender, address(this), s1Amount);
            s1BalanceNew = s1Balance + s1Amount;
        } else {
            s1BalanceNew = s1Balance;
        }
        if (s2Amount > 0) {
            s2Token.transferFrom(msg.sender, address(this), s2Amount);
            s2BalanceNew = s2Balance + s2Amount;
        } else {
            s2BalanceNew = s2Balance;
        }
        // Calculate new liquidity d1
        uint d1 = _getD(s1BalanceNew, s2BalanceNew);
        require(d1 > d0, "liquidity didn't increase");

        uint256 lpTokens;
        // Shares to mint = (d2 - d0) / d0 * total supply
        // d1 >= d2 >= d0
        if (_totalSupply > 0) {
            lpTokens = ((d1 - d0) * _totalSupply) / d0;
        } else {
            lpTokens = d1;
        }
        lpToken.mint(msg.sender, lpTokens);
    }

    function removeLiquidity(uint256 lpAmount) external {
        require(lpAmount > 0, "LP amount must be greater than 0");
        uint256 totalLPSupply = lpToken.totalSupply();
        require(totalLPSupply > 0, "No liquidity in the pool");

        uint256 s1Balance = s1Token.balanceOf(address(this));
        uint256 s2Balance = s2Token.balanceOf(address(this));

        uint256 s1Share = lpAmount * s1Balance / totalLPSupply;
        uint256 s2Share = lpAmount * s2Balance / totalLPSupply;

        s1Token.transfer(msg.sender, s1Share);
        s2Token.transfer(msg.sender, s2Share);
        lpToken.burn(msg.sender, lpAmount);
    }


    /**
     * @notice Calculate D, sum of balances in a perfectly balanced pool
     * If balances of x,y then x + y = D
     * @param x balance of 2 token
     * @param y balance of 2 token
     * @return D
     */
    function _getD(uint256 x, uint256 y) public pure returns (uint256) {
        /*
        Newton's method to compute D
        -----------------------------
        f(D) = ADn^n + D^(n + 1) / (n^n prod(x_i)) - An^n sum(x_i) - D 
        f'(D) = An^n + (n + 1) D^n / (n^n prod(x_i)) - 1

                     (as + np)D_n
        D_(n+1) = -----------------------
                  (a - 1)D_n + (n + 1)p

        a = An^n
        s = sum(x_i)
        p = (D_n)^(n + 1) / (n^n prod(x_i))
        */
        uint a = A * N; // An^n

        uint s = x + y; // x+y       

        // Newton's method
        // Initial guess, d <= s
        uint d = s;
        uint d_prev;
        for (uint i; i < 255; ++i) {
            // p = D^(n + 1) / (n^n * x_0 * ... * x_(n-1))
            uint p = d;
            
            p = (p * d) / (N * x);
            p = (p * d) / (N * y);

            d_prev = d;
            d = ((a * s + N * p) * d) / ((a - 1) * d + (N + 1) * p);

            if (Math.abs(d, d_prev) <= 1) {
                return d;
            }
        }
        revert("D didn't converge");
    }
    /**
     * @notice Calculate the new balance of token j given the new balance of token i
     * @param x New balance of token i
     * @param tokenInBalance Current in balances
     * @param tokenOutBalance Current out balances
     */
    function _getY(
        uint x,
        uint tokenInBalance,
        uint tokenOutBalance
    ) public pure returns (uint) {
        /*
        Newton's method to compute y
        -----------------------------
        y = x_j

        f(y) = y^2 + y(b - D) - c

                    y_n^2 + c
        y_(n+1) = --------------
                   2y_n + b - D

        where
        s = sum(x_k), k != j
        p = prod(x_k), k != j
        b = s + D / (An^n)
        c = D^(n + 1) / (n^n * p * An^n)
        */
        uint a = A * N;
        uint d = _getD(tokenInBalance, tokenOutBalance);
        uint s;
        uint c = d;

        uint _x;

        _x = x;
        s += _x;
        c = (c * d) / (N * _x);

        c = (c * d) / (N * a);
        uint b = s + d / a;

        // Newton's method
        uint y_prev;
        // Initial guess, y <= d
        uint y = d;
        for (uint _i; _i < 255; ++_i) {
            y_prev = y;
            y = (y * y + c) / (2 * y + b - d);
            if (Math.abs(y, y_prev) <= 1) {
                return y;
            }
        }
        revert("y didn't converge");
    }

    /**
     * @notice Calculate the new balance of token i given precision-adjusted
     * balances xp and liquidity d
     * @dev Equation is calculate y is same as _getY
     * @param tokenOutBalance Current out balances
     * @param d Liquidity d
     * @return New balance of token i
     */
    function _getYD(uint tokenOutBalance, uint d) private pure returns (uint) {
        uint a = A * N;
        uint s;
        uint c = d;

        uint _x;
        _x = tokenOutBalance;
        s += _x;
        c = (c * d) / (N * _x);

        c = (c * d) / (N * a);
        uint b = s + d / a;

        // Newton's method
        uint y_prev;
        // Initial guess, y <= d
        uint y = d;
        for (uint _i; _i < 255; ++_i) {
            y_prev = y;
            y = (y * y + c) / (2 * y + b - d);
            if (Math.abs(y, y_prev) <= 1) {
                return y;
            }
        }
        revert("y didn't converge");
    }

    function getRate(address tokenToSwap, uint256 amountIn) public view returns (uint256) {
        uint256 s1Balance = s1Token.balanceOf(address(this));
        uint256 s2Balance = s2Token.balanceOf(address(this));

        uint256 scalingFactor = 1e18;
        uint256 newS1Balance;
        uint256 newS2Balance;
        uint256 amountOut;
        // uint256 D = _getD(s1Balance, s2Balance);

        if (tokenToSwap == address(s1Token)) {
            newS1Balance = s1Balance + amountIn;
            uint y = _getY(newS1Balance, s1Balance, s2Balance);
            amountOut = s2Balance - y;
        } else if (tokenToSwap == address(s2Token)) {
            newS2Balance = s2Balance + amountIn;
            uint y = _getY(newS2Balance, s2Balance, s1Balance);
            amountOut = s1Balance - y;
        } else {
            revert("Invalid token address");
        }

        return amountOut * scalingFactor / amountIn;
    }
}
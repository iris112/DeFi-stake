// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../lib/@defiat-crypto/utils/DeFiatGovernedUtils.sol";
import "../lib/@openzeppelin/token/ERC20/SafeERC20.sol";
import "../lib/@uniswap/interfaces/IUniswapV2Router02.sol";

abstract contract AnyStakeUtils is DeFiatGovernedUtils {
    using SafeERC20 for IERC20;

    event PointsUpdated(address indexed user, address points);
    event TokenUpdated(address indexed user, address token);
  
    address public router;
    address public factory;
    address public weth;
    address public DeFiatToken;
    address public DeFiatPoints;
    address public DeFiatTokenLp;
    address public DeFiatPointsLp;

    mapping (address => bool) internal _blacklistedAdminWithdraw;

    constructor(address _router, address _gov, address _points, address _token) public {
        _setGovernance(_gov);

        router = _router;
        DeFiatPoints = _points;
        DeFiatToken = _token;
         
        weth = IUniswapV2Router02(router).WETH();
        factory = IUniswapV2Router02(router).factory();
        DeFiatTokenLp = address(0);// IUniswapV2Factory(factory).getPair(dft, weth);
        DeFiatPointsLp = address(0); //IUniswapV2Factory(factory).getPair(dftp, weth);
    }

    function sweep(address _token) external override onlyOwner {
        require(!_blacklistedAdminWithdraw[_token], "Sweep: Cannot withdraw blacklisted token");

        this.sweep(_token);
    }

    function isBlacklistedAdminWithdraw(address _token)
        external
        view
        returns (bool)
    {
        return _blacklistedAdminWithdraw[_token];
    }

    // Method to avoid underflow on token transfers
    function safeTokenTransfer(address user, address token, uint256 amount) internal {
        if (amount == 0) {
            return;
        }

        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        if (amount > tokenBalance) {
            IERC20(token).safeTransfer(user, tokenBalance);
        } else {
            IERC20(token).safeTransfer(user, amount);
        }
    }

    function setToken(address _token) external onlyGovernor {
        require(_token != DeFiatToken, "SetToken: No token change");
        require(_token != address(0), "SetToken: Must set token value");

        DeFiatToken = _token;
        emit TokenUpdated(msg.sender, DeFiatToken);
    }

    function setPoints(address _points) external onlyGovernor {
        require(_points != DeFiatPoints, "SetPoints: No points change");
        require(_points != address(0), "SetPoints: Must set points value");

        DeFiatPoints = _points;
        emit PointsUpdated(msg.sender, DeFiatPoints);
    }
}
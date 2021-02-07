// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./lib/@defiat/interfaces/IDeFiatPoints.sol";
import "./interfaces/IAnyStakeRegulator.sol";
import "./interfaces/IAnyStakeVault.sol";
import "./utils/AnyStakeUtils.sol";

//series of pool weighted by token price (using price oracles on chain)
contract AnyStakeRegulator is IAnyStakeRegulator, AnyStakeUtils {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event Claim(address indexed user, uint256 amount);
    event Deposit(address indexed user, uint256 amount);

    struct UserInfo {
        uint256 amount;
        uint256 rewardPaid;
        uint256 lastEntryBlock;
    }

    mapping (address => UserInfo) public userInfo;
    
    address public Vault;
    bool public initialized;
    uint256 public priceMultiplier; // pegs price at DFT_PRICE * (priceMultiplier / 1000)
    uint256 public exponentialRetry; // exponentially increases burn on each successive attempt
    uint256 public accDFTPerShare;

    modifier NoReentrant(address user) {
        require(
            block.number > userInfo[user].lastEntryBlock,
            "No Reentrancy: Must wait 1 block performing this operation"
        );
        _;
    }

    modifier activated() {
        require(initialized, "Contract has not be initialized yet");
        _;
    }

    constructor(address _router, address _gov, address _points, address _token) 
        public 
        AnyStakeUtils(_router, _gov, _points, _token)
    {
        priceMultiplier = 2500; // 2.5x, min DFT fee/burn needed to generate 1 DFTP 
    }

    function initialize(address vault) external onlyGovernor {
        initialized = true;
        Vault = vault;
    }

    function stabilize(uint256 amount) internal {
        uint256 DFTPrice = IAnyStakeVault(Vault).getTokenPrice(DeFiatPoints, address(0));
        uint256 DFTPPrice = IAnyStakeVault(Vault).getTokenPrice(DeFiatPoints, address(0));

        if (DFTPPrice > DFTPrice.mul(priceMultiplier.div(1000))) {
            // sell DFTP, buy DFT. 
            // Raises price of DFT
            IERC20(DeFiatPoints).safeTransfer(Vault, amount);
            IAnyStakeVault(Vault).buyDFTWithTokens(DeFiatPoints, amount);
        } else {
            // burn deposited DFTP, burn DFTP from Uniswap proportionally.
            // Raises price of DFTP

            uint256 pointsLiquidity = IERC20(DeFiatPoints).balanceOf(DeFiatPointsLp);
            uint256 adjustedSupply = IERC20(DeFiatPoints).totalSupply().sub(pointsLiquidity);
            uint256 burnRatio = amount.div(adjustedSupply); // check math, may need to burn more

            IDeFiatPoints(DeFiatPoints).overrideLoyaltyPoints(address(this), 0);
            IDeFiatPoints(DeFiatPoints).overrideLoyaltyPoints(DeFiatPointsLp, pointsLiquidity.mul(burnRatio)); 
        }
    }

    // update pool rewards
    function updatePool() external override {

    }

    function claim() external override activated NoReentrant(msg.sender) {
        _claim(msg.sender);
    }

    function _claim(address user) internal {
        UserInfo storage _user = userInfo[user];

        if (_user.amount == 0) {
            return;
        }

        // calculate user.rewards

        _user.amount = 0; // burn entire stake
        //_user.rewardPaid = ...
        _user.lastEntryBlock = block.number;

        emit Claim(user, 0);
    }

    function deposit(uint256 amount) external override activated NoReentrant(msg.sender) {
        _deposit(msg.sender, amount);
    }

    function _deposit(address user, uint256 amount) internal {
        require(amount > 0, "Deposit: Cannot deposit zero tokens");

        UserInfo storage _user = userInfo[user];

        IERC20(DeFiatPoints).safeTransferFrom(user, address(this), amount);

        stabilize(amount); // perform stabilization

        _user.amount = _user.amount.add(amount);
        //_user.rewardPaid = ...
        _user.lastEntryBlock = block.number;

        emit Deposit(user, amount);
    }
}
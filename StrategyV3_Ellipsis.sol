// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./StrategyV3.sol";

interface ILpStaker {
    function poolInfo(uint256 _pid) external view returns (address, uint256, uint256, uint256, uint256);
    function userInfo(uint256 _pid, address _user) external view returns (uint256, uint256);
    function claimableReward(uint256 _pid, address _user) external view returns (uint256);
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function emergencyWithdraw(uint256 _pid) external;
    function claim(uint256[] calldata _pids) external;
}

interface I2PoolLP {
    function add_liquidity(uint256[2] memory amounts, uint256 min_mint_amount) external;
}
interface I3PoolLP {
    function add_liquidity(uint256[3] memory amounts, uint256 min_mint_amount) external;
}
interface I4PoolLP {
    function add_liquidity(uint256[4] memory amounts, uint256 min_mint_amount) external;
}

interface IMultiFeeDistribution {
    function exit() external;
}

contract StrategyV3_Ellipsis is StrategyV3 {
    address public epsLPAddress;
    address public feeDistribution;
    uint256 public nPools;
    uint256 public iPool;

    constructor(
        address[] memory _addresses,
        address[] memory _tokenAddresses,
        uint256 _pid,
        address[] memory _earnedToNATIVEPath,
        address[] memory _earnedToToken0Path,
        address[] memory _earnedToToken1Path,
        address[] memory _token0ToEarnedPath,
        address[] memory _token1ToEarnedPath,
        uint256 _depositFeeFactor,
        uint256 _withdrawFeeFactor,
        uint256 _entranceFeeFactor,
        address _epsLPAddress,
        address _feeDistribution,
        uint256 _nPools,
        uint256 _iPool
    ) public {
        nativeFarmAddress = _addresses[0];
        farmContractAddress = _addresses[1];
        govAddress = _addresses[2];
        uniRouterAddress = _addresses[3];

        NATIVEAddress = _tokenAddresses[0];
        wbnbAddress = _tokenAddresses[1];
        wantAddress = _tokenAddresses[2];
        earnedAddress = _tokenAddresses[3];
        token0Address = _tokenAddresses[4];
        token1Address = _tokenAddresses[5];

        pid = _pid;
        isSingleVault = true;
        isAutoComp = true;

        earnedToNATIVEPath = _earnedToNATIVEPath;
        earnedToToken0Path = _earnedToToken0Path;
        earnedToToken1Path = _earnedToToken1Path;
        token0ToEarnedPath = _token0ToEarnedPath;
        token1ToEarnedPath = _token1ToEarnedPath;

        depositFeeFactor = _depositFeeFactor;
        withdrawFeeFactor = _withdrawFeeFactor;
        entranceFeeFactor = _entranceFeeFactor;

        epsLPAddress = _epsLPAddress;
        feeDistribution = _feeDistribution;
        nPools = _nPools;
        iPool = _iPool;
        require(iPool < nPools, "Invalid iPool");

        transferOwnership(nativeFarmAddress);
    }

    function earn() public override nonReentrant whenNotPaused {
        require(isAutoComp, "!isAutoComp");

        // Harvest farm tokens
        uint256[] memory pids = new uint256[](1);
        pids[0] = pid;
        ILpStaker(farmContractAddress).claim(pids);    //Mints EPS to feeDistribution contract where they are stored as "vesting"
        IMultiFeeDistribution(feeDistribution).exit();

        // Converts farm tokens into want tokens
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        earnedAmt = distributeFees(earnedAmt);
        earnedAmt = buyBack(earnedAmt);

        IERC20(earnedAddress).safeApprove(uniRouterAddress, 0);
        IERC20(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            earnedAmt
        );

        _safeSwap(
            uniRouterAddress,
            earnedAmt,
            slippageFactor,
            earnedToToken0Path,
            address(this),
            now + routerDeadlineDuration
        );

        // Get want tokens, ie. get iToken
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));


        IERC20(token0Address).safeIncreaseAllowance(epsLPAddress, token0Amt);
        if (nPools == 2) {
            uint256[2] memory uamounts;
            uamounts[iPool] = token0Amt;
            I2PoolLP(epsLPAddress).add_liquidity(uamounts, 0);
        } else if (nPools == 3) {
            uint256[3] memory uamounts;
            uamounts[iPool] = token0Amt;
            I3PoolLP(epsLPAddress).add_liquidity(uamounts, 0);
        } else if (nPools == 4) {
            uint256[4] memory uamounts;
            uamounts[iPool] = token0Amt;
            I4PoolLP(epsLPAddress).add_liquidity(uamounts, 0);
        } else {
            revert("Invalid nPools");
        }
        // ILoanToken(wantAddress).mint(address(this), token0Amt);

        lastEarnBlock = block.number;
        _farm();
    }
}
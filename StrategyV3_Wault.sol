// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./StrategyV3.sol";

interface IWaultFarm {
    // Deposit LP tokens to the farm for farm's token allocation.
    function deposit(uint256 _pid, uint256 _amount, bool _withdrawRewards) external;

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount, bool _withdrawRewards) external;
}

contract StrategyV3_Wault is StrategyV3 {
    constructor(
        address[] memory _addresses,
        address[] memory _tokenAddresses,
        bool _isSingleVault,
        bool _isAutoComp,
        uint256 _pid,
        address[] memory _earnedToNATIVEPath,
        address[] memory _earnedToToken0Path,
        address[] memory _earnedToToken1Path,
        address[] memory _token0ToEarnedPath,
        address[] memory _token1ToEarnedPath,
        uint256 _depositFeeFactor,
        uint256 _withdrawFeeFactor,
        uint256 _entranceFeeFactor
    ) public {
        nativeFarmAddress = _addresses[0];
        farmContractAddress = _addresses[1];
        govAddress = _addresses[2];
        uniRouterAddress = _addresses[3];
        buybackRouterAddress = _addresses[4];

        NATIVEAddress = _tokenAddresses[0];
        wbnbAddress = _tokenAddresses[1];
        wantAddress = _tokenAddresses[2];
        earnedAddress = _tokenAddresses[3];
        token0Address = _tokenAddresses[4];
        token1Address = _tokenAddresses[5];

        pid = _pid;
        isSingleVault = _isSingleVault;
        isAutoComp = _isAutoComp;

        earnedToNATIVEPath = _earnedToNATIVEPath;
        earnedToToken0Path = _earnedToToken0Path;
        earnedToToken1Path = _earnedToToken1Path;
        token0ToEarnedPath = _token0ToEarnedPath;
        token1ToEarnedPath = _token1ToEarnedPath;

        depositFeeFactor = _depositFeeFactor;
        withdrawFeeFactor = _withdrawFeeFactor;
        entranceFeeFactor = _entranceFeeFactor;

        transferOwnership(nativeFarmAddress);
    }

    function _farm() internal override virtual {
        require(isAutoComp, "!isAutoComp");
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        wantLockedTotal = wantLockedTotal.add(wantAmt);
        IERC20(wantAddress).safeIncreaseAllowance(farmContractAddress, wantAmt);

        IWaultFarm(farmContractAddress).deposit(pid, wantAmt, false);
    }

    function _unfarm(uint256 _wantAmt) internal override virtual {
        IWaultFarm(farmContractAddress).withdraw(pid, _wantAmt, true);
    }

}
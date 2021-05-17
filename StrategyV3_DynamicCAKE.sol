// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./StrategyV3.sol";

interface ISmartChef {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;
}

contract StrategyV3_DynamicCAKE is StrategyV3 {
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
        uint256 _entranceFeeFactor
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

        transferOwnership(nativeFarmAddress);
    }

    function _farm() internal override {
        require(isAutoComp, "!isAutoComp");
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        wantLockedTotal = wantLockedTotal.add(wantAmt);
        IERC20(wantAddress).safeIncreaseAllowance(farmContractAddress, wantAmt);

        ISmartChef(farmContractAddress).deposit(wantAmt);
    }

    function _unfarm(uint256 _wantAmt) internal override {
        ISmartChef(farmContractAddress).withdraw(_wantAmt);
    }

    function switchPool(
        address _farmContractAddress,
        address _earnedAddress,
        address[] memory _earnedToNATIVEPath,
        address[] memory _earnedToToken0Path
    )
        external
        nonReentrant
        onlyAllowGov 
    {
        _unfarm(wantLockedTotal);

         uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        earnedAmt = distributeFees(earnedAmt);
        earnedAmt = buyBack(earnedAmt);

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

        lastEarnBlock = block.number;

        farmContractAddress = _farmContractAddress;
        earnedAddress = _earnedAddress;
        earnedToNATIVEPath = _earnedToNATIVEPath;
        earnedToToken0Path = _earnedToToken0Path;

        IERC20(wantAddress).safeIncreaseAllowance(farmContractAddress, wantLockedTotal);
        ISmartChef(farmContractAddress).deposit(wantLockedTotal);
    }
}
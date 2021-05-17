// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./StrategyV3.sol";

interface ILoanToken {
    function mint(address receiver, uint256 depositAmount)
        external
        returns (uint256);
}

contract StrategyV3_BZX is StrategyV3 {
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

    function earn() public override nonReentrant whenNotPaused {
        require(isAutoComp, "!isAutoComp");

        // Harvest farm tokens
        _unfarm(0);

        if (earnedAddress == wbnbAddress) {
            _wrapBNB();
        }

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

        IERC20(token0Address).safeApprove(wantAddress, 0);
        IERC20(token0Address).safeIncreaseAllowance(wantAddress, token0Amt);

        ILoanToken(wantAddress).mint(address(this), token0Amt);

        lastEarnBlock = block.number;
        _farm();
    }
}
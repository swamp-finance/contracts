// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;


import "./interfaces/IERC20.sol";

import "./libraries/SafeERC20.sol";

import "./helpers/ReentrancyGuard.sol";
import "./helpers/Pausable.sol";
import "./helpers/Ownable.sol";

interface IXLoan {
    function mint(address receiver, uint256 depositAmount)
        external
        returns (uint256); // mintAmount
}

interface IXswapFarm {
    function poolLength() external view returns (uint256);

    function userInfo() external view returns (uint256);

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
        external
        view
        returns (uint256);

    // View function to see pending CAKEs on frontend.
    // function pendingCake(uint256 _pid, address _user)
    //     external
    //     view
    //     returns (uint256);

    // Deposit LP tokens to the farm for farm's token allocation.
    function deposit(uint256 _pid, uint256 _amount) external;

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external;

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external;

    // stakedWantTokens
    function stakedWantTokens(uint256 _pid, address _user)
        external
        view
        returns (uint256);
}

interface IXRouter01 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) external pure returns (uint256 amountB);

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut);

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountIn);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

interface IXRouter02 is IXRouter01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

contract StrategyBZX is Ownable, ReentrancyGuard, Pausable {
    // Maximises yields in e.g. pancakeswap

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public farmContractAddress; // address of farm, eg, PCS, Thugs etc.
    uint256 public pid; // pid of pool in farmContractAddress
    address public wantAddress; // iBUSD, iBNB, etc
    address public wantAddressOrig; // BUSD, WBNB, etc
    address public earnedAddress;
    address public uniRouterAddress; // uniswap, pancakeswap etc
    address public buybackRouterAddress = 0x10ED43C718714eb63d5aA57B78B54704E256024E; // uniswap, pancakeswap etc
    uint256 public routerDeadlineDuration = 300;  // Set on global level, could be passed to functions via arguments

    address public wbnbAddress; // should be WBNB or BUSD
    address public nativeFarmAddress;
    address public NATIVEAddress;
    address public govAddress = 0xC0dDa6d4dD7b38E99452Fa99b6090637353e4064; // timelock contract

    uint256 public lastEarnBlock = 0;
    uint256 public wantLockedTotal = 0;
    uint256 public sharesTotal = 0;

    uint256 public controllerFee = 200;
    uint256 public constant controllerFeeMax = 10000; // 100 = 1%
    uint256 public constant controllerFeeUL = 300;

    uint256 public depositFeeFactor; // 9600 == 4% fee
    uint256 public constant depositFeeFactorMax = 10000; // 100 = 1%
    uint256 public constant depositFeeFactorLL = 9500;

    uint256 public withdrawFeeFactor;
    uint256 public constant withdrawFeeFactorMax = 10000;
    uint256 public constant withdrawFeeFactorLL = 9950;

    uint256 public buyBackRate = 200;
    uint256 public constant buyBackRateMax = 10000; // 100 = 1%
    uint256 public constant buyBackRateUL = 800;
    /* This is vanity address -  For instance an address 0x000000000000000000000000000000000000dEaD for which it's
       absolutely impossible to generate a private key with today's computers. */
    address public constant buyBackAddress = 0x000000000000000000000000000000000000dEaD;
    uint256 public entranceFeeFactor; // < 0.1% entrance fee - goes to pool + prevents front-running
    uint256 public constant entranceFeeFactorMax = 10000;
    uint256 public constant entranceFeeFactorLL = 9950; // 0.5% is the max entrance fee settable. LL = lowerlimit

    uint256 public exitFeeFactor; // < 0.1% exit fee - goes to pool
    uint256 public constant exitFeeFactorMax = 10000;
    uint256 public constant exitFeeFactorLL = 9950; // 0.5% is the max exit fee settable. LL = lowerlimit

    address[] public earnedToNATIVEPath;
    address[] public earnedToWantPath;
    address[] public earnedToWBNBPath;
    address[] public WBNBToNATIVEPath;

    constructor(
        address _nativeFarmAddress,
        address _NATIVEAddress,
        address _farmContractAddress,
        uint256 _pid,
        address _wantAddress,
        address _wantAddressOrig,
        address _earnedAddress,
        address _uniRouterAddress,
        address _wbnbAddress,
        uint256 _depositFeeFactor,
        uint256 _withdrawFeeFactor,
        uint256 _entranceFeeFactor,
        uint256 _exitFeeFactor
    ) public {
        nativeFarmAddress = _nativeFarmAddress;
        NATIVEAddress = _NATIVEAddress;

        wantAddress = _wantAddress;
        wantAddressOrig = _wantAddressOrig;
        wbnbAddress = _wbnbAddress;

        depositFeeFactor = _depositFeeFactor;
        withdrawFeeFactor = _withdrawFeeFactor;
        entranceFeeFactor = _entranceFeeFactor;
        exitFeeFactor = _exitFeeFactor;

        farmContractAddress = _farmContractAddress;
        pid = _pid;
        earnedAddress = _earnedAddress;

        uniRouterAddress = _uniRouterAddress;

        earnedToNATIVEPath = [earnedAddress, wbnbAddress, NATIVEAddress];
        if (wbnbAddress == earnedAddress) {
            earnedToNATIVEPath = [wbnbAddress, NATIVEAddress];
        }

        earnedToWantPath = [earnedAddress, wbnbAddress, wantAddressOrig];
        if (wbnbAddress == wantAddressOrig) {
            earnedToWantPath = [earnedAddress, wantAddressOrig];
        }

        earnedToWBNBPath = [earnedAddress, wbnbAddress];
        WBNBToNATIVEPath = [wbnbAddress, NATIVEAddress];

        transferOwnership(nativeFarmAddress);
    }

    modifier onlyAllowGov() {
        require(msg.sender == govAddress, "Not authorised");
        _;
    }

    // Receives new deposits from user
    function deposit(address _userAddress, uint256 _wantAmt)
        public
        onlyOwner
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        IERC20(wantAddress).safeTransferFrom(
            address(msg.sender),
            address(this),
            _wantAmt
        );

        // If depositFee in set, than _wantAmt - depositFee
        if (depositFeeFactor < depositFeeFactorMax) {
            _wantAmt = _wantAmt.mul(depositFeeFactor).div(depositFeeFactorMax);
        }

        // update wantLockedTotal, could deviate because of Venus loans
        wantLockedTotal = IXswapFarm(farmContractAddress).stakedWantTokens(pid, address(this));

        uint256 sharesAdded = _wantAmt;
        if (wantLockedTotal > 0) {
            sharesAdded = _wantAmt
                .mul(sharesTotal)
                .mul(entranceFeeFactor)
                .div(wantLockedTotal)
                .div(entranceFeeFactorMax);

            // Fix if pool stuck
            if (sharesAdded == 0 && sharesTotal == 0) {
                sharesAdded = _wantAmt
                    .mul(entranceFeeFactor)
                    .div(wantLockedTotal)
                    .div(entranceFeeFactorMax);
            }
        }
        sharesTotal = sharesTotal.add(sharesAdded);

        _farm();

        return sharesAdded;
    }

    function farm() public nonReentrant {
        _farm();
    }

    function _farm() internal {
        // reinvest harvested amount
        uint256 wantOrigAmt = IERC20(wantAddressOrig).balanceOf(address(this));
        if (wantOrigAmt > 0) {
            IERC20(wantAddressOrig).safeIncreaseAllowance(wantAddress, wantOrigAmt);

            // swap wantOrig for iTOKEN
            IXLoan(wantAddress).mint(address(this), wantOrigAmt);
        }

        // reinvest received iTOKEN
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        IERC20(wantAddress).safeIncreaseAllowance(farmContractAddress, wantAmt);
        IXswapFarm(farmContractAddress).deposit(pid, wantAmt);

        // update wantLockedTotal (should be higher because of external auto-compounding + reinvested harvested amount)
        wantLockedTotal = IXswapFarm(farmContractAddress).stakedWantTokens(pid, address(this));
    }

    function withdraw(address _userAddress, uint256 _wantAmt)
        public
        onlyOwner
        nonReentrant
        returns (uint256)
    {
        require(_wantAmt > 0, "_wantAmt <= 0");

        // update wantLockedTotal, could deviate because of Venus loans
        wantLockedTotal = IXswapFarm(farmContractAddress).stakedWantTokens(pid, address(this));

        IXswapFarm(farmContractAddress).withdraw(pid, _wantAmt);

        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        if (_wantAmt > wantAmt) {
            _wantAmt = wantAmt;
        }

        if (wantLockedTotal < _wantAmt) {
            _wantAmt = wantLockedTotal;
        }

        uint256 wantAmtWithFee = _wantAmt;
        if (withdrawFeeFactor < withdrawFeeFactorMax) {
            wantAmtWithFee = _wantAmt.mul(withdrawFeeFactorMax).div(withdrawFeeFactor);
        }

        uint256 sharesRemoved = wantAmtWithFee.mul(sharesTotal).div(wantLockedTotal);
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        sharesTotal = sharesTotal.sub(sharesRemoved);
        wantLockedTotal = wantLockedTotal.sub(wantAmtWithFee);

        if (exitFeeFactor < exitFeeFactorMax) {
            _wantAmt = _wantAmt.mul(exitFeeFactor).div(exitFeeFactorMax);
        }

        IERC20(wantAddress).safeTransfer(nativeFarmAddress, _wantAmt);

        return sharesRemoved;
    }

    // 1. Harvest farm tokens
    // 2. Converts farm tokens into want tokens
    // 3. Deposits want tokens

    function earn() public nonReentrant whenNotPaused {

        // Harvest farm tokens
        IXswapFarm(farmContractAddress).withdraw(pid, 0);

        // Converts farm tokens into want tokens
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        earnedAmt = distributeFees(earnedAmt);
        earnedAmt = buyBack(earnedAmt);

        if (earnedAddress != wantAddressOrig) {
            IERC20(earnedAddress).safeIncreaseAllowance(
                uniRouterAddress,
                earnedAmt
            );

            // Swap earned to wantOrig (BUSD,WBNB,...)
            IXRouter02(uniRouterAddress)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                earnedAmt,
                0,
                earnedToWantPath,
                address(this),
                now + routerDeadlineDuration
            );
        }

        lastEarnBlock = block.number;
        _farm();
        return;
    }

    function buyBack(uint256 _earnedAmt) internal returns (uint256) {
        if (buyBackRate <= 0) {
            return _earnedAmt;
        }

        uint256 buyBackAmt = _earnedAmt.mul(buyBackRate).div(buyBackRateMax);

        if (uniRouterAddress != buybackRouterAddress) {
            // Example case: LP token on ApeSwap and NATIVE token on PancakeSwap

            if (earnedAddress != wbnbAddress) {
                // First convert earn to wbnb
                IERC20(earnedAddress).safeIncreaseAllowance(
                    uniRouterAddress,
                    buyBackAmt
                );

                IXRouter02(uniRouterAddress)
                    .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    buyBackAmt,
                    0,
                    earnedToWBNBPath,
                    address(this),
                    now + routerDeadlineDuration
                );
            }

            // convert all wbnb to Native and burn them
            uint256 wbnbAmt = IERC20(wbnbAddress).balanceOf(address(this));
            if (wbnbAmt > 0) {
                IERC20(wbnbAddress).safeIncreaseAllowance(
                    buybackRouterAddress,
                    wbnbAmt
                );

                IXRouter02(buybackRouterAddress)
                    .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    wbnbAmt,
                    0,
                    WBNBToNATIVEPath,
                    buyBackAddress,
                    now + routerDeadlineDuration
                );
            }
        } else {
            // Both LP and NATIVE token on same swap

            IERC20(earnedAddress).safeIncreaseAllowance(
                uniRouterAddress,
                buyBackAmt
            );

            IXRouter02(uniRouterAddress)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                buyBackAmt,
                0,
                earnedToNATIVEPath,
                buyBackAddress,
                now + routerDeadlineDuration
            );
        }

        return _earnedAmt.sub(buyBackAmt);
    }

    function distributeFees(uint256 _earnedAmt) internal returns (uint256) {
        if (_earnedAmt > 0) {
            // Performance fee
            if (controllerFee > 0) {
                uint256 fee =
                    _earnedAmt.mul(controllerFee).div(controllerFeeMax);
                IERC20(earnedAddress).safeTransfer(govAddress, fee);
                _earnedAmt = _earnedAmt.sub(fee);
            }
        }

        return _earnedAmt;
    }

    function convertDustToEarned() public whenNotPaused {}

    function pause() public onlyAllowGov {
        _pause();
    }

    function unpause() external onlyAllowGov {
        _unpause();
    }

    function setEntranceFeeFactor(uint256 _entranceFeeFactor) public onlyAllowGov {
        require(_entranceFeeFactor > entranceFeeFactorLL, "!safe - too low");
        require(_entranceFeeFactor <= entranceFeeFactorMax, "!safe - too high");
        entranceFeeFactor = _entranceFeeFactor;
    }

    function setExitFeeFactor(uint256 _exitFeeFactor) public onlyAllowGov{
        require(_exitFeeFactor > exitFeeFactorLL, "!safe - too low");
        require(_exitFeeFactor <= exitFeeFactorMax, "!safe - too high");
        exitFeeFactor = _exitFeeFactor;
    }

    function setControllerFee(uint256 _controllerFee) public onlyAllowGov{
        require(_controllerFee <= controllerFeeUL, "too high");
        controllerFee = _controllerFee;
    }

    function setDepositFeeFactor(uint256 _depositFeeFactor) public onlyAllowGov{
        require(_depositFeeFactor > depositFeeFactorLL, "!safe - too low");
        require(_depositFeeFactor <= depositFeeFactorMax, "!safe - too high");
        depositFeeFactor = _depositFeeFactor;
    }

    function setWithdrawFeeFactor(uint256 _withdrawFeeFactor) public onlyAllowGov {
        require(_withdrawFeeFactor > withdrawFeeFactorLL, "!safe - too low");
        require(_withdrawFeeFactor <= withdrawFeeFactorMax, "!safe - too high");
        withdrawFeeFactor = _withdrawFeeFactor;
    }

    function setbuyBackRate(uint256 _buyBackRate) public onlyAllowGov {
        require(buyBackRate <= buyBackRateUL, "too high");
        buyBackRate = _buyBackRate;
    }

    function setGov(address _govAddress) public onlyAllowGov {
        govAddress = _govAddress;
    }

    function setBuybackRouterAddress(address _buybackRouterAddress) public onlyAllowGov {
        buybackRouterAddress = _buybackRouterAddress;
    }

    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) public onlyAllowGov {
        require(_token != earnedAddress, "!safe");
        require(_token != wantAddress, "!safe");
        IERC20(_token).safeTransfer(_to, _amount);
    }
}

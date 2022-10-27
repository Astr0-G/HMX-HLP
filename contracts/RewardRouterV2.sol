// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./libraries/math/SafeMath.sol";
import "./libraries/token/IERC20.sol";
import "./libraries/token/SafeERC20.sol";
import "./libraries/utils/ReentrancyGuard.sol";
import "./libraries/utils/Address.sol";

import "./interfaces/IRewardTracker.sol";
import "./interfaces/IVester.sol";
import "./interfaces/IMintable.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IGlpManager.sol";
import "./Governable.sol";

contract RewardRouterV2 is ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    address public weth;

    address public gmx;
    address public esGmx;

    address public glp; // GMX Liquidity Provider token

    address public stakedGmxTracker;
    address public bonusGmxTracker;
    address public feeGmxTracker;

    address public stakedGlpTracker;
    address public feeGlpTracker;

    address public glpManager;

    address public gmxVester;
    address public glpVester;

    mapping(address => address) public pendingReceivers;

    event StakeGmx(address account, address token, uint256 amount);
    event UnstakeGmx(address account, address token, uint256 amount);

    event StakeGlp(address account, uint256 amount);
    event UnstakeGlp(address account, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    function initialize(
        address _weth,
        address _gmx,
        address _esGmx,
        address _glp,
        address _stakedGmxTracker,
        address _bonusGmxTracker,
        address _feeGmxTracker,
        address _feeGlpTracker,
        address _stakedGlpTracker,
        address _glpManager,
        address _gmxVester,
        address _glpVester
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;

        weth = _weth;

        gmx = _gmx;
        esGmx = _esGmx;

        glp = _glp;

        stakedGmxTracker = _stakedGmxTracker;
        bonusGmxTracker = _bonusGmxTracker;
        feeGmxTracker = _feeGmxTracker;

        feeGlpTracker = _feeGlpTracker;
        stakedGlpTracker = _stakedGlpTracker;

        glpManager = _glpManager;

        gmxVester = _gmxVester;
        glpVester = _glpVester;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function batchStakeGmxForAccount(address[] memory _accounts, uint256[] memory _amounts)
        external
        nonReentrant
        onlyGov
    {
        address _gmx = gmx;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stakeGmx(msg.sender, _accounts[i], _gmx, _amounts[i]);
        }
    }

    function stakeGmxForAccount(address _account, uint256 _amount) external nonReentrant onlyGov {
        _stakeGmx(msg.sender, _account, gmx, _amount);
    }

    function stakeGmx(uint256 _amount) external nonReentrant {
        _stakeGmx(msg.sender, msg.sender, gmx, _amount);
    }

    function stakeEsGmx(uint256 _amount) external nonReentrant {
        _stakeGmx(msg.sender, msg.sender, esGmx, _amount);
    }

    function unstakeGmx(uint256 _amount) external nonReentrant {
        _unstakeGmx(msg.sender, gmx, _amount);
    }

    function unstakeEsGmx(uint256 _amount) external nonReentrant {
        _unstakeGmx(msg.sender, esGmx, _amount);
    }

    function mintAndStakeGlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minGlp
    ) external nonReentrant returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        uint256 glpAmount = IGlpManager(glpManager).addLiquidityForAccount(
            account,
            account,
            _token,
            _amount,
            _minUsdg,
            _minGlp
        );
        IRewardTracker(feeGlpTracker).stakeForAccount(account, account, glp, glpAmount);
        IRewardTracker(stakedGlpTracker).stakeForAccount(
            account,
            account,
            feeGlpTracker,
            glpAmount
        );

        emit StakeGlp(account, glpAmount);

        return glpAmount;
    }

    function mintAndStakeGlpETH(uint256 _minUsdg, uint256 _minGlp)
        external
        payable
        nonReentrant
        returns (uint256)
    {
        require(msg.value > 0, "RewardRouter: invalid msg.value");

        IWETH(weth).deposit{value: msg.value}();
        IERC20(weth).approve(glpManager, msg.value);

        address account = msg.sender;
        uint256 glpAmount = IGlpManager(glpManager).addLiquidityForAccount(
            address(this),
            account,
            weth,
            msg.value,
            _minUsdg,
            _minGlp
        );

        IRewardTracker(feeGlpTracker).stakeForAccount(account, account, glp, glpAmount);
        IRewardTracker(stakedGlpTracker).stakeForAccount(
            account,
            account,
            feeGlpTracker,
            glpAmount
        );

        emit StakeGlp(account, glpAmount);

        return glpAmount;
    }

    function unstakeAndRedeemGlp(
        address _tokenOut,
        uint256 _glpAmount,
        uint256 _minOut,
        address _receiver
    ) external nonReentrant returns (uint256) {
        require(_glpAmount > 0, "RewardRouter: invalid _glpAmount");

        address account = msg.sender;
        IRewardTracker(stakedGlpTracker).unstakeForAccount(
            account,
            feeGlpTracker,
            _glpAmount,
            account
        );
        IRewardTracker(feeGlpTracker).unstakeForAccount(account, glp, _glpAmount, account);
        // uint256 amountOut = IGlpManager(glpManager).removeLiquidityForAccount(
        //     account,
        //     _tokenOut,
        //     _glpAmount,
        //     _minOut,
        //     _receiver
        // );

        emit UnstakeGlp(account, _glpAmount);

        return 10;
    }

    function unstakeAndRedeemGlpETH(
        uint256 _glpAmount,
        uint256 _minOut,
        address payable _receiver
    ) external nonReentrant returns (uint256) {
        require(_glpAmount > 0, "RewardRouter: invalid _glpAmount");

        address account = msg.sender;
        IRewardTracker(stakedGlpTracker).unstakeForAccount(
            account,
            feeGlpTracker,
            _glpAmount,
            account
        );
        IRewardTracker(feeGlpTracker).unstakeForAccount(account, glp, _glpAmount, account);
        // uint256 amountOut = IGlpManager(glpManager).removeLiquidityForAccount(
        //     account,
        //     weth,
        //     _glpAmount,
        //     _minOut,
        //     address(this)
        // );

        IWETH(weth).withdraw(10);

        _receiver.sendValue(10);

        emit UnstakeGlp(account, _glpAmount);

        return 10;
    }

    function claim() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeGmxTracker).claimForAccount(account, account);
        IRewardTracker(feeGlpTracker).claimForAccount(account, account);

        IRewardTracker(stakedGmxTracker).claimForAccount(account, account);
        IRewardTracker(stakedGlpTracker).claimForAccount(account, account);
    }

    function claimEsGmx() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(stakedGmxTracker).claimForAccount(account, account);
        IRewardTracker(stakedGlpTracker).claimForAccount(account, account);
    }

    function claimFees() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeGmxTracker).claimForAccount(account, account);
        IRewardTracker(feeGlpTracker).claimForAccount(account, account);
    }

    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external nonReentrant {
        address account = msg.sender;

        uint256 gmxAmount = 0;
        if (_shouldClaimGmx) {
            uint256 gmxAmount0 = IVester(gmxVester).claimForAccount(account, account);
            uint256 gmxAmount1 = IVester(glpVester).claimForAccount(account, account);
            gmxAmount = gmxAmount0.add(gmxAmount1);
        }

        if (_shouldStakeGmx && gmxAmount > 0) {
            _stakeGmx(account, account, gmx, gmxAmount);
        }

        uint256 esGmxAmount = 0;
        if (_shouldClaimEsGmx) {
            uint256 esGmxAmount0 = IRewardTracker(stakedGmxTracker).claimForAccount(
                account,
                account
            );
            uint256 esGmxAmount1 = IRewardTracker(stakedGlpTracker).claimForAccount(
                account,
                account
            );
            esGmxAmount = esGmxAmount0.add(esGmxAmount1);
        }

        if (_shouldStakeEsGmx && esGmxAmount > 0) {
            _stakeGmx(account, account, esGmx, esGmxAmount);
        }

        if (_shouldClaimWeth) {
            if (_shouldConvertWethToEth) {
                uint256 weth0 = IRewardTracker(feeGmxTracker).claimForAccount(
                    account,
                    address(this)
                );
                uint256 weth1 = IRewardTracker(feeGlpTracker).claimForAccount(
                    account,
                    address(this)
                );

                uint256 wethAmount = weth0.add(weth1);
                IWETH(weth).withdraw(wethAmount);

                payable(account).sendValue(wethAmount);
            } else {
                IRewardTracker(feeGmxTracker).claimForAccount(account, account);
                IRewardTracker(feeGlpTracker).claimForAccount(account, account);
            }
        }
    }

    function _stakeGmx(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount
    ) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IRewardTracker(stakedGmxTracker).stakeForAccount(
            _fundingAccount,
            _account,
            _token,
            _amount
        );
        IRewardTracker(bonusGmxTracker).stakeForAccount(
            _account,
            _account,
            stakedGmxTracker,
            _amount
        );
        IRewardTracker(feeGmxTracker).stakeForAccount(
            _account,
            _account,
            bonusGmxTracker,
            _amount
        );

        emit StakeGmx(_account, _token, _amount);
    }

    function _unstakeGmx(
        address _account,
        address _token,
        uint256 _amount
    ) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        uint256 balance = IRewardTracker(stakedGmxTracker).stakedAmounts(_account);

        IRewardTracker(feeGmxTracker).unstakeForAccount(
            _account,
            bonusGmxTracker,
            _amount,
            _account
        );
        IRewardTracker(bonusGmxTracker).unstakeForAccount(
            _account,
            stakedGmxTracker,
            _amount,
            _account
        );
        IRewardTracker(stakedGmxTracker).unstakeForAccount(_account, _token, _amount, _account);

        emit UnstakeGmx(_account, _token, _amount);
    }
}

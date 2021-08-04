// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@bundle-dao/pancakeswap-peripheral/contracts/interfaces/IPancakeRouter02.sol";

import "./interfaces/IController.sol";
import "./interfaces/IBundle.sol";

contract BundleVault is Ownable {
    using SafeMath for uint256;
    using Math for uint256;
    using SafeERC20 for IERC20;

    event LogShareChanged(
        address indexed caller,
        uint256         devShare
    );

    event LogCallerShareChanged(
        address indexed caller,
        uint256         callerShare
    );

    event LogDevChanged(
        address indexed caller,
        address         dev
    );

    event LogCollection(
        address indexed caller,
        uint256         amount
    );

    event LogSwapWhitelist(
        address indexed caller,
        address         token,
        bool            flag
    );

    /* ========== Storage ========== */

    struct Deposit {
        uint256 balance;
        uint256 time;
    }

    struct User {
        uint256 activeBalance;
        Deposit[] deposits;
    }

    struct ActiveRatio {
        uint256 underlying;
        uint256 active;
    }

    struct SwapToken {
        bool flag;
        uint256 index;
    }

    uint256 private constant INIT_DEV_SHARE = 30000;
    uint256 private constant MAX_DEV_SHARE = 50000;
    uint256 private constant INIT_CALLER_SHARE = 1500;
    uint256 private constant MAX_CALLER_SHARE = 5000;
    uint256 private constant DELAY = 7 days;

    IController private _controller;
    IPancakeRouter02 private _router;
    IERC20 private _bdl;
    address private _dev;
    uint256 private _cumulativeBalance;
    uint256 private _devShare;
    uint256 private _callerShare;

    mapping(address=>User) private _users;
    mapping(uint256=>ActiveRatio) private _cache;
    Deposit[] private _cumulativeDeposits;
    mapping(address=>SwapToken) private _swapWhitelist;
    address[] private _swapTokens;

    /* ========== Initialization ========== */

    constructor(address controller, address bdl, address dev, address router) public {
        // Validate addresses
        require(
            controller != address(0) && bdl != address(0) && dev != address(0),
            "ERR_ZERO_ADDRESS"
        );

        _controller = IController(controller);
        _bdl = IERC20(bdl);
        _dev = dev;
        _router = IPancakeRouter02(router);
        _devShare = INIT_DEV_SHARE;
        _callerShare = INIT_CALLER_SHARE;
    }

    /* ========== Setters ========== */

    function setDevShare(uint256 devShare) 
        external 
        onlyOwner
    {
        require(devShare <= MAX_DEV_SHARE && devShare > 0, "ERR_BAD_DEV_SHARE");
        _devShare = devShare;
        emit LogShareChanged(msg.sender, devShare);
    }

    function setCallerShare(uint256 callerShare) 
        external 
        onlyOwner
    {
        require(callerShare <= MAX_CALLER_SHARE && callerShare > 0, "ERR_BAD_CALLER_SHARE");
        _callerShare = callerShare;
        emit LogCallerShareChanged(msg.sender, callerShare);
    }

    function setDev(address dev)
        external
    {
        require(msg.sender == _dev, "ERR_NOT_DEV");
        _dev = dev;
        emit LogDevChanged(msg.sender, dev);
    }

    function setSwapWhitelist(address[] calldata tokens, bool flag)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            require(flag != _swapWhitelist[token].flag, "ERR_FLAG_NOT_CHANGED");
            uint256 index;

            if (flag) {
                _swapTokens.push(token);
                index = _swapTokens.length - 1;
            } else {
                _swapTokens[_swapWhitelist[token].index] = _swapTokens[_swapTokens.length - 1];
                _swapTokens.pop();
                index = 0;
            }

            _swapWhitelist[token] = SwapToken({
                flag: flag,
                index: index
            });

            emit LogSwapWhitelist(msg.sender, token, flag);
        }
    }

    /* ========== Getters ========== */

    function getBalance(address user)
        external view
        returns (uint256)
    {
        User memory userData = _users[user];
        uint256 balance = 0;

        balance = balance.add(
            _convertFromActive(userData.activeBalance)
        );

        uint256 time = block.timestamp.sub(DELAY);

        for (uint i = 0; i < userData.deposits.length; i++) {
            Deposit memory deposit = userData.deposits[i];
            ActiveRatio memory activeRatio = _cache[deposit.time];

            if (deposit.time <= time && activeRatio.active > 0) {
                uint256 activeAmount = deposit.balance.mul(activeRatio.active).div(activeRatio.underlying);
                balance = balance.add(_convertFromActive(activeAmount));
            } else {
                balance = balance.add(deposit.balance);
            }
        }

        return balance;
    }

    function isSwapWhitelisted(address token)
        external view
        returns (bool)
    {
        return _swapWhitelist[token].flag;
    }

    function getDev()
        external view
        returns (address)
    {
        return _dev;
    }

    function getCumulativeBalance()
        external view
        returns (uint256)
    {
        return _cumulativeBalance;
    }

    function getDevShare()
        external view
        returns (uint256)
    {
        return _devShare;
    }

    function getCallerShare()
        external view
        returns (uint256)
    {
        return _callerShare;
    }

    function getToken()
        external view
        returns (address)
    {
        return address(_bdl);
    }

    function getController()
        external view
        returns (address)
    {
        return address(_controller);
    }

    function getRouter()
        external view
        returns (address)
    {
        return address(_router);
    }

    function getSwapTokens()
        external view
        returns (address[] memory)
    {
        return _swapTokens;
    }

    function getActiveBalance(address user)
        external view
        returns (uint256)
    {
        User memory userData = _users[user];
        return _convertFromActive(userData.activeBalance);
    }

    /* ========== User Fund Movement ========== */

    function deposit(uint256 amount) external {
        // Merge user deposits
        _mergeCumulativeDeposits();
        _mergeDeposits(msg.sender);

        // Load relevant data
        uint256 time = block.timestamp.div(1 days).mul(1 days);
        bool depositExists = false;
        bool cumulativeDepositExists = false;
        User storage user = _users[msg.sender];

        // Transfer from user to the vault
        _bdl.safeTransferFrom(msg.sender, address(this), amount);

        // Add to existing deposit if present
        for (uint256 i = 0; i < user.deposits.length; i++) {
            if (user.deposits[i].time == time) {
                user.deposits[i].balance = user.deposits[i].balance.add(amount);
                depositExists = true;
            }
        }

        if (!depositExists) {
            user.deposits.push(
                Deposit({
                    time: time,
                    balance: amount
                })
            );
        }

        // Add to cumulative deposit if present
        for (uint256 i = 0; i < _cumulativeDeposits.length; i++) {
            if (_cumulativeDeposits[i].time == time) {
                _cumulativeDeposits[i].balance = _cumulativeDeposits[i].balance.add(amount);
                cumulativeDepositExists = true;
            }
        }

        if (!cumulativeDepositExists) {
            _cumulativeDeposits.push(
                Deposit({
                    time: time,
                    balance: amount
                })
            );
        }
    }

    function withdraw(uint256 amount) external {
        // Merge user deposits
        _mergeCumulativeDeposits();
        _mergeDeposits(msg.sender);

        // Load relevant data
        User storage user = _users[msg.sender];
        uint256 mutableAmount = amount;

        // Subtract from existing deposits first
        for (uint256 i = 0; i < user.deposits.length; i++) {
            uint256 subAmount = user.deposits[user.deposits.length - 1 - i].balance.min(mutableAmount);
            user.deposits[user.deposits.length - 1 - i].balance = user.deposits[user.deposits.length - 1 - i].balance.sub(subAmount);
            mutableAmount = mutableAmount.sub(subAmount);

            // Update cumulative deposit
            uint256 time = user.deposits[user.deposits.length - 1 - i].time;
            for (uint256 j = 0; j < _cumulativeDeposits.length; j++) {
                if (_cumulativeDeposits[j].time == time) {
                    _cumulativeDeposits[j].balance = _cumulativeDeposits[j].balance.sub(subAmount);
                }
            }

            // Break if we've withdrawn as much as possible
            if (mutableAmount == 0) {
                break;
            }
        }

        // Subtract from active balance
        uint256 activeAmount = _convertToActive(mutableAmount, amount.sub(mutableAmount));
        require(user.activeBalance >= activeAmount, "ERR_AMOUNT_TOO_LARGE");

        if (activeAmount > 0) {
            user.activeBalance = user.activeBalance.sub(activeAmount);
            _cumulativeBalance = _cumulativeBalance.sub(activeAmount);
        }
        
        _bdl.transfer(msg.sender, amount);
    }

    /* ========== Fee Collection ========== */

    function collect(address bundle, address[][] calldata paths) external {
        require(_cumulativeBalance > 0, "ERR_SETUP_REQUIRES_DEPOSITS");

        _mergeCumulativeDeposits();
        _controller.collectStreamingFee(bundle);

        uint256 totalCollected = 0;
        address[] memory underlying = IBundle(bundle).getCurrentTokens();
        address[] memory tokens = new address[](underlying.length + 1);

        for (uint256 i = 0; i < underlying.length; i++) {
            tokens[i] = underlying[i];
            require(paths[i][0] == tokens[i], "ERR_PATH_START");
            require(paths[i][paths[i].length - 1] == address(_bdl), "ERR_PATH_END");
        }

        require(paths.length == tokens.length, "ERR_PATHS_MISMATCH");

        tokens[underlying.length] = bundle;
        _controller.collectTokens(tokens, address(this));

        for (uint i = 0; i < tokens.length; i++) {
            if (IERC20(tokens[i]).allowance(address(this), address(_router)) != type(uint256).max) {
                IERC20(tokens[i]).approve(address(_router), type(uint256).max);
            }

            _validatePath(paths[i]);

            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            uint256[] memory amountsOut = _router.getAmountsOut(balance, paths[i]);
            uint256[] memory amountsSwappedOut = _router.swapExactTokensForTokens(
                balance, 
                amountsOut[amountsOut.length - 1].mul(97).div(100), 
                paths[i], 
                address(this), 
                block.timestamp + 10000
            );

            totalCollected = totalCollected.add(amountsSwappedOut[amountsSwappedOut.length - 1]);
        }

        if (_callerShare > 0) {
            _bdl.transfer(msg.sender, totalCollected.mul(_callerShare).div(100000));
        }
        
        if (_devShare > 0) {
            _bdl.transfer(_dev, totalCollected.mul(_devShare).div(100000));
        }

        emit LogCollection(msg.sender, totalCollected);
    }

    /* ========== Internal ========== */

    function _mergeDeposits(address userAddress) internal {
        uint256 time = block.timestamp.sub(DELAY);
        User storage user = _users[userAddress];
        uint256 mergeCounter = 0;

        // Merge deposit if older than 7 days
        for (uint256 i = 0; i < user.deposits.length; i++) {
            if (user.deposits[i].time <= time) {
                // Use cache to determine appropriate ratio
                // TODO: verify math here is equivalent to cumulative merge
                ActiveRatio memory activeRatio = _cache[user.deposits[i].time];
                uint256 activeAmount = user.deposits[i].balance.mul(activeRatio.active).div(activeRatio.underlying);
                user.activeBalance = user.activeBalance.add(activeAmount);
                user.deposits[i].balance = 0;
                mergeCounter++;
            }
        }

        // Remove deposits from array
        for (uint256 i = 0; i < user.deposits.length.sub(mergeCounter); i++) {
            user.deposits[i] = user.deposits[i + mergeCounter];
        }

        for (uint256 i = 0; i < mergeCounter; i++) {
            user.deposits.pop();
        }
    }

    // Merges valid cumulative deposits into active balance
    function _mergeCumulativeDeposits() internal {
        uint256 time = block.timestamp.sub(DELAY);
        uint256 mergeCounter = 0;

        // Merge deposit if older than 7 days
        for (uint256 i = 0; i < _cumulativeDeposits.length; i++) {
            if (_cumulativeDeposits[i].time <= time) {
                // Set the cache for user deposit merging
                _cache[_cumulativeDeposits[i].time] = ActiveRatio({
                    underlying: _cumulativeBalance > 0 ? _bdl.balanceOf(address(this)).sub(_getPendingBalance()) : 1,
                    active: _cumulativeBalance > 0 ? _cumulativeBalance : 1
                });

                // Convert to active and merge
                uint256 balance = _cumulativeDeposits[i].balance;
                _cumulativeBalance = _cumulativeBalance.add(_convertToActive(balance, 0));
                _cumulativeDeposits[i].balance = 0;
                mergeCounter++;
            }
        }

        // Remove deposits from array
        for (uint256 i = 0; i < _cumulativeDeposits.length.sub(mergeCounter); i++) {
            _cumulativeDeposits[i] = _cumulativeDeposits[i + mergeCounter];
        }

        for (uint256 i = 0; i < mergeCounter; i++) {
            _cumulativeDeposits.pop();
        }
    }

    // Converts an amount to an "active" amount accruing rewards
    function _convertToActive(uint256 amount, uint256 extra) 
        internal view 
        returns(uint256) 
    {
        // Should discount BDL from pending deposits
        if (_cumulativeBalance == 0) {
            return amount;
        } else {
            return amount.mul(_cumulativeBalance).div(_bdl.balanceOf(address(this)).sub(_getPendingBalance()).sub(extra));
        }
    }

    // Converts from an "active" amount to an underlying amount
    function _convertFromActive(uint256 amount)
        internal view
        returns(uint256)
    {
        if (_cumulativeBalance == 0) {
            return amount;
        } else {
            return amount.mul(_bdl.balanceOf(address(this)).sub(_getPendingBalance())).div(_cumulativeBalance);
        }
    }

    // Returns the current balance of all pending deposits
    function _getPendingBalance()
        internal view
        returns (uint256)
    {
        uint256 pendingBalance = 0;

        for (uint256 i = 0; i < _cumulativeDeposits.length; i++) {
            pendingBalance += _cumulativeDeposits[i].balance;
        }

        return pendingBalance;
    }

    function _validatePath(address[] memory path)
        internal view
    {
        require(path.length >= 2, "ERR_PATH_LENGTH");

        for (uint256 i = 1; i < path.length - 1; i++) {
            require(_swapWhitelist[path[i]].flag, "ERR_BAD_PATH");
        }
    }
}
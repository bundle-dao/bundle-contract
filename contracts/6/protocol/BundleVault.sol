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

    event LogDevChanged(
        address indexed caller,
        address         dev
    );

    event LogCollection(
        address indexed caller,
        uint256         amount
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

    uint256 private constant INIT_DEV_SHARE = 30000;
    uint256 private constant MAX_DEV_SHARE = 50000;
    uint256 private constant DELAY = 7 days;

    IController private _controller;
    IPancakeRouter02 private _router;
    IERC20 private _bdl;
    address private _dev;
    uint256 private _cumulativeBalance;
    uint256 private _devShare;

    mapping(address=>User) private _users;
    mapping(uint256=>ActiveRatio) private _cache;
    Deposit[] private _cumulativeDeposits;

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
    }

    /* ========== Setters ========== */

    function setDevShare(uint256 devShare) 
        external 
        onlyOwner
    {
        require(devShare <= MAX_DEV_SHARE, "ERR_MAX_DEV_SHARE");
        _devShare = devShare;
        emit LogShareChanged(msg.sender, devShare);
    }

    function setDev(address dev)
        external
    {
        require(msg.sender == _dev, "ERR_NOT_DEV");
        _dev = dev;
        emit LogDevChanged(msg.sender, dev);
    }

    /* ========== User Fund Movement ========== */

    function deposit(uint256 amount) external {
        // Merge user deposits
        _mergeCumulativeDeposits();
        _mergeDeposits(msg.sender);

        // Load relevant data
        uint256 time = block.timestamp.mod(1 days).mul(1 days);
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
            for (uint256 j = 0; i < _cumulativeDeposits.length; i++) {
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
        uint256 activeAmount = mutableAmount == 0 ? 0 : _convertToActive(mutableAmount);

        require(user.activeBalance >= activeAmount, "ERR_AMOUNT_TOO_LARGE");

        user.activeBalance = user.activeBalance.sub(activeAmount);
        _cumulativeBalance = _cumulativeBalance.sub(activeAmount);
        
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
        }

        require(paths.length == tokens.length, "ERR_PATHS_MISMATCH");

        for (uint i = 0; i < paths.length; i++) {
            require(paths[i][0] == tokens[i], "ERR_PATH_START");
            require(paths[i][paths[i].length - 1] == address(_bdl), "ERR_PATH_END");
        }

        tokens[underlying.length] = bundle;

        _controller.collectTokens(tokens, address(this));

        for (uint i = 0; i < tokens.length; i++) {
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

        _bdl.transfer(msg.sender, totalCollected.mul(15).div(1000));
        _bdl.transfer(_dev, totalCollected.mul(_devShare).div(100000));

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
                ActiveRatio memory activeRatio = _cache[time];
                uint256 activeAmount = user.deposits[i].balance.mul(activeRatio.underlying).div(activeRatio.active);
                user.activeBalance = user.activeBalance.add(_convertToActive(activeAmount));
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
                    underlying: _bdl.balanceOf(address(this)).sub(_getPendingBalance()),
                    active: _cumulativeBalance
                });

                // Convert to active and merge
                uint256 balance = _cumulativeDeposits[i].balance;
                _cumulativeBalance = _cumulativeBalance.add(_convertToActive(balance));
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
    function _convertToActive(uint256 amount) 
        internal view 
        returns(uint256) 
    {
        // Should discount BDL from pending deposits
        return amount.mul(_bdl.balanceOf(address(this)).sub(_getPendingBalance())).div(_cumulativeBalance);
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
}
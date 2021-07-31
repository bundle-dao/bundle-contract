// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IController.sol";

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

    event LogBundlesChanged(
        address indexed caller,
        address[]       bundles
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

    uint256 private constant INIT_DEV_SHARE = 30000;
    uint256 private constant MAX_DEV_SHARE = 50000;
    uint256 private constant DELAY = 7 days;

    IController private _controller;
    IERC20 private _bdl;
    address private _dev;
    uint256 private _cumulativeBalance;
    uint256 private _devShare;

    address[] private _bundles;
    mapping(address=>User) private _users;
    Deposit[] private _cumulativeDeposits;

    /* ========== Initialization ========== */

    constructor(address controller, address bdl, address dev) public {
        // Validate addresses
        require(
            controller != address(0) && bdl != address(0) && dev != address(0),
            "ERR_ZERO_ADDRESS"
        );

        _controller = IController(controller);
        _bdl = IERC20(bdl);
        _dev = dev;
    }

    /* ========== Setters ========== */

    function setBundles(address[] calldata bundles) 
        external 
        onlyOwner
    {
        // Validate updated set
        for (uint256 i = 0; i < bundles.length; i++) {
            (,,bool isSetup,) = _controller.getBundleMetadata(bundles[i]);
            require(isSetup, "ERR_NOT_SET_UP");
        }
        
        _bundles = bundles;
        emit LogBundlesChanged(msg.sender, bundles);
    }

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
        _mergeDeposits(msg.sender);
        _mergeCumulativeDeposits();

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
        _mergeDeposits(msg.sender);
        _mergeCumulativeDeposits();

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

    function collect() external {
        _mergeCumulativeDeposits();

    }

    /* ========== Internal ========== */

    function _mergeDeposits(address userAddress) internal {
        uint256 time = block.timestamp.sub(DELAY);
        User storage user = _users[userAddress];
        uint256 mergeCounter = 0;

        // Merge deposit if older than 7 days
        for (uint256 i = 0; i < user.deposits.length; i++) {
            if (user.deposits[i].time <= time) {
                uint256 balance = user.deposits[i].balance;
                // FIX user.activeBalance = user.activeBalance.add(balance);
                user.deposits[i].balance = 0;
                mergeCounter++;
            }
        }

        for (uint256 i = 0; i < user.deposits.length.sub(mergeCounter); i++) {
            user.deposits[i] = user.deposits[i + mergeCounter];
        }

        for (uint256 i = 0; i < mergeCounter; i++) {
            user.deposits.pop();
        }
    }

    function _mergeCumulativeDeposits() internal {
        uint256 time = block.timestamp.sub(DELAY);
        uint256 mergeCounter = 0;

        // Merge deposit if older than 7 days
        for (uint256 i = 0; i < _cumulativeDeposits.length; i++) {
            if (_cumulativeDeposits[i].time <= time) {
                uint256 balance = _cumulativeDeposits[i].balance;
                // FIX _cumulativeBalance = _cumulativeBalance.add(balance);
                _cumulativeDeposits[i].balance = 0;
                mergeCounter++;
            }
        }

        for (uint256 i = 0; i < _cumulativeDeposits.length.sub(mergeCounter); i++) {
            _cumulativeDeposits[i] = _cumulativeDeposits[i + mergeCounter];
        }

        for (uint256 i = 0; i < mergeCounter; i++) {
            _cumulativeDeposits.pop();
        }
    }

    function _convertToActive(uint256 amount) 
        internal view 
        returns(uint256) 
    {
        // Should discount BDL from pending deposits
        return amount.mul(_bdl.balanceOf(address(this)).sub(_getPendingBalance())).div(_cumulativeBalance);
    }

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
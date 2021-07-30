// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IController.sol";

contract BundleVault is Ownable {
    using SafeMath for uint256;
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

    }

    /* ========== Fee Collection ========== */

    function collect() external {

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
                user.activeBalance = user.activeBalance.add(balance);
                _cumulativeBalance = _cumulativeBalance.add(balance);
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
}
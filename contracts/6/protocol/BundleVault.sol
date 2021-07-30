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

    uint256 private constant INIT_DEV_SHARE = 33333;
    uint256 private constant MAX_DEV_SHARE = 50000;

    IController private _controller;
    address private _dev;
    address private _bdl;
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
        _bdl = bdl;
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
        
    }

    function withdraw(uint256 amount) external {

    }

    /* ========== Fee Collection ========== */

    function collect() external {

    }
}
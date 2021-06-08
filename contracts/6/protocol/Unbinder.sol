// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@bundle-dao/pancakeswap-peripheral/contracts/interfaces/IPancakeRouter02.sol";

import "./interfaces/IUnbinder.sol";

contract Unbinder is IUnbinder, Initializable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Storage
    address private _bundle;
    address private _controller;
    uint256 private _premium;
    IPancakeRouter02 private _router;

    uint256 internal constant BONE         = 10**18;
    uint256 internal constant INIT_PREMIUM = BONE / 10**2;
    uint256 internal constant MAX_PREMIUM  = (5 * BONE) / 10**2;

    // Modifiers
    modifier _control_() {
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        _;
    }

    modifier _bundle_() {
        require(msg.sender == _bundle, "ERR_NOT_BUNDLE");
        _;
    }

    // Initialization
    function initialize(address bundle, address controller, IPancakeRouter02 router)
        public
        initializer
    {
        __ReentrancyGuard_init();
        _bundle = bundle;
        _controller = controller;
        _premium = INIT_PREMIUM;
        _router = router;
    }

    // Controller methods
    function setPremium(uint256 premium)
        external override
        _control_
    {
        require(_premium <= MAX_PREMIUM, "ERR_MAX_PREMIUM");
        _premium = premium;
    }

    function setRouter(IPancakeRouter02 router)
        external override
        _control_
    {
        _router = router;
    }

    // Bundle functions
    function handleUnboundToken(address token)
        external override
        _bundle_
    {
        emit TokenUnbound(token);
    }

    // Getters
    function getBundle()
        external view override
        _bundle_
        returns (address)
    {
        return _bundle;
    }

    function getController()
        external view override
        _bundle_
        returns (address)
    {
        return _controller;
    }

    function getPremium()
        external view override
        _bundle_
        returns (uint256)
    {
        return _premium;
    }

    // Public handler function
    function distributeUnboundToken(address token, uint256 amount)
        external override
        nonReentrant
    {
        
    }
}
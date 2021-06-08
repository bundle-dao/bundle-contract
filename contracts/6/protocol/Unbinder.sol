// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "./interfaces/IUnbinder.sol";

contract Unbinder is IUnbinder, Initializable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Storage
    address public bundle;
    address public controller;
    uint256 public premium;

    uint256 internal constant BONE         = 10**18;
    uint256 internal constant INIT_PREMIUM = BONE / 10**2;
    uint256 internal constant MAX_PREMIUM  = (5 * BONE) / 10**2;

    // Modifiers
    modifier _control_() {
        require(msg.sender == controller, "ERR_NOT_CONTROLLER");
        _;
    }

    modifier _bundle_() {
        require(msg.sender == bundle, "ERR_NOT_BUNDLE");
        _;
    }

    // Initialization
    function initialize(address _bundle, address _controller)
        public
        initializer
    {
        __ReentrancyGuard_init();
        bundle = _bundle;
        controller = _controller;
        premium = INIT_PREMIUM;
    }

    // Controller methods
    function setPremium(uint256 _premium)
        external override
        _control_
    {
        require(_premium <= MAX_PREMIUM, "ERR_MAX_PREMIUM");
        premium = _premium;
    }

    // Bundle functions
    function handleUnboundToken(address token)
        external override
        _bundle_
    {
        emit TokenUnbound(token);
    }

    // Public handler function
    function distributeUnboundToken(address token, uint256 amount)
        external override
        nonReentrant
    {

    }
}
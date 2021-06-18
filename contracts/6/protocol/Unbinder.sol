// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@bundle-dao/pancakeswap-peripheral/contracts/interfaces/IPancakeRouter02.sol";

import "./interfaces/IUnbinder.sol";
import "./interfaces/IBundle.sol";

contract Unbinder is IUnbinder, Initializable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    /* ========== Constants ========== */

    uint256 internal constant BONE         = 10**18;
    uint256 internal constant INIT_PREMIUM = BONE / 10**2;
    uint256 internal constant MAX_PREMIUM  = (5 * BONE) / 10**2;

    /* ========== Storage ========== */

    address private _controller;
    uint256 private _premium;
    IBundle private _bundle;
    IPancakeRouter02 private _router;

    mapping(address=>bool) private _whitelist;

    /* ========== Modifiers ========== */

    modifier _control_() {
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        _;
    }

    modifier _bundle_() {
        require(msg.sender == address(_bundle), "ERR_NOT_BUNDLE");
        _;
    }

    modifier _eoa_() {
        require(msg.sender == tx.origin, "ERR_NOT_EOA");
        _;
    }

    /* ========== Initialization ========== */
    
    function initialize(address bundle, address router, address controller)
        public override
        initializer
    {
        __ReentrancyGuard_init();
        _bundle = IBundle(bundle);
        _router = IPancakeRouter02(router);
        _controller = controller;
        _premium = INIT_PREMIUM;
    }

    /* ========== Control ========== */

    function setPremium(uint256 premium)
        external override
        _control_
    {
        require(_premium <= MAX_PREMIUM, "ERR_MAX_PREMIUM");
        _premium = premium;
    }

    function setRouteToken(address token, bool flag)
        external override
        _control_
    {
        _whitelist[token] = flag;
    }

    /* ========== Bundle Interaction ========== */
    
    function handleUnboundToken(address token)
        external override
        _bundle_
    {
        emit TokenUnbound(token);
    }

    /* ========== Getters ========== */

    function getBundle()
        external view override
        returns (address)
    {
        return address(_bundle);
    }

    function getController()
        external view override
        returns (address)
    {
        return _controller;
    }

    function getPremium()
        external view override
        returns (uint256)
    {
        return _premium;
    }

    function isWhitelisted(address token)
        external view override
        returns (bool)
    {
        return _whitelist[token];
    }

    /** @dev This function and contract are intended to allow constrained
     *  swaps from an unbound token back to bound tokens. Ensures that erroneously
     *  sent tokens / small amounts of unbound tokens are redistributed back to 
     *  index holders. This could be improved by using TWAP and a price oracle, 
     *  but ultimately not important enough to prioritize at the time being.
     *
     *  Experimental, and may require future upgrades to resolve certain blocking
     *  edge cases.
     *
     *  @param token Address of token to distribute back to Bundle
     *  @param amount Amount of token to redistribute
     */
    function distributeUnboundToken(address token, uint256 amount, uint256 deadline, address[] calldata routeTokens)
        external override
        nonReentrant
        _eoa_
    {
        require(IERC20Upgradeable(token).balanceOf(address(this)) >= amount, "ERR_BAD_AMOUNT");

        if (IERC20Upgradeable(token).allowance(address(this), address(_router)) != type(uint256).max) {
            IERC20Upgradeable(token).approve(address(_router), type(uint256).max);
        }

        address[] memory tokens = _bundle.getCurrentTokens();
        require(routeTokens.length == tokens.length, "ERR_ROUTE_MISMATCH");

        uint256[] memory weights = new uint256[](tokens.length);
        uint256 totalWeight = 0;

        // Reward the caller with a portion of unbound tokens
        uint256 balance = amount.sub(amount.mul(_premium).div(BONE));
        IERC20Upgradeable(token).transfer(msg.sender, amount.mul(_premium).div(BONE));

        // Assumes we can swap to tokens within the bundle
        for (uint256 i = 0; i < tokens.length; i++) {
            weights[i] = _bundle.getDenormalizedWeight(tokens[i]);
            totalWeight = totalWeight.add(weights[i]);
        }

        for (uint256 i = 0; i < tokens.length - 1; i++) {
            // Ensure we don't swap on arbitrary pairs
            require(_whitelist[routeTokens[i]], "ERR_ROUTE_NOT_WHITELISTED");

            address[] memory path = new address[](3);

            // Enforce reliably secure path set on initialization
            path[0] = token;
            path[1] = routeTokens[i];
            path[2] = tokens[i];

            uint256[] memory expectedOut = _router.getAmountsOut(balance.mul(weights[i]).div(totalWeight), path);

            require(expectedOut[path.length - 1] > 0, "ERR_BAD_SWAP");
            
            // Min amount out to be 97% of expectation
            // unbinder used infrequently enough s.t. these don't need to be too strict
            _router.swapExactTokensForTokens(
                balance.mul(weights[i]).div(totalWeight), 
                expectedOut[path.length - 1].mul(970).div(1000), 
                path, 
                address(_bundle), 
                deadline
            );

            // Add bToken back to balances
            _bundle.gulp(tokens[i]);
        }
    }
}

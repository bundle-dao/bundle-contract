// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

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

    mapping(address=>SwapToken) private _swapWhitelist;
    address[] private _swapTokens;

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
    
    function initialize(address bundle, address router, address controller, address[] calldata whitelist)
        public override
        initializer
    {
        __ReentrancyGuard_init();
        _bundle = IBundle(bundle);
        _router = IPancakeRouter02(router);
        _controller = controller;
        _premium = INIT_PREMIUM;

        uint256 index = 0;
        for(uint256 i = 0; i < whitelist.length; i++) {
            if (!_swapWhitelist[whitelist[i]].flag) {
                _swapWhitelist[whitelist[i]] = SwapToken({
                    flag: true,
                    index: index
                });
                _swapTokens.push(whitelist[i]);
                index++;
            }
        }
    }

    /* ========== Control ========== */

    function setPremium(uint256 premium)
        external override
        _control_
    {
        require(_premium <= MAX_PREMIUM, "ERR_MAX_PREMIUM");
        _premium = premium;
        emit LogPremium(msg.sender, premium);
    }

    function setSwapWhitelist(address token, bool flag)
        external override
        _control_
    {
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

    function isSwapWhitelisted(address token)
        external view override
        returns (bool)
    {
        return _swapWhitelist[token].flag;
    }

    function getSwapWhitelist()
        external view override
        returns (address[] memory)
    {
        return _swapTokens;
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
    function distributeUnboundToken(address token, uint256 amount, uint256 deadline, address[][] calldata paths)
        external override
        nonReentrant
        _eoa_
    {
        if (IERC20Upgradeable(token).allowance(address(this), address(_router)) != type(uint256).max) {
            IERC20Upgradeable(token).approve(address(_router), type(uint256).max);
        }

        address[] memory tokens = _bundle.getCurrentTokens();
        require(paths.length == tokens.length, "ERR_TOKENS_MISMATCH");

        for (uint256 i = 0; i < paths.length; i++) {
            require(paths[i][0] == token, "ERR_PATH_START");
            require(paths[i][paths[i].length - 1] == tokens[i], "ERR_PATH_END");
        }

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

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256[] memory amountsOut = _router.getAmountsOut(balance.mul(weights[i]).div(totalWeight), paths[i]);

            _handlePath(
                paths[i], 
                balance.mul(weights[i]).div(totalWeight), 
                amountsOut[amountsOut.length - 1], 
                deadline
            );
        }
    }

    function _handlePath(address[] calldata path, uint256 amountIn, uint256 amountOut, uint256 deadline) 
        internal
    {
            require(amountOut > 0, "ERR_BAD_SWAP");

            for (uint256 i = 1; i < path.length - 1; i++) {
                require(_swapWhitelist[path[i]].flag, "ERR_BAD_PATH");
            }
            
            // Min amount out to be 99% of expectation
            // unbinder used infrequently enough s.t. these don't need to be too strict
            _router.swapExactTokensForTokens(
                amountIn, 
                amountOut.mul(9900).div(10000), 
                path,
                address(_bundle),
                deadline
            );

            // Add bToken back to balances
            _bundle.gulp(path[path.length - 1]);
    }
}

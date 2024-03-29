// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@bundle-dao/pancakeswap-peripheral/contracts/interfaces/IPancakeRouter02.sol";

import "./interfaces/IUnbinder.sol";
import "./interfaces/IBundle.sol";
import "./interfaces/IRebalancer.sol";
import "./interfaces/IBundleLock.sol";
import "./interfaces/IPriceOracle.sol";

contract Rebalancer is Initializable, ReentrancyGuardUpgradeable, IRebalancer {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    /* ========== Constants ========== */

    uint256 internal constant BONE         = 10**18;
    uint256 internal constant INIT_PREMIUM = (3 * BONE) / 10**2;
    uint256 internal constant MAX_PREMIUM  = (25 * BONE) / 10**2;
    uint256 internal constant INIT_ORACLE_GAP = (5 * BONE) / 10**2;

    /* ========== Storage ========== */
    
    address private _controller;
    uint256 private _premium;
    uint256 private _gap;
    IPancakeRouter02 private _router;
    IPriceOracle private _oracle;

    mapping(address=>bool) private _poolAuth;
    mapping(address=>SwapToken) private _swapWhitelist;
    address[] private _swapTokens;

    /* ========== Modifiers ========== */
    
    modifier _control_() {
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        _;
    }

    modifier _eoa_() {
        require(msg.sender == tx.origin, "ERR_NOT_EOA");
        _;
    }

    /* ========== Initialization ========== */
    
    function initialize(address router, address controller)
        public
        initializer
    {
        __ReentrancyGuard_init();
        _controller = controller;
        _router = IPancakeRouter02(router);
        _premium = INIT_PREMIUM;
        _gap = INIT_ORACLE_GAP;
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

    function setWhitelist(address pool, bool flag)
        external override
        _control_
    {
        _poolAuth[pool] = flag;
        emit LogWhitelist(msg.sender, pool, flag);
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

    function setOracle(address oracle)
        external override
        _control_
    {
        _oracle = IPriceOracle(oracle);
        emit LogOracle(msg.sender, oracle);
    }

    function setGap(uint256 gap)
        external override
        _control_
    {
        _gap = gap;
        emit LogGap(msg.sender, gap);
    }

    /* ========== Getters ========== */

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

    function getOracle()
        external view override
        returns (address)
    {
        return address(_oracle);
    }

    function getGap()
        external view override
        returns (uint256)
    {
        return _gap;
    }

    function isWhitelisted(address pool)
        external view override
        returns (bool)
    {
        return _poolAuth[pool];
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

    /** @dev This function allows the user to execute controlled arbitrage trades against a 
     *  whitelisted Bundle. This works by ensuring the provided funds are returned, with any 
     *  profits being split between the caller and pool.
     * 
     *  @param pool Pool to execute the swap against
     *  @param tokenIn Input token
     *  @param tokenOut Output token
     *  @param amountIn Input amount
     *  @param deadline Deadline for which the swap must complete
     *  @param path Path of the returning swap, tokenOut -> tokenIn
     */
    function swap(
        address pool,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 deadline,
        address[] calldata path
    )
        external override
        nonReentrant
        _eoa_
    {
        // Bundle validation
        require(_poolAuth[pool], "ERR_POOL_WHITELIST");
        require(IBundle(pool).isBound(tokenIn), "ERR_IN_NOT_BOUND");
        require(IBundle(pool).isBound(tokenOut), "ERR_OUT_NOT_BOUND");
        require(IBundle(pool).getRebalancable(), "ERR_NOT_REBALANCABLE");

        // Path validation
        require(path[0] == tokenOut, "ERR_BAD_PATH");
        require(path[path.length - 1] == tokenIn, "ERR_BAD_PATH");

        for (uint256 i = 1; i < path.length - 1; i++) {
            require(_swapWhitelist[path[i]].flag, "ERR_BAD_PATH");
        }

        // Approve tokenOut for router if not done already
        if (IERC20Upgradeable(tokenOut).allowance(address(this), address(_router)) != type(uint256).max) {
            IERC20Upgradeable(tokenOut).approve(address(_router), type(uint256).max);
        }

        // Approve token for pool if not done already
        if (IERC20Upgradeable(tokenIn).allowance(address(this), address(pool)) != type(uint256).max) {
            IERC20Upgradeable(tokenIn).approve(address(pool), type(uint256).max);
        }

        // Swap on Bundle w/ absolute min out and max price
        IERC20Upgradeable(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        (uint256 tokenAmountOut, ) = IBundle(pool).swapExactAmountIn(tokenIn, amountIn, tokenOut, 0, type(uint256).max);

        // Swap tokenOut tokenIn on separate DEX
        uint256[] memory amountsTokenOut = _router.swapExactTokensForTokens(tokenAmountOut, amountIn, path, address(this), deadline);

        // Update oracle and check reference prices
        if (_gap > 0) {
            _oracle.updateReference(tokenIn);
            _oracle.updateReference(tokenOut);
            uint256 inToPeg = _oracle.consultReference(tokenIn, amountsTokenOut[path.length - 1]);
            uint256 outToPeg = _oracle.consultReference(tokenOut, tokenAmountOut);
            uint256 diff;

            require(inToPeg > 0 && outToPeg > 0, "ERR_REFERENCE_NOT_INITIALIZED");

            if (inToPeg > outToPeg) {
                diff = inToPeg.sub(outToPeg);
            } else {
                diff = outToPeg.sub(inToPeg);
            }

            // Ensure differences in prices to not exceed set range
            require(inToPeg.mul(_gap).div(BONE) >= diff, "ERR_SWAP_OUT_OF_GAP");
        }

        // Send funds back to user
        uint256 userFee = amountsTokenOut[path.length - 1].sub(amountIn).mul(_premium).div(BONE);
        uint256 poolAmount = amountsTokenOut[path.length - 1].sub(amountIn).sub(userFee);
        IERC20Upgradeable(tokenIn).safeTransfer(msg.sender, amountIn.add(userFee));

        // Send funds back to pool and re-process
        IERC20Upgradeable(tokenIn).safeTransfer(pool, poolAmount);
        IBundle(pool).gulp(tokenIn);
    }
}

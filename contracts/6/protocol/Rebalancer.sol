// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@bundle-dao/pancakeswap-peripheral/contracts/interfaces/IPancakeRouter02.sol";

import "./interfaces/IUnbinder.sol";
import "./interfaces/IBundle.sol";

contract Rebalancer is Initializable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    /* ========== Constants ========== */

    uint256 internal constant BONE         = 10**18;
    uint256 internal constant INIT_PREMIUM = (2 * BONE) / 10**2;
    uint256 internal constant MAX_PREMIUM  = (25 * BONE) / 10**2;

    /* ========== Storage ========== */
    
    address private _controller;
    address private _bundleToken;
    uint256 private _premium;
    IPancakeRouter02 private _router;

    mapping(address=>bool) private _poolAuth;

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
    
    function initialize(IPancakeRouter02 router, address controller, address bundleToken)
        public
        initializer
    {
        __ReentrancyGuard_init();
        _controller = controller;
        _bundleToken = bundleToken;
        _router = router;
        _premium = INIT_PREMIUM;
    }

    /* ========== Control ========== */

    function setPremium(uint256 premium)
        external
        _control_
    {
        require(_premium <= MAX_PREMIUM, "ERR_MAX_PREMIUM");
        _premium = premium;
    }

    function setWhitelist(address pool, bool flag)
        external
        _control_
    {
        _poolAuth[pool] = flag;
    }

    /* ========== Getters ========== */

    function getController()
        external view
        returns (address)
    {
        return _controller;
    }

    function getPremium()
        external view
        returns (uint256)
    {
        return _premium;
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
        external
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

        // Send funds back to user
        uint256 userFee = amountsTokenOut[path.length - 1].sub(amountIn).mul(_premium).div(BONE);
        uint256 poolAmount = amountsTokenOut[path.length - 1].sub(amountIn).sub(userFee);
        IERC20Upgradeable(tokenIn).safeTransfer(msg.sender, amountIn.add(userFee));

        // Send funds back to pool and re-process
        IERC20Upgradeable(tokenIn).safeTransfer(pool, poolAmount);
        IBundle(pool).gulp(tokenIn);
    }
}
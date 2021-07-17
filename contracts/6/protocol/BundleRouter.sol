// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@bundle-dao/pancakeswap-peripheral/contracts/interfaces/IPancakeRouter02.sol";

import "./interfaces/IUnbinder.sol";
import "./interfaces/IBundle.sol";
import "./interfaces/IPriceOracle.sol";
import "./core/BNum.sol";

contract BundleRouter is ReentrancyGuard, BNum, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /* ========== Storage ========== */

    IPancakeRouter02 private _router;

    mapping(address => bool) private _whitelist;

    /* ========== Initialization ========== */
    
    constructor(address router)
        public
    {
        _router = IPancakeRouter02(router);
    }

    /* ========== Getters ========== */

    function getRouter()
        external view
        returns (address)
    {
        return address(_router);
    }

    function isWhitelisted(address bundle)
        external view
        returns (bool)
    {
        return _whitelist[bundle];
    }

    function setWhitelist(address bundle, bool flag)
        external
        onlyOwner
    {
        _whitelist[bundle] = flag;
    }

    function mint(address bundle, address token, uint256 amountIn, uint256 minAmountOut, uint256 deadline, address[][] calldata paths)
        external
        nonReentrant
    {
        // Ensure Bundle is whitelisted
        require(_whitelist[bundle], "ERR_NOT_WHITELISTED");

        // Approve token in for router
        if (IERC20(token).allowance(address(this), address(_router)) != type(uint256).max) {
            IERC20(token).approve(address(_router), type(uint256).max);
        }

        // Load tokens, check path length matches tokens
        address[] memory tokens = IBundle(bundle).getCurrentTokens();
        require(paths.length == tokens.length, "ERR_TOKENS_MISMATCH");

        // Initialize memory for weights and amounts in
        uint256[] memory amounts = new uint256[](tokens.length);
        uint256 totalWeight = 0;

        // Validate paths, approve tokens for bundle, set weights / total weight
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] != token) {
                require(paths[i][0] == token, "ERR_PATH_START");
                require(paths[i][paths[i].length - 1] == tokens[i], "ERR_PATH_END");
            }

            if (IERC20(tokens[i]).allowance(address(this), address(bundle)) != type(uint256).max) {
                IERC20(tokens[i]).approve(address(bundle), type(uint256).max);
            }

            uint256 weight = IBundle(bundle).getDenormalizedWeight(tokens[i]);
            amounts[i] = weight.mul(amountIn);
            totalWeight = totalWeight.add(weight);
        }

        // Transfer token to the contract for swap
        IERC20(token).transferFrom(msg.sender, address(this), amountIn);

        // Execute swaps and store output amounts
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] != token) {
                _handlePath(
                    paths[i], 
                    amounts[i].div(totalWeight), 
                    _router.getAmountsOut(amounts[i].div(totalWeight), paths[i])[paths[i].length - 1], 
                    deadline
                );

                amounts[i] = IERC20(tokens[i]).balanceOf(address(this));
            }
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                amounts[i] = IERC20(tokens[i]).balanceOf(address(this));
            }
        }

        // Compute the max amount out given balances
        uint256 amountOut = _computeAmountOut(bundle, amounts, tokens);
        IBundle(bundle).joinPool(amountOut, amounts);
        IERC20(bundle).transfer(msg.sender, IERC20(bundle).balanceOf(address(this)));

        // Swap and transfer dust amounts back to caller
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));

            if (balance > 0 && token != tokens[i]) {
                _handleDustPath(
                    paths[i], 
                    balance, 
                    deadline
                );
            }
        }

        // Require in to min out ratio is preserved
        require(
            amountOut > minAmountOut.sub(
                minAmountOut.mul(IERC20(token).balanceOf(address(this))).div(amountIn)
            ), 
            "ERR_MIN_AMOUNT_OUT"
        );

        IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
    }

    function redeem(address bundle, address token, uint256 amountIn, uint256 minAmountOut, uint256 deadline, address[][] calldata paths)
        external
        nonReentrant
    {
        // Ensure Bundle is whitelisted
        require(_whitelist[bundle], "ERR_NOT_WHITELISTED");

        // Load tokens, check path length matches tokens
        address[] memory tokens = IBundle(bundle).getCurrentTokens();
        require(paths.length == tokens.length, "ERR_TOKENS_MISMATCH");

        // Approve tokens for swaps, validate paths
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] != token) {
                require(paths[i][0] == tokens[i], "ERR_PATH_START");
                require(paths[i][paths[i].length - 1] == token, "ERR_PATH_END");
            }

            if (IERC20(tokens[i]).allowance(address(this), address(_router)) != type(uint256).max) {
                IERC20(tokens[i]).approve(address(_router), type(uint256).max);
            }
        }

        // Transfer bundle to router
        IERC20(bundle).transferFrom(msg.sender, address(this), amountIn);

        // Exit the pool, default to 0 min amounts as we check against the peg later
        IBundle(bundle).exitPool(amountIn, new uint256[](tokens.length));

        // Execute swaps
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] != token) {
                uint256 balance = IERC20(tokens[i]).balanceOf(address(this));

                if (balance > 0) {
                    uint256[] memory amountsOut = _router.getAmountsOut(balance, paths[i]);

                    _handlePath(
                        paths[i], 
                        balance, 
                        amountsOut[amountsOut.length - 1], 
                        deadline
                    );
                }
            }
        }

        // Assert min amount out and return token to caller
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(balance > minAmountOut, "ERR_MIN_AMOUNT_OUT");
        IERC20(token).transfer(msg.sender, balance);
    }

    function _computeAmountOut(address bundle, uint256[] memory amounts, address[] memory tokens)
        internal view
        returns(uint256 amountOut)
    {
        amountOut = type(uint256).max;
        uint256 poolTotal = IERC20(bundle).totalSupply();
        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 balance = IBundle(bundle).getBalance(tokens[i]);
            // Account for negligible rounding errors
            amountOut = bmin(amountOut, bmul(poolTotal, bdiv(amounts[i], balance)).mul(1e12).div(1e12 + 1));
        }
    }

    function _handlePath(address[] calldata path, uint256 amountIn, uint256 amountOut, uint256 deadline) 
        internal
    {
            require(amountOut > 0, "ERR_BAD_SWAP");
            
            // Min amount out to be 99% of expectation
            _router.swapExactTokensForTokens(
                amountIn, 
                amountOut.mul(9900).div(10000), 
                path,
                address(this),
                deadline
            );
    }

    function _handleDustPath(address[] calldata path, uint256 amountIn, uint256 deadline) 
        internal
    {
            address[] memory reversePath = new address[](path.length);

            for (uint256 i = 0; i < path.length; i++) {
                reversePath[i] = path[path.length - i - 1];
            }

            if (IERC20(reversePath[0]).allowance(address(this), address(_router)) != type(uint256).max) {
                IERC20(reversePath[0]).approve(address(_router), type(uint256).max);
            }
            
            _router.swapExactTokensForTokens(
                amountIn,
                0,
                reversePath,
                address(this),
                deadline
            );
    }
}
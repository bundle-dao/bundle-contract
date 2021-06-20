// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./IUnbinder.sol";

interface IBundle {
    struct Record {
        bool bound;               // is token bound to pool
        bool ready;               // is token ready for swaps
        uint256 denorm;           // denormalized weight
        uint256 targetDenorm;     // target denormalized weight
        uint256 targetTime;      // target block to update by
        uint256 lastUpdateTime;  // last update block
        uint8 index;              // token index
        uint256 balance;          // token balance
    }

    /* ========== Events ========== */

    event LogSwap(
        address indexed caller,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256         tokenAmountIn,
        uint256         tokenAmountOut
    );

    event LogJoin(
        address indexed caller,
        address indexed tokenIn,
        uint256         tokenAmountIn
    );

    event LogExit(
        address indexed caller,
        address indexed tokenOut,
        uint256         tokenAmountOut
    );

    event LogSwapFeeUpdated(
        address indexed caller,
        uint256         swapFee
    );

    event LogTokenReady(
        address indexed token
    );

    event LogPublicSwapEnabled();

    event LogCall(
        bytes4  indexed sig,
        address indexed caller,
        bytes           data
    ) anonymous;

    /* ========== Initialization ========== */

    function initialize(
        address controller, 
        address rebalancer,
        address unbinder,
        string calldata name, 
        string calldata symbol
    ) external;

    function setup(
        address[] calldata tokens,
        uint256[] calldata balances,
        uint256[] calldata denorms,
        address tokenProvider
    ) external;

    function setSwapFee(uint256 swapFee) external;

    function setRebalancable(bool rebalancable) external;

    function setPublicSwap(bool public_) external;

    function setMinBalance(address token, uint256 minBalance) external;

    function setStreamingFee(uint256 streamingFee) external;

    function setExitFee(uint256 exitFee) external;

    function setTargetDelta(uint256 targetDelta) external;

    function collectStreamingFee() external;

    function isPublicSwap() external view returns (bool);

    function isBound(address t) external view returns (bool);

    function isReady(address t) external view returns (bool);

    function getNumTokens() external view returns (uint256) ;

    function getCurrentTokens() external view returns (address[] memory tokens);

    function getDenormalizedWeight(address token) external view returns (uint256);

    function getTotalDenormalizedWeight() external view returns (uint256);

    function getBalance(address token) external view returns (uint256);

    function getSwapFee() external view returns (uint256);

    function getStreamingFee() external view returns (uint256);

    function getExitFee() external view returns (uint256);

    function getLastStreamingTime() external view returns (uint256);

    function getController() external view returns (address);

    function getRebalancer() external view returns (address);

    function getRebalancable() external view returns (bool);

    function getUnbinder() external view returns (address);

    function getSpotPrice(
        address tokenIn, 
        address tokenOut
    ) external view returns (uint256 spotPrice);

    function getSpotPriceSansFee(
        address tokenIn, 
        address tokenOut
    ) external view returns (uint256 spotPrice);

    /* ==========  External Token Weighting  ========== */

    /**
     * @dev Adjust weights for existing tokens
     * @param tokens A set of token addresses to adjust
     * @param targetDenorms A set of denorms to linearly update to
     */

    function reweighTokens(
        address[] calldata tokens,
        uint256[] calldata targetDenorms
    ) external;

    /**
     * @dev Reindex the pool on a new set of tokens
     *
     * @param tokens A set of token addresses to be indexed
     * @param targetDenorms A set of denorms to linearly update to
     * @param minBalances Minimum balance thresholds for unbound assets
     */
    function reindexTokens(
        address[] calldata tokens,
        uint256[] calldata targetDenorms,
        uint256[] calldata minBalances
    ) external;

    function gulp(address token) external;

    function joinPool(uint256 poolAmountOut, uint[] calldata maxAmountsIn) external;

    function exitPool(uint256 poolAmountIn, uint[] calldata minAmountsOut) external;

    function swapExactAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    ) external returns (uint256 tokenAmountOut, uint256 spotPriceAfter);

    function swapExactAmountOut(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPrice
    ) external returns (uint256 tokenAmountIn, uint256 spotPriceAfter);
}

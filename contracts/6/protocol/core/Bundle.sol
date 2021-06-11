// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./BToken.sol";
import "./BMath.sol";

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "../interfaces/IUnbinder.sol";
import "../interfaces/IBundle.sol";

/************************************************************************************************
Originally forked from https://github.com/balancer-labs/balancer-core/

This source code has been modified from the original, which was copied from the github repository
at commit hash f4ed5d65362a8d6cec21662fb6eae233b0babc1f.

Subject to the GPL-3.0 license
*************************************************************************************************/

contract Bundle is Initializable, BToken, BMath, IBundle {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== Modifiers ========== */

    modifier _logs_() {
        emit LogCall(msg.sig, msg.sender, msg.data);
        _;
    }

    modifier _lock_() {
        require(!_mutex, "ERR_REENTRY");
        _mutex = true;
        _;
        _mutex = false;
    }

    modifier _viewlock_() {
        require(!_mutex, "ERR_REENTRY");
        _;
    }

    modifier _public_() {
        require(_publicSwap, "ERR_NOT_PUBLIC");
        _;
    }

    modifier _control_() {
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        _;
    }

    modifier _rebalance_() {
        require(msg.sender == _rebalancer, "ERR_NOT_REBALANCER");
        require(_rebalancable, "ERR_NOT_REBALANCEABLE");
        _;
    }

    /* ========== Storage ========== */

    bool private _mutex;

    // Can use functions behind the _control_ modifier
    address private _controller;
    
    // Can rebalance the pool
    address private _rebalancer;

    // true if PUBLIC can call SWAP functions
    bool private _publicSwap;

    // swap fee
    uint256 private _swapFee;

    // exit fee
    uint256 private _exitFee;

    // Flag preventing multiple setup calls
    bool private _setup;

    // Array of token addresses
    address[] private _tokens;

    // Records for each token
    mapping(address=>Record) private  _records;

    // Mapping of minimum balances for tokens added to the pool 
    mapping(address=>uint256) private _minBalances;

    // Sum of token denorms
    uint256 private _totalWeight;

    // Streaming fee
    uint256 private _streamingFee;

    // Start block for streaming fee
    uint256 private _lastStreamingBlock;

    // Is rebalancable
    bool private _rebalancable;

    // Contract that handles unbound tokens
    IUnbinder private _unbinder;

    /* ========== Initialization ========== */

    /**
     * @dev Initializer function for upgradeability
     * TODO: Set unbound handler on initialization
     */
    function initialize(
        address controller, 
        address rebalancer,
        address unbinder,
        string calldata name, 
        string calldata symbol
    )
        public override
        initializer
    {
        _initializeToken(name, symbol);
        _controller = controller;
        _rebalancer = rebalancer;
        _unbinder = IUnbinder(unbinder);
        _swapFee = INIT_FEE;
        _streamingFee = INIT_STREAMING_FEE;
        _exitFee = INIT_EXIT_FEE;
        _publicSwap = false;
    }

    /** @dev Setup function to initialize the pool after contract creation */
    function setup(
        address[] calldata tokens,
        uint256[] calldata balances,
        uint256[] calldata denorms,
        address tokenProvider
    )
        external override
        _logs_
        _lock_
        _control_
    {
        require(!_setup && _tokens.length == 0, "ERR_BUNDLE_ALREADY_SETUP");
        require(tokens.length >= MIN_BOUND_TOKENS, "ERR_MIN_TOKENS");
        require(tokens.length <= MAX_BOUND_TOKENS, "ERR_MAX_TOKENS");
        require(balances.length == tokens.length && denorms.length == tokens.length, "ERR_ARR_LEN");

        uint256 totalWeight = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 denorm = denorms[i];
            uint256 balance = balances[i];

            require(denorm >= MIN_WEIGHT, "ERR_MIN_WEIGHT");
            require(denorm <= MAX_WEIGHT, "ERR_MAX_WEIGHT");
            require(balance >= MIN_BALANCE, "ERR_MIN_BALANCE");

            address token = tokens[i];
            _records[token] = Record({
                bound: true,
                ready: true,
                denorm: denorm,
                targetDenorm: denorm,
                targetBlock: 0,
                lastUpdateBlock: 0,
                index: uint8(i),
                balance: balance
            });

            _tokens.push(token);
            totalWeight = badd(totalWeight, denorm);
            // Move underlying asset to pool
            _pullUnderlying(token, tokenProvider, balance);
        }

        require(totalWeight <= MAX_TOTAL_WEIGHT, "ERR_MAX_TOTAL_WEIGHT");
        _totalWeight = totalWeight;
        _publicSwap = true;
        _lastStreamingBlock = block.number;
        _rebalancable = true;
        _setup = true;
        emit LogPublicSwapEnabled();
        _mintPoolShare(INIT_POOL_SUPPLY);
        _pushPoolShare(tokenProvider, INIT_POOL_SUPPLY);
    }

    /* ==========  Control  ========== */

    function setSwapFee(uint256 swapFee)
        external override
        _lock_
        _control_
    { 
        require(swapFee >= MIN_FEE, "ERR_MIN_FEE");
        require(swapFee <= MAX_FEE, "ERR_MAX_FEE");
        _swapFee = swapFee;
        emit LogSwapFeeUpdated(msg.sender, swapFee);
    }

    function setRebalancable(bool rebalancable)
        external override
        _logs_
        _lock_
        _control_
    {
        _rebalancable = rebalancable;
    }

    function setPublicSwap(bool public_)
        external override
        _logs_
        _lock_
        _control_
    {
        _publicSwap = public_;
    }

    function setMinBalance(address token, uint256 minBalance) 
        external override
        _logs_
        _lock_
        _control_
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        require(!_records[token].ready, "ERR_READY");
        _minBalances[token] = minBalance;
    }

    function setStreamingFee(uint256 streamingFee) 
        external override
        _logs_
        _lock_
        _control_
    {
        require(streamingFee < MAX_STREAMING_FEE, "ERR_MAX_STREAMING_FEE");
        _streamingFee = streamingFee;
    }

    function setExitFee(uint256 exitFee) 
        external override
        _logs_
        _lock_
        _control_
    {
        require(exitFee < MAX_EXIT_FEE, "ERR_MAX_STREAMING_FEE");
        _exitFee = exitFee;
    }

    function collectStreamingFee()
        external override
        _logs_
        _lock_
        _control_
    {
        require(_setup, "ERR_SETUP");
        require(_lastStreamingBlock < block.number, "ERR_COLLECTION_TO_SOON");

        uint256 blockDelta = bsub(block.number, _lastStreamingBlock);

        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];

            // Shouldnt withdraw tokens if not ready
            if (_records[token].ready) {
                uint256 fee = bdiv(
                    bmul(bmul(_records[token].balance, _streamingFee), blockDelta),
                    BPY
                );

                _pushUnderlying(token, _controller, fee);
                _updateToken(token, bsub(_records[token].balance, fee));
            }
        }

        _lastStreamingBlock = block.number;
    }

    /* ==========  Getters  ========== */

    function isPublicSwap()
        external view override
        returns (bool)
    {
        return _publicSwap;
    }

    function isBound(address t)
        external view override
        returns (bool)
    {
        return _records[t].bound;
    }

    function getNumTokens()
        external view override
        returns (uint256) 
    {
        return _tokens.length;
    }

    function getCurrentTokens()
        external view override 
        _viewlock_
        returns (address[] memory tokens)
    {
        return _tokens;
    }

    function getDenormalizedWeight(address token)
        external view override
        _viewlock_
        returns (uint256)
    {

        require(_records[token].bound, "ERR_NOT_BOUND");
        return _records[token].denorm;
    }

    function getTotalDenormalizedWeight()
        external view override
        _viewlock_
        returns (uint256)
    {
        return _totalWeight;
    }

    function getBalance(address token)
        external view override
        _viewlock_
        returns (uint256)
    {

        require(_records[token].bound, "ERR_NOT_BOUND");
        return _records[token].balance;
    }

    function getSwapFee()
        external view override
        _viewlock_
        returns (uint256)
    {
        return _swapFee;
    }

    function getStreamingFee()
        external view override
        _viewlock_
        returns (uint256)
    {
        return _streamingFee;
    }

    function getExitFee()
        external view override
        _viewlock_
        returns (uint256)
    {
        return _exitFee;
    }

    function getLastStreamingBlock()
        external view override
        _viewlock_
        returns (uint256)
    {
        return _lastStreamingBlock;
    }

    function getController()
        external view override
        _viewlock_
        returns (address)
    {
        return _controller;
    }

    function getRebalancer()
        external view override
        _viewlock_
        returns (address)
    {
        return _rebalancer;
    }

    function getRebalancable()
        external view override
        _viewlock_
        returns (bool)
    {
        return _rebalancable;
    }

    function getUnbinder()
        external view override
        _viewlock_
        returns (address)
    {
        return address(_unbinder);
    }

    function getSpotPrice(address tokenIn, address tokenOut)
        external view override
        _viewlock_
        returns (uint256 spotPrice)
    {
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        Record storage inRecord = _records[tokenIn];
        Record storage outRecord = _records[tokenOut];
        return calcSpotPrice(inRecord.balance, inRecord.denorm, outRecord.balance, outRecord.denorm, _swapFee);
    }

    function getSpotPriceSansFee(address tokenIn, address tokenOut)
        external view override
        _viewlock_
        returns (uint256 spotPrice)
    {
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        Record storage inRecord = _records[tokenIn];
        Record storage outRecord = _records[tokenOut];
        return calcSpotPrice(inRecord.balance, inRecord.denorm, outRecord.balance, outRecord.denorm, 0);
    }

    /* ==========  External Token Weighting  ========== */

    /**
     * @dev Adjust weights for existing tokens
     * @param tokens A set of token addresses to adjust
     * @param targetDenorms A set of denorms to linearly update to
     */

    function reweighTokens(
        address[] calldata tokens,
        uint256[] calldata targetDenorms
    )
        external override
        _lock_
        _control_
    {
        require(targetDenorms.length == tokens.length, "ERR_ARR_LEN");
        for (uint256 i = 0; i < tokens.length; i++) {
            _setTargetDenorm(tokens[i], targetDenorms[i]);
        }
    }

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
    )
        external override
        _lock_
        _control_
    {
        require(
            targetDenorms.length == tokens.length && minBalances.length == tokens.length,
            "ERR_ARR_LEN"
        );
        uint256 unbindCounter = 0;
        uint256 tLen = _tokens.length;
        bool[] memory receivedIndices = new bool[](tLen);
        Record[] memory records = new Record[](tokens.length);

        // Mark which tokens on reindexing call are already in pool
        for (uint256 i = 0; i < tokens.length; i++) {
            records[i] = _records[tokens[i]];
            if (records[i].bound) receivedIndices[records[i].index] = true;
        }

        // If any bound tokens were not sent in this call
        // set their target weights to 0 and increment counter
        for (uint256 i = 0; i < tLen; i++) {
            if (!receivedIndices[i]) {
                _setTargetDenorm(_tokens[i], 0);
                unbindCounter++;
            }
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            // If an input weight is less than the minimum weight, use that instead.
            uint256 denorm = targetDenorms[i];
            if (denorm < MIN_WEIGHT) denorm = uint96(MIN_WEIGHT);
            if (!records[i].bound) {
                // If the token is not bound, bind it.
                _bind(token, minBalances[i], denorm);
            } else {
                _setTargetDenorm(token, denorm);
            }
        }

        // Ensure the number of tokens at equilibrium form this 
        // operation is lte max bound tokens
        require(_tokens.length - unbindCounter <= MAX_BOUND_TOKENS, "ERR_MAX_BOUND_TOKENS");
    }

    /* ==========  Internal Token Weighting  ========== */

    /**
     * @dev Bind a new token to the pool, may cause tokens to exceed max assets temporarily
     *
     * @param token Token to add to the pool
     * @param minBalance A set of denorms to linearly update to
     * @param denorm The target denorm to gradually adjust to
     */
    function _bind(address token, uint256 minBalance, uint256 denorm)
        internal
        _logs_
    {
        require(!_records[token].bound, "ERR_IS_BOUND");
        require(denorm >= MIN_WEIGHT, "ERR_MIN_WEIGHT");
        require(denorm <= MAX_WEIGHT, "ERR_MAX_WEIGHT");
        require(minBalance >= MIN_BALANCE, "ERR_MIN_BALANCE");

        _records[token] = Record({
            bound: true,
            ready: false,
            denorm: 0,
            targetDenorm: denorm,
            targetBlock: badd(block.number, TARGET_BLOCK_DELTA),
            lastUpdateBlock: block.number,
            index: uint8(_tokens.length),
            balance: 0
        });

        _tokens.push(token);
        _minBalances[token] = minBalance;
    }

    /**
     * @dev Unbind a token from the pool
     *
     * @param token Token to remove from the pool
     */
    function _unbind(address token)
        internal
        _logs_
    {
        require(_records[token].bound, "ERR_NOT_BOUND");

        uint256 tokenBalance = _records[token].balance;
        _totalWeight = bsub(_totalWeight, _records[token].denorm);

        // Swap the token-to-unbind with the last token,
        // then delete the last token
        uint256 index = _records[token].index;
        uint256 last = _tokens.length - 1;
        _tokens[index] = _tokens[last];
        _records[_tokens[index]].index = uint8(index);
        _tokens.pop();
        _records[token] = Record({
            bound: false,
            ready: false,
            index: 0,
            denorm: 0,
            targetDenorm: 0,
            targetBlock: 0,
            lastUpdateBlock: 0,
            balance: 0
        });

        // TODO: Send this to unbound token handler
        _pushUnderlying(token, address(_unbinder), tokenBalance);
        _unbinder.handleUnboundToken(token);
    }

    /**
     * @dev Set the target denorm of a token
     * linearly adjusts by block + TARGET_BLOCK_DELTA
     *
     * @param token Token to adjust
     * @param denorm Target denorm to set
     */
    function _setTargetDenorm(address token, uint256 denorm) 
        internal
        _logs_
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        require(denorm >= MIN_WEIGHT || denorm == 0, "ERR_MIN_WEIGHT");
        require(denorm <= MAX_WEIGHT, "ERR_MAX_WEIGHT");
        _records[token].targetDenorm = denorm;
        _records[token].targetBlock = badd(block.number, TARGET_BLOCK_DELTA);
        _records[token].lastUpdateBlock = block.number;
    }

    /**
     * @dev Updates the denorm on a given token to match target
     *
     * @param token Token to update denorm for
     */
    function _updateDenorm(address token)
        internal
        _logs_
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        Record memory record = _records[token];
        uint256 targetBlock = record.targetBlock;

        if (block.number < targetBlock && record.denorm != record.targetDenorm) {
            uint256 lastUpdateBlock = record.lastUpdateBlock;
            uint256 blockDelta = bsub(block.number, lastUpdateBlock);
            uint256 blocksLeft = bsub(lastUpdateBlock, block.number);

            if (record.denorm > record.targetDenorm) {
                uint256 denormDelta = bsub(record.denorm, record.targetDenorm);
                uint256 diff = bdiv(bmul(denormDelta, blockDelta), blocksLeft);
                _records[token].denorm = bsub(record.denorm, diff);
                _totalWeight = bsub(_totalWeight, diff);
            } else {
                uint256 denormDelta = bsub(record.targetDenorm, record.denorm);
                uint256 diff = bdiv(bmul(denormDelta, blockDelta), blocksLeft);
                _records[token].denorm = badd(record.denorm, diff);
                _totalWeight = badd(_totalWeight, diff);
            }
        } else if (record.denorm != record.targetDenorm || record.lastUpdateBlock != record.targetBlock) {
            // Ensure denorm set to target if equal, or past targetBlock
            _records[token].denorm = _records[token].targetDenorm;
            _records[token].lastUpdateBlock = _records[token].targetBlock;
        }
    }

    /**
     * @dev Performs a full update on a tokens state
     *
     * @param token Token to adjust
     * @param balance New token balance
     */
    function _updateToken(
        address token,
        uint256 balance
    )
        internal
    {
        if (!_records[token].ready) {
            // Check if the minimum balance has been reached
            if (balance >= _minBalances[token]) {
                // Mark the token as ready
                _records[token].ready = true;
                emit LogTokenReady(token);
                // Set the initial denorm value to the minimum weight times one plus
                // the ratio of the increase in balance over the minimum to the minimum
                // balance.
                // weight = (1 + ((bal - min_bal) / min_bal)) * min_weight
                uint256 currBalance = _getBalance(token);
                uint256 additionalBalance = bsub(balance, currBalance);
                uint256 balRatio = bdiv(additionalBalance, currBalance);
                uint256 denorm = badd(MIN_WEIGHT, bmul(MIN_WEIGHT, balRatio));
                _records[token].denorm = denorm;
                _records[token].lastUpdateBlock = block.number;
                _records[token].targetBlock = badd(block.number, TARGET_BLOCK_DELTA);
                _totalWeight = badd(_totalWeight, _records[token].denorm);
                // Remove the minimum balance record
                _minBalances[token] = 0;
            } else {
                uint256 currBalance = _getBalance(token);
                uint256 realToMinRatio = bdiv(bsub(currBalance, balance), currBalance);
                uint256 weightPremium = bmul(MIN_WEIGHT / 10, realToMinRatio);
                _records[token].denorm = badd(MIN_WEIGHT, weightPremium);
            }
            _records[token].balance = balance;
        } else {
            // Update denorm if token is ready
            _updateDenorm(token);
            _records[token].balance = balance;
            // Always check if token needs to be unbound
            if (_records[token].denorm < MIN_WEIGHT) {
                _unbind(token);
            }
        }
    }

    /**
     * @dev Internal view to get the current treatment balance for a token
     *
     * @param token Token to get balance for
     */
    function _getBalance(
        address token
    )
        internal view
        returns (uint256 balance)
    {
        if (_records[token].ready) {
            return _records[token].balance;
        } else {
            return _minBalances[token];
        }
    }

    // Absorb any tokens that have been sent to this contract into the pool
    function gulp(address token)
        external override
        _logs_
        _lock_
    {
        Record storage record = _records[token];
        uint256 balance = IERC20Upgradeable(token).balanceOf(address(this));
        if (record.bound) {
            _updateToken(token, balance);
        } else {
            _pushUnderlying(token, address(_unbinder), balance);
            _unbinder.handleUnboundToken(token);
        }
    }

    /* ==========  Pool Entry/Exit  ========== */

    function joinPool(uint256 poolAmountOut, uint[] calldata maxAmountsIn)
        external override
        _public_
        _logs_
        _lock_
    {
        require(maxAmountsIn.length == _tokens.length, "ERR_ARR_LEN");

        uint256 poolTotal = totalSupply();
        uint256 ratio = bdiv(poolAmountOut, poolTotal);
        require(ratio != 0, "ERR_MATH_APPROX");

        for (uint256 i = 0; i < _tokens.length; i++) {
            address t = _tokens[i];
            uint256 bal = _getBalance(t);
            uint256 tokenAmountIn = bmul(ratio, bal);
            require(tokenAmountIn != 0, "ERR_MATH_APPROX");
            require(tokenAmountIn <= maxAmountsIn[i], "ERR_LIMIT_IN");
            _updateToken(t, badd(_records[t].balance, tokenAmountIn));
            emit LogJoin(msg.sender, t, tokenAmountIn);
            _pullUnderlying(t, msg.sender, tokenAmountIn);
        }
        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
    }

    function exitPool(uint256 poolAmountIn, uint[] calldata minAmountsOut)
        external override
        _public_
        _logs_
        _lock_
    {
        uint256 poolTotal = totalSupply();
        uint256 exitFee = bmul(poolAmountIn, _exitFee);
        uint256 pAiAfterExitFee = bsub(poolAmountIn, exitFee);
        uint256 ratio = bdiv(pAiAfterExitFee, poolTotal);
        require(ratio != 0, "ERR_MATH_APPROX");

        _pullPoolShare(msg.sender, poolAmountIn);
        _pushPoolShare(_controller, exitFee);
        _burnPoolShare(pAiAfterExitFee);

        for (uint256 i = 0; i < _tokens.length; i++) {
            address t = _tokens[i];
            Record memory record = _records[t];

            if (record.ready) {
                uint256 tokenAmountOut = bmul(ratio, record.balance);
                require(tokenAmountOut != 0, "ERR_MATH_APPROX");
                require(tokenAmountOut >= minAmountsOut[i], "ERR_LIMIT_OUT");
                _records[t].balance = bsub(_records[t].balance, tokenAmountOut);
                emit LogExit(msg.sender, t, tokenAmountOut);
                _pushUnderlying(t, msg.sender, tokenAmountOut);
            } else {
                // Uninitialized tokens cannot exit the pool
                require(minAmountsOut[i] == 0, "ERR_NOT_READY");
            }
        }
    }

    /* ==========  Swaps  ========== */

    function swapExactAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut,
        uint256 maxPrice
    )
        external override
        _logs_
        _lock_
        _public_
        _rebalance_
        returns (uint256 tokenAmountOut, uint256 spotPriceAfter)
    {
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_READY");

        Record memory inRecord = _records[tokenIn];
        uint256 inRecordBalance = _getBalance(tokenIn);
        Record memory outRecord = _records[tokenOut];

        require(tokenAmountIn <= bmul(inRecord.balance, MAX_IN_RATIO), "ERR_MAX_IN_RATIO");

        uint256 spotPriceBefore = calcSpotPrice(
                                    inRecordBalance,
                                    inRecord.denorm,
                                    outRecord.balance,
                                    outRecord.denorm,
                                    _swapFee
                                );
        require(spotPriceBefore <= maxPrice, "ERR_BAD_LIMIT_PRICE");

        tokenAmountOut = calcOutGivenIn(
                            inRecordBalance,
                            inRecord.denorm,
                            outRecord.balance,
                            outRecord.denorm,
                            tokenAmountIn,
                            _swapFee
                        );
        require(tokenAmountOut >= minAmountOut, "ERR_LIMIT_OUT");

        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);

        // Update tokens
        _updateToken(tokenIn, badd(inRecord.balance, tokenAmountIn));
        _updateToken(tokenIn, bsub(inRecord.balance, tokenAmountIn));

        spotPriceAfter = calcSpotPrice(
                                inRecordBalance,
                                inRecord.denorm,
                                outRecord.balance,
                                outRecord.denorm,
                                _swapFee
                            );
        require(spotPriceAfter >= spotPriceBefore, "ERR_MATH_APPROX");     
        require(spotPriceAfter <= maxPrice, "ERR_LIMIT_PRICE");
        require(spotPriceBefore <= bdiv(tokenAmountIn, tokenAmountOut), "ERR_MATH_APPROX");

        emit LogSwap(msg.sender, tokenIn, tokenOut, tokenAmountIn, tokenAmountOut);

        return (tokenAmountOut, spotPriceAfter);
    }

    function swapExactAmountOut(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPrice
    )
        external override
        _logs_
        _lock_
        _public_
        _rebalance_
        returns (uint256 tokenAmountIn, uint256 spotPriceAfter)
    {
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_READY");

        Record memory inRecord = _records[tokenIn];
        uint256 inRecordBalance = _getBalance(tokenIn);
        Record memory outRecord = _records[tokenOut];

        require(tokenAmountOut <= bmul(outRecord.balance, MAX_OUT_RATIO), "ERR_MAX_OUT_RATIO");

        uint256 spotPriceBefore = calcSpotPrice(
                                    inRecordBalance,
                                    inRecord.denorm,
                                    outRecord.balance,
                                    outRecord.denorm,
                                    _swapFee
                                );
        require(spotPriceBefore <= maxPrice, "ERR_BAD_LIMIT_PRICE");

        tokenAmountIn = calcInGivenOut(
                            inRecordBalance,
                            inRecord.denorm,
                            outRecord.balance,
                            outRecord.denorm,
                            tokenAmountOut,
                            _swapFee
                        );
        require(tokenAmountIn <= maxAmountIn, "ERR_LIMIT_IN");

        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);

        // Update tokens
        _updateToken(tokenIn, badd(inRecord.balance, tokenAmountOut));
        _updateToken(tokenIn, bsub(inRecord.balance, tokenAmountOut));

        inRecord.balance = badd(inRecord.balance, tokenAmountIn);
        outRecord.balance = bsub(outRecord.balance, tokenAmountOut);

        spotPriceAfter = calcSpotPrice(
                                inRecordBalance,
                                inRecord.denorm,
                                outRecord.balance,
                                outRecord.denorm,
                                _swapFee
                            );
        require(spotPriceAfter >= spotPriceBefore, "ERR_MATH_APPROX");
        require(spotPriceAfter <= maxPrice, "ERR_LIMIT_PRICE");
        require(spotPriceBefore <= bdiv(tokenAmountIn, tokenAmountOut), "ERR_MATH_APPROX");

        emit LogSwap(msg.sender, tokenIn, tokenOut, tokenAmountIn, tokenAmountOut);

        return (tokenAmountIn, spotPriceAfter);
    }

    /* ==========  Internal Helpers  ========== */

    // ==
    // 'Underlying' token-manipulation functions make external calls but are NOT locked
    // You must `_lock_` or otherwise ensure reentry-safety

    function _pullUnderlying(address erc20, address from, uint256 amount)
        internal
    {
        IERC20Upgradeable(erc20).safeTransferFrom(from, address(this), amount);
    }

    function _pushUnderlying(address erc20, address to, uint256 amount)
        internal
    {
        IERC20Upgradeable(erc20).safeTransfer(to, amount);
    }

    function _pullPoolShare(address from, uint256 amount)
        internal
    {
        _pull(from, amount);
    }

    function _pushPoolShare(address to, uint256 amount)
        internal
    {
        _push(to, amount);
    }

    function _mintPoolShare(uint256 amount)
        internal
    {
        _mint(amount);
    }

    function _burnPoolShare(uint256 amount)
        internal
    {
        _burn(amount);
    }
}

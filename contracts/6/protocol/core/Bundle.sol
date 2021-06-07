// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;

import "./BToken.sol";
import "./BMath.sol";

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

/************************************************************************************************
Originally forked from https://github.com/balancer-labs/balancer-core/

This source code has been modified from the original, which was copied from the github repository
at commit hash f4ed5d65362a8d6cec21662fb6eae233b0babc1f.

Subject to the GPL-3.0 license
*************************************************************************************************/

contract Bundle is Initializable, BToken, BMath {

    struct Record {
        bool bound;               // is token bound to pool
        bool ready;
        uint256 denorm;            // denormalized weight
        uint256 targetDenorm;
        uint256 targetBlock;
        uint8 index;              // private
        uint256 balance;
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

    // `setSwapFee` and `finalize` require CONTROL
    // `finalize` sets `PUBLIC can SWAP`, `PUBLIC can JOIN`
    uint256 private _swapFee;

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

    /* ========== Initialization ========== */

    function initialize(address controller, address rebalancer, string calldata name, string calldata symbol) 
        external 
        initializer
    {
        _controller = controller;
        _rebalancer = rebalancer;
        _swapFee = MIN_FEE;
        _publicSwap = false;
        _initializeToken(name, symbol);
    }

    function setup(
        address[] calldata tokens,
        uint256[] calldata balances,
        uint256[] calldata denorms,
        address tokenProvider
    )
        external
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
        _setup = true;
        emit LogPublicSwapEnabled();
        _mintPoolShare(INIT_POOL_SUPPLY);
        _pushPoolShare(tokenProvider, INIT_POOL_SUPPLY);
    }

    /* ==========  Control  ========== */

    function setSwapFee(uint256 swapFee)
        external
        _lock_
        _control_
    { 
        require(swapFee >= MIN_FEE, "ERR_MIN_FEE");
        require(swapFee <= MAX_FEE, "ERR_MAX_FEE");
        _swapFee = swapFee;
        emit LogSwapFeeUpdated(msg.sender, swapFee);
    }

    function setController(address manager)
        external
        _logs_
        _lock_
        _control_
    {
        _controller = manager;
    }

    function setRebalancer(address rebalancer)
        external
        _logs_
        _lock_
        _control_
    {
        _rebalancer = rebalancer;
    }

    function setPublicSwap(bool public_)
        external
        _logs_
        _lock_
        _control_
    {
        _publicSwap = public_;
    }

    function setMinBalance(address token, uint256 minBalance) 
        external
        _logs_
        _lock_
        _control_
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        require(!_records[token].ready, "ERR_READY");
        _minBalances[token] = minBalance;
    }

    /* ==========  Getters  ========== */

    function isPublicSwap()
        external view
        returns (bool)
    {
        return _publicSwap;
    }

    function isBound(address t)
        external view
        returns (bool)
    {
        return _records[t].bound;
    }

    function getNumTokens()
        external view
        returns (uint) 
    {
        return _tokens.length;
    }

    function getCurrentTokens()
        external view _viewlock_
        returns (address[] memory tokens)
    {
        return _tokens;
    }

    function getDenormalizedWeight(address token)
        external view
        _viewlock_
        returns (uint)
    {

        require(_records[token].bound, "ERR_NOT_BOUND");
        return _records[token].denorm;
    }

    function getTotalDenormalizedWeight()
        external view
        _viewlock_
        returns (uint)
    {
        return _totalWeight;
    }

    function getNormalizedWeight(address token)
        external view
        _viewlock_
        returns (uint)
    {

        require(_records[token].bound, "ERR_NOT_BOUND");
        uint256 denorm = _records[token].denorm;
        return bdiv(denorm, _totalWeight);
    }

    function getBalance(address token)
        external view
        _viewlock_
        returns (uint)
    {

        require(_records[token].bound, "ERR_NOT_BOUND");
        return _records[token].balance;
    }

    function getSwapFee()
        external view
        _viewlock_
        returns (uint)
    {
        return _swapFee;
    }

    function getController()
        external view
        _viewlock_
        returns (address)
    {
        return _controller;
    }

    function getRebalancer()
        external view
        _viewlock_
        returns (address)
    {
        return _rebalancer;
    }

    function getSpotPrice(address tokenIn, address tokenOut)
        external view
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
        external view
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

    function reweighTokens(
        address[] calldata tokens,
        uint256[] calldata targetDenorms
    )
        external
        _lock_
        _control_
    {
        require(targetDenorms.length == tokens.length, "ERR_ARR_LEN");
        for (uint256 i = 0; i < tokens.length; i++) {
            _setTargetDenorm(tokens[i], targetDenorms[i]);
        }
    }

    /**
    * @dev Update the underlying assets held by the pool and their associated
    * weights. Tokens which are not currently bound will be gradually added
    * as they are swapped in to reach the provided minimum balances, which must
    * be an amount of tokens worth the minimum weight of the total pool value.
    * If a currently bound token is not received in this call, the token's
    * desired weight will be set to 0.
    */
    function reindexTokens(
        address[] calldata tokens,
        uint256[] calldata targetDenorms,
        uint256[] calldata minBalances
    )
        external
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

        // We need to read token records in two separate loops, so
        // write them to memory to avoid duplicate storage reads.
        Record[] memory records = new Record[](tokens.length);

        // Read all the records from storage and mark which of the existing tokens
        // were represented in the reindex call.
        for (uint256 i = 0; i < tokens.length; i++) {
            records[i] = _records[tokens[i]];
            if (records[i].bound) receivedIndices[records[i].index] = true;
        }

        // If any bound tokens were not sent in this call, set their desired weights to 0.
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

    function _bind(address token, uint256 balance, uint256 denorm)
        internal
        _logs_
        _lock_
    {
        require(!_records[token].bound, "ERR_IS_BOUND");
        require(denorm >= MIN_WEIGHT, "ERR_MIN_WEIGHT");
        require(denorm <= MAX_WEIGHT, "ERR_MAX_WEIGHT");
        require(balance >= MIN_BALANCE, "ERR_MIN_BALANCE");

        _records[token] = Record({
            bound: true,
            ready: false,
            denorm: 0,
            targetDenorm: denorm,
            targetBlock: badd(block.number, TARGET_BLOCK_DELTA),
            index: uint8(_tokens.length),
            balance: 0
        });

        _tokens.push(token);
        _minBalances[token] = balance;
    }

    function _unbind(address token)
        internal
        _logs_
        _lock_
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
            balance: 0
        });

        // TODO: Send this to unbound token handler
        _pushUnderlying(token, msg.sender, tokenBalance);
    }

    function _setTargetDenorm(address token, uint256 denorm) 
        internal
        _logs_
        _lock_
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        require(denorm >= MIN_WEIGHT || denorm == 0, "ERR_MIN_WEIGHT");
        require(denorm <= MAX_WEIGHT, "ERR_MAX_WEIGHT");
        _records[token].targetDenorm = denorm;
        _records[token].targetBlock = badd(block.number, TARGET_BLOCK_DELTA);
    }

    function _updateDenorm(address token)
        internal
        _logs_
        _lock_
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        uint256 targetBlock = _records[token].targetBlock;

        if (block.number < targetBlock) {
            uint256 delta = bsub(_records[token].targetDenorm, _records[token].denorm);
            uint256 denorm = bdiv(bmul(delta, block.number), bsub(targetBlock, block.number));

            if (denorm < MIN_WEIGHT) {
                _unbind(token);
            } else {
                // Adjust total weight
                if (_records[token].denorm > denorm) {
                    uint256 diff = bsub(_records[token].denorm, denorm);
                    _totalWeight = bsub(_totalWeight, diff);
                } else {
                    uint256 diff = bsub(denorm, _records[token].denorm);
                    _totalWeight = badd(_totalWeight, diff);
                }

                _records[token].denorm = denorm;
            }
        } else {
            // If gte target block, ensure denorm is set to the target
            _records[token].denorm = _records[token].targetDenorm;
        }
    }

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
                _records[token].targetBlock = block.number;
                _totalWeight = badd(_totalWeight, _records[token].denorm);
                // Remove the minimum balance record
                _minBalances[token] = 0;
            } else {
                uint256 currBalance = _getBalance(token);
                uint256 realToMinRatio = bdiv(bsub(currBalance, balance), currBalance);
                uint256 weightPremium = bmul(MIN_WEIGHT / 10, realToMinRatio);
                _records[token].denorm = badd(MIN_WEIGHT, weightPremium);
            }
        } else {
            // Update denorm if token is ready
            _updateDenorm(token);
        }
        // Regardless of whether the token is initialized, store the actual new balance.
        _records[token].balance = balance;
    }

    function _getBalance(
        address token
    )
        internal
        view
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
        external
        _logs_
        _lock_
    {
        require(_records[token].bound, "ERR_NOT_BOUND");
        _records[token].balance = IERC20(token).balanceOf(address(this));
    }

    /* ==========  Pool Entry/Exit  ========== */

    function joinPool(uint256 poolAmountOut, uint[] calldata maxAmountsIn)
        external
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
        external
        _public_
        _logs_
        _lock_
    {
        uint256 poolTotal = totalSupply();
        uint256 exitFee = bmul(poolAmountIn, EXIT_FEE);
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
        external
        _logs_
        _lock_
        _rebalance_
        returns (uint256 tokenAmountOut, uint256 spotPriceAfter)
    {

        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        require(_publicSwap, "ERR_SWAP_NOT_PUBLIC");

        Record storage inRecord = _records[address(tokenIn)];
        Record storage outRecord = _records[address(tokenOut)];

        require(tokenAmountIn <= bmul(inRecord.balance, MAX_IN_RATIO), "ERR_MAX_IN_RATIO");

        uint256 spotPriceBefore = calcSpotPrice(
                                    inRecord.balance,
                                    inRecord.denorm,
                                    outRecord.balance,
                                    outRecord.denorm,
                                    _swapFee
                                );
        require(spotPriceBefore <= maxPrice, "ERR_BAD_LIMIT_PRICE");

        tokenAmountOut = calcOutGivenIn(
                            inRecord.balance,
                            inRecord.denorm,
                            outRecord.balance,
                            outRecord.denorm,
                            tokenAmountIn,
                            _swapFee
                        );
        require(tokenAmountOut >= minAmountOut, "ERR_LIMIT_OUT");

        inRecord.balance = badd(inRecord.balance, tokenAmountIn);
        outRecord.balance = bsub(outRecord.balance, tokenAmountOut);

        spotPriceAfter = calcSpotPrice(
                                inRecord.balance,
                                inRecord.denorm,
                                outRecord.balance,
                                outRecord.denorm,
                                _swapFee
                            );
        require(spotPriceAfter >= spotPriceBefore, "ERR_MATH_APPROX");     
        require(spotPriceAfter <= maxPrice, "ERR_LIMIT_PRICE");
        require(spotPriceBefore <= bdiv(tokenAmountIn, tokenAmountOut), "ERR_MATH_APPROX");

        emit LogSwap(msg.sender, tokenIn, tokenOut, tokenAmountIn, tokenAmountOut);

        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);

        return (tokenAmountOut, spotPriceAfter);
    }

    function swapExactAmountOut(
        address tokenIn,
        uint256 maxAmountIn,
        address tokenOut,
        uint256 tokenAmountOut,
        uint256 maxPrice
    )
        external
        _logs_
        _lock_
        _rebalance_
        returns (uint256 tokenAmountIn, uint256 spotPriceAfter)
    {
        require(_records[tokenIn].bound, "ERR_NOT_BOUND");
        require(_records[tokenOut].bound, "ERR_NOT_BOUND");
        require(_publicSwap, "ERR_SWAP_NOT_PUBLIC");

        Record storage inRecord = _records[address(tokenIn)];
        Record storage outRecord = _records[address(tokenOut)];

        require(tokenAmountOut <= bmul(outRecord.balance, MAX_OUT_RATIO), "ERR_MAX_OUT_RATIO");

        uint256 spotPriceBefore = calcSpotPrice(
                                    inRecord.balance,
                                    inRecord.denorm,
                                    outRecord.balance,
                                    outRecord.denorm,
                                    _swapFee
                                );
        require(spotPriceBefore <= maxPrice, "ERR_BAD_LIMIT_PRICE");

        tokenAmountIn = calcInGivenOut(
                            inRecord.balance,
                            inRecord.denorm,
                            outRecord.balance,
                            outRecord.denorm,
                            tokenAmountOut,
                            _swapFee
                        );
        require(tokenAmountIn <= maxAmountIn, "ERR_LIMIT_IN");

        inRecord.balance = badd(inRecord.balance, tokenAmountIn);
        outRecord.balance = bsub(outRecord.balance, tokenAmountOut);

        spotPriceAfter = calcSpotPrice(
                                inRecord.balance,
                                inRecord.denorm,
                                outRecord.balance,
                                outRecord.denorm,
                                _swapFee
                            );
        require(spotPriceAfter >= spotPriceBefore, "ERR_MATH_APPROX");
        require(spotPriceAfter <= maxPrice, "ERR_LIMIT_PRICE");
        require(spotPriceBefore <= bdiv(tokenAmountIn, tokenAmountOut), "ERR_MATH_APPROX");

        emit LogSwap(msg.sender, tokenIn, tokenOut, tokenAmountIn, tokenAmountOut);

        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);

        return (tokenAmountIn, spotPriceAfter);
    }

    /* ==========  Internal Helpers  ========== */

    // ==
    // 'Underlying' token-manipulation functions make external calls but are NOT locked
    // You must `_lock_` or otherwise ensure reentry-safety

    function _pullUnderlying(address erc20, address from, uint256 amount)
        internal
    {
        bool xfer = IERC20(erc20).transferFrom(from, address(this), amount);
        require(xfer, "ERR_ERC20_FALSE");
    }

    function _pushUnderlying(address erc20, address to, uint256 amount)
        internal
    {
        bool xfer = IERC20(erc20).transfer(to, amount);
        require(xfer, "ERR_ERC20_FALSE");
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

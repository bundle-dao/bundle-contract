// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;

/************************************************************************************************
Originally forked from https://github.com/balancer-labs/balancer-core/

This source code has been modified from the original, which was copied from the github repository
at commit hash f4ed5d65362a8d6cec21662fb6eae233b0babc1f.

Subject to the GPL-3.0 license
*************************************************************************************************/

contract BConst {
    uint256 internal constant BONE               = 10**18;

    uint256 internal constant MIN_BOUND_TOKENS   = 2;
    uint256 internal constant MAX_BOUND_TOKENS   = 15;

    uint256 internal constant MIN_FEE            = BONE / 10**6;
    uint256 internal constant INIT_FEE           = (2 * BONE) / 10**2;
    uint256 internal constant MAX_FEE            = BONE / 10;
    
    uint256 internal constant INIT_EXIT_FEE      = (2 * BONE) / 10**2;
    uint256 internal constant MAX_EXIT_FEE       = (5 * BONE) / 10**2;

    uint256 internal constant MAX_STREAMING_FEE  = (4 * BONE) / 10**2;
    uint256 internal constant INIT_STREAMING_FEE = (2 * BONE) / 10**2;
    uint256 internal constant BPY                = 365 days;

    uint256 internal constant MIN_WEIGHT         = BONE / 2;
    uint256 internal constant MAX_WEIGHT         = BONE * 50;
    uint256 internal constant MAX_TOTAL_WEIGHT   = BONE * 51;
    uint256 internal constant MIN_BALANCE        = BONE / 10**12;

    uint256 internal constant INIT_POOL_SUPPLY   = BONE * 100;

    uint256 internal constant MIN_BPOW_BASE      = 1 wei;
    uint256 internal constant MAX_BPOW_BASE      = (2 * BONE) - 1 wei;
    uint256 internal constant BPOW_PRECISION     = BONE / 10**10;

    uint256 internal constant MAX_TARGET_DELTA   = 14 days;
    uint256 internal constant INIT_TARGET_DELTA  = 7 days;
    uint256 internal constant MIN_TARGET_DELTA   = 1 days;

    uint256 internal constant MAX_IN_RATIO       = BONE / 2;
    uint256 internal constant MAX_OUT_RATIO      = (BONE / 3) + 1 wei;
}

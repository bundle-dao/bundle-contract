// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;

/************************************************************************************************
Originally forked from https://github.com/balancer-labs/balancer-core/

This source code has been modified from the original, which was copied from the github repository
at commit hash f4ed5d65362a8d6cec21662fb6eae233b0babc1f.

Subject to the GPL-3.0 license
*************************************************************************************************/

contract BConst {
    uint internal constant BONE               = 10**18;

    uint internal constant MIN_BOUND_TOKENS   = 2;
    uint internal constant MAX_BOUND_TOKENS   = 8;

    uint internal constant MIN_FEE            = BONE / 10**6;
    uint internal constant MAX_FEE            = BONE / 10;
    uint internal constant EXIT_FEE           = 0;

    uint internal constant MAX_STREAMING_FEE  = (4 * BONE) / 10**2;
    uint internal constant INIT_STREAMING_FEE = (2 * BONE) / 10**2;
    uint internal constant BPY                = 10512000;

    uint internal constant MIN_WEIGHT         = BONE;
    uint internal constant MAX_WEIGHT         = BONE * 50;
    uint internal constant MAX_TOTAL_WEIGHT   = BONE * 50;
    uint internal constant MIN_BALANCE        = BONE / 10**12;

    uint internal constant INIT_POOL_SUPPLY   = BONE * 100;

    uint internal constant MIN_BPOW_BASE      = 1 wei;
    uint internal constant MAX_BPOW_BASE      = (2 * BONE) - 1 wei;
    uint internal constant BPOW_PRECISION     = BONE / 10**10;

    uint internal constant TARGET_BLOCK_DELTA = 28800;

    uint internal constant MAX_IN_RATIO       = BONE / 2;
    uint internal constant MAX_OUT_RATIO      = (BONE / 3) + 1 wei;
}

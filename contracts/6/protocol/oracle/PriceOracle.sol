// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@pancakeswap-libs/pancake-swap-core/contracts/interfaces/IPancakePair.sol";
import "@bundle-dao/pancakeswap-peripheral/contracts/libraries/PancakeOracleLibrary.sol";
import "@bundle-dao/pancakeswap-peripheral/contracts/libraries/PancakeLibrary.sol";

import "../interfaces/IPriceOracle.sol";

contract PriceOracle is Ownable, IPriceOracle {
    using FixedPoint for *;

    struct PriceData {
        bool initialized;
        uint32 lastUpdatedAt;
        uint256 price0CumulativeLast;
        uint256 price1CumulativeLast;
        FixedPoint.uq112x112 price0Average;
        FixedPoint.uq112x112 price1Average;
    }

    /* ========== Storage ========== */

    uint256 public constant PERIOD = 1 hours;
    address private _factory;
    address private _peg;
    mapping(address=>PriceData) private _prices;
    mapping(address=>address[]) private _referencePaths;

    /* ========== Constructor ========== */

    constructor(address factory, address peg) public {
        _factory = factory;
        _peg = peg;
    }

    /* ========== Control ========== */

    // Reference paths should all have same output token
    function setReferencePath(address token, address[] calldata path) 
        external onlyOwner 
    {
        require(_peg == path[path.length - 1], "ERR_BAD_REFERENCE_PATH");
        require(token == path[0], "ERR_BAD_REFERENCE_PATH");
        require(path.length >= 2, "ERR_BAD_PATH");
        _referencePaths[token] = path;

        address tokenA;
        address tokenB;

        for (uint256 i = 1; i < path.length; i++) {
            tokenA = path[i - 1];
            tokenB = path[i];
            initializePair(tokenA, tokenB);
        }
    }

    /* ========== Public ========== */

    function updateReference(address token) 
        external override 
    {
        address[] memory path = _referencePaths[token];
        require(path.length >= 2, "ERR_BAD_PATH");
        address tokenA;
        address tokenB;

        for (uint256 i = 1; i < path.length; i++) {
            tokenA = path[i - 1];
            tokenB = path[i];
            _update(tokenA, tokenB);
        }
    }

    function updatePath(address[] calldata path)
        public override
    {
        require(path.length >= 2, "ERR_BAD_PATH");
        address tokenA;
        address tokenB;

        for (uint256 i = 1; i < path.length; i++) {
            tokenA = path[i - 1];
            tokenB = path[i];
            _update(tokenA, tokenB);
        }
    } 

    function consultReference(address token, uint256 amountIn) 
        external view override 
        returns (uint256) 
    {
        address[] memory path = _referencePaths[token];
        require(path.length >= 2, "ERR_BAD_PATH");
        address tokenA;
        address tokenB;
        uint256 amount = amountIn;

        for (uint256 i = 1; i < path.length; i++) {
            tokenA = path[i - 1];
            tokenB = path[i];
            amount = _consult(tokenA, tokenB, amount);
        }

        return amount;
    }

    function consultPath(address[] calldata path, uint256 amountIn)
        external view override
        returns (uint256)
    {
        require(path.length >= 2, "ERR_BAD_PATH");
        address tokenA;
        address tokenB;
        uint256 amount = amountIn;

        for (uint256 i = 1; i < path.length; i++) {
            tokenA = path[i - 1];
            tokenB = path[i];
            amount = _consult(tokenA, tokenB, amount);
        }

        return amount;
    }

    function initializePair(address tokenA, address tokenB) 
        public override
    {
        require(address(tokenA) != address(0) && address(tokenB) != address(0), "ERR_BAD_ADDRESS");

        IPancakePair pair = IPancakePair(PancakeLibrary.pairFor(_factory, tokenA, tokenB));

        if (!_prices[address(pair)].initialized) {
            (uint256 reserve0, uint256 reserve1, uint32 blockTimestampLast) = pair.getReserves();
            require(reserve0 != 0 && reserve1 != 0, "ERR_NO_RESERVES"); // ensure that there's liquidity in the pair

            _prices[address(pair)] = PriceData({
                initialized: true,
                lastUpdatedAt: blockTimestampLast,
                price0CumulativeLast: pair.price0CumulativeLast(),
                price1CumulativeLast: pair.price0CumulativeLast(),
                price0Average: FixedPoint.uq112x112(0),
                price1Average: FixedPoint.uq112x112(0)
            });
        }
    }

    function getPeg() 
        external view override 
        returns (address) 
    {
        return _peg;
    }

    /* ========== Internal ========== */

    function _update(address tokenA, address tokenB) 
        internal 
    {
        IPancakePair pair = IPancakePair(PancakeLibrary.pairFor(_factory, tokenA, tokenB));
        PriceData memory priceData = _prices[address(pair)];
        require(priceData.initialized, "ERR_PAIR_NOT_INITIALIZED");

        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
            PancakeOracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - priceData.lastUpdatedAt; // overflow is desired

        // ensure that at least one full period has passed since the last update
        if (timeElapsed >= PERIOD) {
            // overflow is desired, casting never truncates
            // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
            _prices[address(pair)].price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - priceData.price0CumulativeLast) / timeElapsed));
            _prices[address(pair)].price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - priceData.price1CumulativeLast) / timeElapsed));
            _prices[address(pair)].price0CumulativeLast = price0Cumulative;
            _prices[address(pair)].price1CumulativeLast = price1Cumulative;
            _prices[address(pair)].lastUpdatedAt = blockTimestamp;
        }
    }

    // note this will always return 0 before update has been called successfully for the first time.
    function _consult(address tokenIn, address tokenOut, uint256 amountIn) 
        internal view 
        returns (uint256) 
    {
        IPancakePair pair = IPancakePair(PancakeLibrary.pairFor(_factory, tokenIn, tokenOut));
        PriceData memory priceData = _prices[address(pair)];
        require(priceData.initialized, "ERR_PAIR_NOT_INITIALIZED");
        
        if (tokenIn == pair.token0()) {
            return priceData.price0Average.mul(amountIn).decode144();
        } else {
            require(tokenIn == pair.token1(), "ERR_INVALID_TOKEN");
            return priceData.price1Average.mul(amountIn).decode144();
        }
    }
}
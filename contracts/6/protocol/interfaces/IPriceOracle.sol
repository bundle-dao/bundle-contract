// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IPriceOracle {
    function updateReference(address token) external;

    function updatePath(address[] calldata path) external;

    function consultReference(address token, uint256 amountIn) external view returns (uint256);

    function consultPath(address[] calldata path, uint256 amountIn) external view returns (uint256);

    function initializePair(address tokenA, address tokenB) external;

    function getPeg() external view returns (address);
}
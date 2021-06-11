// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IRebalancer {
    function initialize(address router, address controller, address bundleToken, address bundleLock) external;

    function setPremium(uint256 premium) external;

    function setWhitelist(address pool, bool flag) external;

    function setTierLock(uint256 tierLock) external;

    function getController() external view returns (address);

    function getPremium() external view returns (uint256);

    function swap(
        address pool,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 deadline,
        address[] calldata path
    ) external;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IRebalancer {
    function setPremium(uint256 premium) external;

    function setWhitelist(address pool, bool flag) external;

    function setLock(bool lock) external;

    function setDev(address dev) external;

    function setOracle(address oracle) external;

    function setGap(uint256 gap) external;

    function getController() external view returns (address);

    function getPremium() external view returns (uint256);

    function isWhitelisted(address pool) external view returns (bool);

    function getDev() external view returns (address);

    function getOracle() external view returns (address);

    function getGap() external view returns (uint256);

    function isLocked() external view returns (bool);

    function swap(
        address pool,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 deadline,
        address[] calldata path
    ) external;
}

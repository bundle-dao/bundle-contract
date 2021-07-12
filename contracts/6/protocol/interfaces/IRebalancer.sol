// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IRebalancer {
    struct SwapToken {
        bool flag;
        uint256 index;
    }

    event LogPremium(
        address indexed caller,
        uint256         premium
    );

    event LogWhitelist(
        address indexed caller,
        address         bundle,
        bool            flag
    );

    event LogSwapWhitelist(
        address indexed caller,
        address         token,
        bool            flag
    );

    event LogOracle(
        address indexed caller,
        address         oracle
    );

    event LogGap(
        address indexed caller,
        uint256         gap
    );

    function setPremium(uint256 premium) external;

    function setWhitelist(address pool, bool flag) external;

    function setSwapWhitelist(address token, bool flag) external;

    function setOracle(address oracle) external;

    function setGap(uint256 gap) external;

    function getController() external view returns (address);

    function getPremium() external view returns (uint256);

    function getSwapWhitelist() external view returns (address[] memory);

    function isWhitelisted(address pool) external view returns (bool);

    function isSwapWhitelisted(address token) external view returns (bool);

    function getOracle() external view returns (address);

    function getGap() external view returns (uint256);

    function swap(
        address pool,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 deadline,
        address[] calldata path
    ) external;
}

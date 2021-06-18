// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@bundle-dao/pancakeswap-peripheral/contracts/interfaces/IPancakeRouter02.sol";
import "./IBundle.sol";

interface IUnbinder {
    event TokenUnbound(address token);

    function initialize(address bundle, address router, address controller) external;

    function handleUnboundToken(address token) external;

    function distributeUnboundToken(address token, uint256 amount, uint256 deadline, address[] calldata routeTokens) external;

    function setPremium(uint256 premium) external;

    function getPremium() external view returns (uint256);

    function getController() external view returns (address);

    function getBundle() external view returns (address);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IUnbinder {
    event TokenUnbound(address token);

    function handleUnboundToken(address token) external;
    function distributeUnboundToken(address token, uint256 amount) external;
    function setPremium(uint256 _premium) external;
}
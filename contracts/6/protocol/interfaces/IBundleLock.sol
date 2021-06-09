// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IBundleLock {
    function getLockThreshold(uint256 index) external view returns (uint256);

    function setLockThreshold(uint256 index, uint256 lockThreshold) external;

    function pushTier(uint256 lockThreshold) external;

    function popTier() external;

    function getTier(address user) external view returns (uint256);

    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;
}
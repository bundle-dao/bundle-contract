// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IBundleLock {
    function getLockThreshold() external view returns(uint256);

    function setLockThreshold(uint256 lockThreshold) external;

    function getApprovalState(address user) external view returns(bool);

    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;
}
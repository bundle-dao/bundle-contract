// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IBundleFactory {
    function setController(address controller) external;

    function setRebalancer(address rebalancer) external;

    function getController() external view returns (address);

    function getRebalancer() external view returns (address);

    function deploy(
        string calldata name,
        string calldata symbol
    ) external returns (address bundle, address unbinder);
}

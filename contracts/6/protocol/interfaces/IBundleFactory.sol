// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IBundleFactory {
    function setController(address controller) external;

    function deploy(
        string calldata name,
        string calldata symbol
    ) external returns (address bundle, address unbinder);
}

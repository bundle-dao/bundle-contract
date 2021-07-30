// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IController {
    function getBundleMetadata(
        address bundle
    ) external view returns (
        address unbinder, 
        bool isInitialized, 
        bool isSetup, 
        uint256 lastUpdateTime
    );
}

// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@bundle-dao/pancakeswap-peripheral/contracts/interfaces/IPancakeRouter02.sol";
import "./IBundle.sol";

interface IUnbinder {
    struct SwapToken {
        bool flag;
        uint256 index;
    }

    event TokenUnbound(address token);

    event LogSwapWhitelist(
        address indexed caller,
        address         token,
        bool            flag
    );

    function initialize(address bundle, address router, address controller, address[] calldata whitelist) external;

    function handleUnboundToken(address token) external;

    function distributeUnboundToken(address token, uint256 amount, uint256 deadline, address[][] calldata paths) external;

    function setPremium(uint256 premium) external;

    function setSwapWhitelist(address token, bool flag) external;

    function getPremium() external view returns (uint256);

    function getController() external view returns (address);

    function getBundle() external view returns (address);

    function isSwapWhitelisted(address token) external view returns (bool);

    function getSwapWhitelist() external view returns (address[] memory);
}

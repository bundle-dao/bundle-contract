// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/BeaconProxy.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

contract BundleFactory is Ownable {
    /* ========== Storage ========== */

    address private _unbinderBeacon;
    address private _bundleBeacon;
    address private _controller;
    address private _rebalancer;

    /* ========== Modifiers ========== */

    modifier _control_() {
        require(msg.sender == _controller, "ERR_NOT_CONTROLLER");
        _;
    }

    /* ========== Initialization ========== */

    // Initialize factory with static beacon and proxy addresses
    constructor(
        address unbinderBeacon,
        address bundleBeacon,
        address rebalancer
    ) public {
        _unbinderBeacon = unbinderBeacon;
        _bundleBeacon = bundleBeacon;
        _rebalancer = rebalancer;
    }

    /* ========== Control ========== */

    function setController(address controller)
        external
        onlyOwner
    {
        _controller = controller;
    }

    /* ========== Deploy ========== */

    /** @dev This factory abstracts static implementation details
     *  for Bundle proxy contract deploys. It should not impelement 
     *  any initialization logic, but should ensure the controller 
     *  conforms to existing standards.
     *  
     *  @param name - used to compute salt for deploy
     *  @param symbol - used to compute salt for deploy   
     */
    function deploy(
        string calldata name,
        string calldata symbol
    )
        external
        _control_
        returns (address bundle, address unbinder)
    {
        // Compute salt as function of name and symbol
        bytes32 bundleSalt = keccak256(abi.encode(name, symbol));

        // Deploy uninitialized proxy
        // Factory should have limited knowledge about implementation
        bytes memory bundleBytecode = abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(_bundleBeacon));
        bundle = Create2.deploy(0, bundleSalt, bundleBytecode);

        // Compute salt as hash of bundle salt
        bytes32 unbinderSalt = keccak256(abi.encode(bundleSalt));

        // Deploy uninitialized unbinder
        bytes memory unbinderBytecode = abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(_unbinderBeacon));
        unbinder = Create2.deploy(0, unbinderSalt, unbinderBytecode);

        return (bundle, unbinder);
    }
}

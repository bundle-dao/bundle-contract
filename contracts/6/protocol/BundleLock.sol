// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IBundleLock.sol";

contract BundleLock is ERC20("L Bundle", "LBDL"), Ownable, IBundleLock {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /* ========== Storage ========== */

    address private _bundleToken;
    uint256 private _lock;

    mapping(address => uint256) private _bundleBalances;
    mapping(address => uint256) private _locks;

    uint256[] private _tiers;

    /* ========== Initialization ========== */

    constructor(address bundleToken, uint256 lock) 
        public 
    {
        _bundleToken = bundleToken;
        _lock = lock;
        _tiers.push(0);
    }

    /* ========== Getters ========== */

    function getLockThreshold(uint256 index) 
        external view override
        returns (uint256) 
    {
        require(index <= _tiers.length - 1, "ERR_OUT_OF_BOUNDS");
        return _tiers[index];
    }

    function getTier(address user)
        public view override
        returns (uint256)
    {
        for (uint256 i = 0; i < _tiers.length; i++) {
            if (_bundleBalances[user] >= _tiers[_tiers.length - 1 - i]) {
                return _tiers.length - 1 - i;
            }
        }
    }

    function getBundleBalance(address user)
        public view override
        returns (uint256)
    {
        return _bundleBalances[user];
    }

    function getLock(address user)
        public view override
        returns (uint256)
    {
        return _locks[user];
    }

    /* ========== Control ========== */

    function setLockThreshold(uint256 index, uint256 lockThreshold) 
        external override
        onlyOwner 
    {
        require(index != 0, "ERR_ZERO_TIER");
        require(index <= _tiers.length - 1, "ERR_OUT_OF_BOUNDS");
        _tiers[index] = lockThreshold;
    }

    // It is expected, but not required that lock thresholds are in ascending order
    function pushTier(uint256 lockThreshold) 
        external override
        onlyOwner
    {
        _tiers.push(lockThreshold);
    }

    function popTier()
        external override
        onlyOwner
    {
        require(_tiers.length > 1, "ERR_ZERO_TIER");
        _tiers.pop();
    }

    /* ========== User Interaction ========== */

    function deposit(uint256 amount)
        external override
    {
        IERC20(_bundleToken).safeTransferFrom(msg.sender, address(this), amount);
        _bundleBalances[msg.sender] = _bundleBalances[msg.sender].add(amount);
        _locks[msg.sender] = block.number.add(_lock);

        _mint(msg.sender, amount);
    }

    function withdraw(uint256 amount)
        external override
    {
        require(block.number > _locks[msg.sender], "ERR_LOCK");
        _burn(msg.sender, amount);
        _bundleBalances[msg.sender] = _bundleBalances[msg.sender].sub(amount);
        IERC20(_bundleToken).transfer(msg.sender, amount);
    }
}

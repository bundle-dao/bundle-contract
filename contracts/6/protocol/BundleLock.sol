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

    uint256 internal constant LOCK = 403200;

    address private _bundleToken;

    mapping(address => uint256) private _bundleBalances;
    mapping(address => uint256) private _locks;

    uint256[] private _tiers;

    constructor(address bundleToken) 
        public 
    {
        _bundleToken = bundleToken;
        _tiers.push(0);
    }

    function getLockThreshold(uint256 index) 
        external view override
        returns (uint256) 
    {
        return _tiers[index];
    }

    function setLockThreshold(uint256 index, uint256 lockThreshold) 
        external override
        onlyOwner 
    {
        require(index != 0, "ERR_ZERO_TIER");
        _tiers[index] = lockThreshold;
    }

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

    function deposit(uint256 amount)
        external override
    {
        uint256 startTier = getTier(msg.sender);
        IERC20(_bundleToken).safeTransferFrom(msg.sender, address(this), amount);
        _bundleBalances[msg.sender] = _bundleBalances[msg.sender].add(amount);
        uint256 endTier = getTier(msg.sender);

        if (endTier > startTier) {
            _locks[msg.sender] = block.number.add(LOCK);
        }

        _mint(msg.sender, amount);
    }

    function withdraw(uint256 amount)
        external override
    {
        if (block.number > _locks[msg.sender]) {
            _burn(msg.sender, amount);
            _bundleBalances[msg.sender] = _bundleBalances[msg.sender].sub(amount);
            IERC20(_bundleToken).transfer(msg.sender, amount);
        }
    }
}

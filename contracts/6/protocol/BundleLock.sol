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
    uint256 private _lockThreshold;

    mapping(address => uint256) private _bundleBalances;
    mapping(address => uint256) private _locks;

    constructor(address bundleToken, uint256 lockThreshold) 
        public 
    {
        _bundleToken = bundleToken;
        _lockThreshold = lockThreshold;
    }

    function getLockThreshold() 
        external view override
        returns (uint256) 
    {
        return _lockThreshold;
    }

    function setLockThreshold(uint256 lockThreshold) 
        external override
        onlyOwner 
    {
        _lockThreshold = lockThreshold;
    }

    function getApprovalState(address user)
        public view override
        returns (bool)
    {
        return (block.number > _locks[user] && _bundleBalances[user] > _lockThreshold);
    }

    function deposit(uint256 amount)
        external override
    {
        IERC20(_bundleToken).safeTransferFrom(msg.sender, address(this), amount);
        _bundleBalances[msg.sender] = _bundleBalances[msg.sender].add(amount);

        if (_bundleBalances[msg.sender] > _lockThreshold && _bundleBalances[msg.sender].sub(amount) < _lockThreshold) {
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
// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./interfaces/IMinterDetailed.sol";

contract Shield is Ownable {
  using SafeMath for uint256;

  IMinterDetailed public minter;

  uint256 public mintLimit = 10500000e18;
  uint256 public mintCount = 250000e18;

  event SetRewardsPerBlock(uint256 indexed _alpacaPerBlock);
  event SetBonus(uint256 _bonusMultiplier, uint256 _bonusEndBlock, uint256 _bonusLockUpBps);
  event MintWarchest(address indexed _to, uint256 _amount);
  event AddPool(uint256 indexed _pid, uint256 _allocPoint, address indexed _stakeToken);
  event SetPool(uint256 indexed _pid, uint256 _allocPoint);

  constructor(address _owner, IMinterDetailed _minter) public {
    transferOwnership(_owner);
    minter = _minter;
  }

  /// @dev Set BDL per Block on Minter. Effect immediately on the next block.
  /// @param _blockRewards The new alpacaPerBlock
  function setRewardsPerBlock(uint256 _blockRewards) external onlyOwner {
    minter.setRewardsPerBlock(_blockRewards);
    emit SetRewardsPerBlock(_blockRewards);
  }

  /// @dev Set Bonus period on Minter. This can't be used after lockup period.
  /// @param _bonusMultiplier New bonusMultiplier
  /// @param _bonusEndBlock The block that this bonus will be ended
  /// @param _bonusLockRatio The numerator of the lockup ratio
  function setBonus(uint256 _bonusMultiplier, uint256 _bonusEndBlock, uint256 _bonusLockRatio) external onlyOwner {
    minter.setBonus(_bonusMultiplier, _bonusEndBlock, _bonusLockRatio);
    emit SetBonus(_bonusMultiplier, _bonusEndBlock, _bonusLockRatio);
  }

  /// @dev Maunally mint BDL warchest portion.
  /// @param _to Mint to which address
  /// @param _amount Amount to be minted
  function mintWarchest(address _to, uint256 _amount) external onlyOwner {
    require(mintCount.add(_amount) <= mintLimit, "Shield::mintWarchest:: mint exceeded mintLimit");
    minter.manualMint(_to, _amount);
    mintCount = mintCount.add(_amount);
    emit MintWarchest(_to, _amount);
  }

  /// @dev Add new pool to Minter
  /// @param _allocPoint Allocation point of a new pool
  /// @param _stakeToken Token to be staked
  /// @param _withUpdate Mass update pool?
  function addPool(uint256 _allocPoint, address _stakeToken, bool _withUpdate) external onlyOwner {
    minter.addPool(_allocPoint, _stakeToken, _withUpdate);
    emit AddPool(minter.poolLength().sub(1), _allocPoint, _stakeToken);
  }

  /// @dev Set pool on Minter. Update pool allocation point
  /// @param _pid PoolId to be updated
  /// @param _allocPoint New allocPoint
  /// @param _withUpdate Mass update pool?
  function setPool(uint256 _pid, uint256 _allocPoint, bool _withUpdate) external onlyOwner {
    minter.setPool(_pid, _allocPoint, _withUpdate);
    emit SetPool(_pid, _allocPoint);
  }
}
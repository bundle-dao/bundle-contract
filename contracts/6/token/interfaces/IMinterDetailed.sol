// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IMinterDetailed {
  // Data structure
  struct UserInfo {
    uint256 amount;
    uint256 rewardDebt;
    uint256 bonusDebt;
  }
  struct PoolInfo {
    address stakeToken;
    uint256 allocPoint;
    uint256 lastRewardBlock;
    uint256 accRewardsPerShare;
    uint256 accRewardsPerShareTilBonusEnd;
  }

  // Information query functions
  function blockRewards() external view returns (uint256);
  function totalAllocPoint() external view returns (uint256);
  function poolInfo(uint256 pid) external view returns (IMinterDetailed.PoolInfo memory);
  function userInfo(uint256 pid, address user) external view returns (IMinterDetailed.UserInfo memory);
  function poolLength() external view returns (uint256);

  // OnlyOwner functions
  function setRewardsPerBlock(uint256 _blockRewards) external;
  function setBonus(uint256 _bonusMultiplier, uint256 _bonusEndBlock, uint256 _bonusLockRatio) external;
  function manualMint(address _to, uint256 _amount) external;
  function addPool(uint256 _allocPoint, address _stakeToken, bool _withUpdate) external;
  function setPool(uint256 _pid, uint256 _allocPoint, bool _withUpdate) external;

  // User's interaction functions
  function pendingRewards(uint256 _pid, address _user) external view returns (uint256);
  function updatePool(uint256 _pid) external;
  function deposit(uint256 _pid, uint256 _amount) external;
  function withdraw(uint256 _pid, uint256 _amount) external;
  function withdrawAll(uint256 _pid) external;
  function harvest(uint256 _pid) external;
}
// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./BundleToken.sol";
import "./interfaces/IMinter.sol";

// Minter is a smart contract for distributing BDL for staking rewards.
contract Minter is IMinter, Ownable, ReentrancyGuard {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  // Info of each user.
  struct UserInfo {
    uint256 amount; // How many Staking tokens the user has provided.
    uint256 rewardDebt; // Reward debt. See explanation below.
    uint256 bonusDebt; // Bonus reward debt.
    address fundedBy; // Funded by who?
    //
    // We do some fancy math here. Basically, any point in time, the amount of BDL
    // entitled to a user but is pending to be distributed is:
    //
    //   pending reward = (user.amount * pool.accRewardsPerShare) - user.rewardDebt
    //
    // Whenever a user deposits or withdraws Staking tokens to a pool. Here's what happens:
    //   1. The pool's `accRewardsPerShare` (and `lastRewardBlock`) gets updated.
    //   2. User receives the pending reward sent to his/her address.
    //   3. User's `amount` gets updated.
    //   4. User's `rewardDebt` gets updated.
  }

  // Info of each pool.
  struct PoolInfo {
    address stakeToken; // Address of Staking token contract.
    uint256 allocPoint; // How many allocation points assigned to this pool. BDL to distribute per block.
    uint256 lastRewardBlock; // Last block number that BDL distribution occurs.
    uint256 accRewardsPerShare; // Accumulated BDL per share, times 1e12. See below.
    uint256 accRewardsPerShareTilBonusEnd; // Accumated BDL per share until Bonus End.
  }

  // The Bundle TOKEN!
  BundleToken public bundle;
  // Dev address.
  address public devaddr;
  // Bundle tokens created per block.
  uint256 public blockRewards;
  // Bonus muliplier for early miners.
  uint256 public bonusMultiplier;
  // Block number when bonus BDL period ends.
  uint256 public bonusEndBlock;
  // Lock ratio over 10000 (for precision), determines how much BDL should be locked.
  uint256 public bonusLockRatio;
  // Dev minting rate, mint 1/10 of all rewards.
  uint256 private constant DEV_MINTING_RATE = 10;

  // Info of each pool.
  PoolInfo[] public poolInfo;
  // Info of each user that stakes Staking tokens.
  mapping(uint256 => mapping(address => UserInfo)) public userInfo;
  // Total allocation poitns. Must be the sum of all allocation points in all pools.
  uint256 public totalAllocPoint;
  // The block number when BUNDLE mining starts.
  uint256 public startBlock;

  event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
  event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
  event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

  constructor(
    BundleToken _bundle,
    address _devaddr,
    uint256 _blockRewards,
    uint256 _startBlock
  ) public {
    bonusMultiplier = 0;
    totalAllocPoint = 0;
    bonusEndBlock = 0;
    bundle = _bundle;
    devaddr = _devaddr;
    blockRewards = _blockRewards;
    startBlock = _startBlock;
  }

  // Update dev address by the previous dev.
  function setDev(address _devaddr) public {
    require(msg.sender == devaddr, "setDev: caller not dev");
    devaddr = _devaddr;
  }

  function setRewardsPerBlock(uint256 _blockRewards) external onlyOwner {
    blockRewards = _blockRewards;
  }

  // Set Bonus params. bonus will start to accu on the next block that this function executed
  // See the calculation and counting in test file.
  function setBonus(
    uint256 _bonusMultiplier,
    uint256 _bonusEndBlock,
    uint256 _bonusLockRatio
  ) external onlyOwner {
    require(_bonusEndBlock > block.number, "setBonus: bad bonusEndBlock");
    require(block.number < bundle.endReleaseBlock(), "setBonus: bad block");
    require(_bonusMultiplier > 1, "setBonus: bad bonusMultiplier");
    bonusMultiplier = _bonusMultiplier;
    bonusEndBlock = _bonusEndBlock;
    bonusLockRatio = _bonusLockRatio;
  }

  // Add a new lp to the pool. Can only be called by the owner.
  function addPool(
    uint256 _allocPoint,
    address _stakeToken,
    bool _withUpdate
  ) external override onlyOwner {
    if (_withUpdate) {
      massUpdatePools();
    }
    require(_stakeToken != address(0), "add: not stakeToken addr");
    require(!isDuplicatedPool(_stakeToken), "add: stakeToken dup");
    uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
    totalAllocPoint = totalAllocPoint.add(_allocPoint);
    poolInfo.push(
      PoolInfo({
        stakeToken: _stakeToken,
        allocPoint: _allocPoint,
        lastRewardBlock: lastRewardBlock,
        accRewardsPerShare: 0,
        accRewardsPerShareTilBonusEnd: 0
      })
    );
  }

  // Update the given pool's BDL allocation point. Can only be called by the owner.
  function setPool(
    uint256 _pid,
    uint256 _allocPoint,
    bool /* _withUpdate */
  ) external override onlyOwner {
    massUpdatePools();
    totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
    poolInfo[_pid].allocPoint = _allocPoint;
  }

  function isDuplicatedPool(address _stakeToken) public view returns (bool) {
    uint256 length = poolInfo.length;
    for (uint256 _pid = 0; _pid < length; _pid++) {
      if(poolInfo[_pid].stakeToken == _stakeToken) return true;
    }
    return false;
  }

  function poolLength() external override view returns (uint256) {
    return poolInfo.length;
  }

  function manualMint(address _to, uint256 _amount) external onlyOwner {
    bundle.manualMint(_to, _amount);
  }

  // Return reward multiplier over the given _from to _to block.
  // The product of multiplier and block rewards should give full period rewards
  function getMultiplier(uint256 _lastRewardBlock, uint256 _currentBlock) public view returns (uint256) {
    if (_currentBlock <= bonusEndBlock) {
      return _currentBlock.sub(_lastRewardBlock).mul(bonusMultiplier);
    }
    if (_lastRewardBlock >= bonusEndBlock) {
      return _currentBlock.sub(_lastRewardBlock);
    }
    // This is the case where bonusEndBlock is in the middle of _lastRewardBlock and _currentBlock block.
    return bonusEndBlock.sub(_lastRewardBlock).mul(bonusMultiplier).add(_currentBlock.sub(bonusEndBlock));
  }

  // View function to see pending BDL on frontend.
  function pendingRewards(uint256 _pid, address _user) external view override returns (uint256) {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_user];
    uint256 accRewardsPerShare = pool.accRewardsPerShare;
    uint256 lpSupply = IERC20(pool.stakeToken).balanceOf(address(this));
    if (block.number > pool.lastRewardBlock && lpSupply != 0) {
      uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
      uint256 reward = multiplier.mul(blockRewards).mul(pool.allocPoint).div(totalAllocPoint);
      accRewardsPerShare = accRewardsPerShare.add(reward.mul(1e12).div(lpSupply));
    }
    return user.amount.mul(accRewardsPerShare).div(1e12).sub(user.rewardDebt);
  }

  // Update reward vairables for all pools. Be careful of gas spending!
  function massUpdatePools() public {
    uint256 length = poolInfo.length;
    for (uint256 pid = 0; pid < length; ++pid) {
      updatePool(pid);
    }
  }

  // Update reward variables of the given pool to be up-to-date.
  function updatePool(uint256 _pid) public override {
    PoolInfo storage pool = poolInfo[_pid];
    if (block.number <= pool.lastRewardBlock) {
      return;
    }
    uint256 lpSupply = IERC20(pool.stakeToken).balanceOf(address(this));
    if (lpSupply == 0) {
      pool.lastRewardBlock = block.number;
      return;
    }
    uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
    uint256 reward = multiplier.mul(blockRewards).mul(pool.allocPoint).div(totalAllocPoint);
    bundle.mint(devaddr, reward.div(DEV_MINTING_RATE));
    bundle.mint(address(this), reward);
    pool.accRewardsPerShare = pool.accRewardsPerShare.add(reward.mul(1e12).div(lpSupply));
    // update accRewardsPerShareTilBonusEnd
    if (block.number <= bonusEndBlock) {
      // compute the bonus portion for dev
      bundle.lock(devaddr, reward.mul(bonusLockRatio).div(10000).div(DEV_MINTING_RATE));
      pool.accRewardsPerShareTilBonusEnd = pool.accRewardsPerShare;
    }
    if(block.number > bonusEndBlock && pool.lastRewardBlock < bonusEndBlock) {
      // compute the bonus portion for dev
      uint256 bonusPortion = bonusEndBlock.sub(pool.lastRewardBlock).mul(bonusMultiplier).mul(blockRewards).mul(pool.allocPoint).div(totalAllocPoint);
      bundle.lock(devaddr, bonusPortion.mul(bonusLockRatio).div(10000).div(DEV_MINTING_RATE));
      pool.accRewardsPerShareTilBonusEnd = pool.accRewardsPerShareTilBonusEnd.add(bonusPortion.mul(1e12).div(lpSupply));
    }
    pool.lastRewardBlock = block.number;
  }

  // Deposit Staking tokens to Minter for BDL allocation.
  function deposit(address _for, uint256 _pid, uint256 _amount) external override nonReentrant {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_for];
    if (user.fundedBy != address(0)) require(user.fundedBy == msg.sender, "bad sof");
    require(pool.stakeToken != address(0), "deposit: not accept deposit");
    updatePool(_pid);
    if (user.amount > 0) _harvest(_for, _pid);
    if (user.fundedBy == address(0)) user.fundedBy = msg.sender;
    IERC20(pool.stakeToken).safeTransferFrom(address(msg.sender), address(this), _amount);
    user.amount = user.amount.add(_amount);
    user.rewardDebt = user.amount.mul(pool.accRewardsPerShare).div(1e12);
    user.bonusDebt = user.amount.mul(pool.accRewardsPerShareTilBonusEnd).div(1e12);
    emit Deposit(msg.sender, _pid, _amount);
  }

  // Withdraw Staking tokens from FairLaunchToken.
  function withdraw(address _for, uint256 _pid, uint256 _amount) external override nonReentrant {
    _withdraw(_for, _pid, _amount);
  }

  function withdrawAll(address _for, uint256 _pid) external override nonReentrant {
    _withdraw(_for, _pid, userInfo[_pid][_for].amount);
  }

  function _withdraw(address _for, uint256 _pid, uint256 _amount) internal {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_for];
    require(user.fundedBy == msg.sender, "only funder");
    require(user.amount >= _amount, "withdraw: not good");
    updatePool(_pid);
    _harvest(_for, _pid);
    user.amount = user.amount.sub(_amount);
    user.rewardDebt = user.amount.mul(pool.accRewardsPerShare).div(1e12);
    user.bonusDebt = user.amount.mul(pool.accRewardsPerShareTilBonusEnd).div(1e12);
    if (user.amount == 0) user.fundedBy = address(0);
    if (pool.stakeToken != address(0)) {
      IERC20(pool.stakeToken).safeTransfer(address(msg.sender), _amount);
    }
    emit Withdraw(msg.sender, _pid, user.amount);
  }

  // Harvest BDL earn from the pool.
  function harvest(uint256 _pid) external override nonReentrant {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    updatePool(_pid);
    _harvest(msg.sender, _pid);
    user.rewardDebt = user.amount.mul(pool.accRewardsPerShare).div(1e12);
    user.bonusDebt = user.amount.mul(pool.accRewardsPerShareTilBonusEnd).div(1e12);
  }

  function _harvest(address _to, uint256 _pid) internal {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][_to];
    require(user.amount > 0, "nothing to harvest");
    uint256 pending = user.amount.mul(pool.accRewardsPerShare).div(1e12).sub(user.rewardDebt);
    require(pending <= bundle.balanceOf(address(this)), "not enough BDL");
    uint256 bonus = user.amount.mul(pool.accRewardsPerShareTilBonusEnd).div(1e12).sub(user.bonusDebt);
    safeBundleTransfer(_to, pending);
    bundle.lock(_to, bonus.mul(bonusLockRatio).div(10000));
  }

  // Withdraw without caring about rewards. EMERGENCY ONLY.
  function emergencyWithdraw(uint256 _pid) external nonReentrant {
    PoolInfo storage pool = poolInfo[_pid];
    UserInfo storage user = userInfo[_pid][msg.sender];
    require(user.fundedBy == msg.sender, "only funder");
    IERC20(pool.stakeToken).safeTransfer(address(msg.sender), user.amount);
    emit EmergencyWithdraw(msg.sender, _pid, user.amount);
    user.amount = 0;
    user.rewardDebt = 0;
    user.fundedBy = address(0);
  }

    // Safe bundle transfer function, just in case if rounding error causes pool to not have enough BDL.
  function safeBundleTransfer(address _to, uint256 _amount) internal {
    uint256 bundleBal = bundle.balanceOf(address(this));
    if (_amount > bundleBal) {
      require(bundle.transfer(_to, bundleBal), "failed to transfer BDL");
    } else {
      require(bundle.transfer(_to, _amount), "failed to transfer BDL");
    }
  }
}

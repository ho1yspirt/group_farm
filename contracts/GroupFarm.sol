// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * GroupFarm - one shared farm for three fixed Uniswap v2 LP tokens.
 * Reward token: GROUP1 (same for all pools).
 *
 * - Each pool gets rewardPerPool GROUP1 spread evenly over `duration` seconds.
 * - Rewards are shared by staked LP amount and time (reward-per-share accumulator,
 *   no loops over users).
 * - While a pool is empty its time budget is NOT given to later stakers.
 * - Owner can only call startSession() (once, after full funding).
 *   There is NO function for the owner to take LP tokens or rewards.
 */
contract GroupFarm is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant PRECISION = 1e18;
    uint256 public constant POOL_COUNT = 3;

    struct Pool {
        IERC20 lpToken;
        uint256 totalStaked;       // staked principal (LP) - accounted separately from rewards
        uint256 accRewardPerShare; // scaled by PRECISION
        uint256 lastUpdate;        // last accounting timestamp (<= endTime)
    }

    struct User {
        uint256 staked;
        uint256 paidAcc;  // accRewardPerShare already booked for this user
        uint256 rewards;  // booked, not yet claimed
    }

    IERC20 public immutable rewardToken;
    uint256 public immutable duration;      // seconds (e.g. 120 minutes = 7200)
    uint256 public immutable rewardPerPool; // GROUP1 (wei) per pool for the whole session

    uint256 public startTime;
    uint256 public endTime;
    bool public started;

    uint256 public totalRewardsClaimed; // reward ledger (separate from LP principal)

    Pool[POOL_COUNT] public pools;
    mapping(uint256 => mapping(address => User)) public users;

    event SessionStarted(uint256 startTime, uint256 endTime, uint256 totalReward);
    event Staked(address indexed user, uint256 indexed poolId, uint256 amount);
    event Withdrawn(address indexed user, uint256 indexed poolId, uint256 amount);
    event Claimed(address indexed user, uint256 indexed poolId, uint256 amount);

    error InvalidPool();
    error ZeroAmount();
    error AlreadyStarted();
    error NotFunded();
    error InsufficientStake();
    error BadConfig();

    constructor(
        address rewardToken_,
        address[3] memory lpTokens_,
        uint256 duration_,
        uint256 rewardPerPool_
    ) Ownable(msg.sender) {
        if (rewardToken_ == address(0) || duration_ == 0 || rewardPerPool_ == 0) revert BadConfig();
        rewardToken = IERC20(rewardToken_);
        duration = duration_;
        rewardPerPool = rewardPerPool_;

        for (uint256 i = 0; i < POOL_COUNT; i++) {
            address lp = lpTokens_[i];
            if (lp == address(0) || lp == rewardToken_) revert BadConfig();
            for (uint256 j = 0; j < i; j++) {
                if (lpTokens_[j] == lp) revert BadConfig();
            }
            pools[i].lpToken = IERC20(lp);
        }
    }

    // ---------------------------------------------------------------- admin

    /// Total rewards that must be held by the contract before start.
    function totalReward() public view returns (uint256) {
        return rewardPerPool * POOL_COUNT;
    }

    /// Can be called once, only after the farm holds the full reward budget.
    function startSession() external onlyOwner {
        if (started) revert AlreadyStarted();
        if (rewardToken.balanceOf(address(this)) < totalReward()) revert NotFunded();

        started = true;
        startTime = block.timestamp;
        endTime = block.timestamp + duration;
        for (uint256 i = 0; i < POOL_COUNT; i++) {
            pools[i].lastUpdate = block.timestamp;
        }
        emit SessionStarted(startTime, endTime, totalReward());
    }

    // ---------------------------------------------------------------- user actions

    function stake(uint256 poolId, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _book(poolId, msg.sender); // book earned so far BEFORE changing the stake
        Pool storage p = pools[poolId];
        User storage u = users[poolId][msg.sender];

        // balance-difference check keeps accounting exact even for odd tokens
        uint256 before = p.lpToken.balanceOf(address(this));
        p.lpToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = p.lpToken.balanceOf(address(this)) - before;

        u.staked += received;
        p.totalStaked += received;
        emit Staked(msg.sender, poolId, received);
    }

    function withdraw(uint256 poolId, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        _book(poolId, msg.sender); // book earned so far BEFORE changing the stake
        Pool storage p = pools[poolId];
        User storage u = users[poolId][msg.sender];
        if (amount > u.staked) revert InsufficientStake();

        u.staked -= amount;
        p.totalStaked -= amount;
        p.lpToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, poolId, amount);
    }

    function claim(uint256 poolId) external nonReentrant {
        _book(poolId, msg.sender);
        _pay(poolId, msg.sender);
    }

    function claimAll() external nonReentrant {
        for (uint256 i = 0; i < POOL_COUNT; i++) {
            _book(i, msg.sender);
            _pay(i, msg.sender);
        }
    }

    // ---------------------------------------------------------------- views

    /// Unclaimed GROUP1 for `account` in pool `poolId` (including not yet booked part).
    function earned(address account, uint256 poolId) public view returns (uint256) {
        if (poolId >= POOL_COUNT) revert InvalidPool();
        User storage u = users[poolId][account];
        return u.rewards + (u.staked * (_currentAcc(poolId) - u.paidAcc)) / PRECISION;
    }

    function earnedAll(address account) external view returns (uint256 sum) {
        for (uint256 i = 0; i < POOL_COUNT; i++) sum += earned(account, i);
    }

    function timeLeft() external view returns (uint256) {
        if (!started || block.timestamp >= endTime) return 0;
        return endTime - block.timestamp;
    }

    function lpTokenOf(uint256 poolId) external view returns (address) {
        if (poolId >= POOL_COUNT) revert InvalidPool();
        return address(pools[poolId].lpToken);
    }

    function totalStakedOf(uint256 poolId) external view returns (uint256) {
        if (poolId >= POOL_COUNT) revert InvalidPool();
        return pools[poolId].totalStaked;
    }

    function stakedOf(address account, uint256 poolId) external view returns (uint256) {
        if (poolId >= POOL_COUNT) revert InvalidPool();
        return users[poolId][account].staked;
    }

    // ---------------------------------------------------------------- internals

    /// accRewardPerShare as it would be right now (view helper).
    function _currentAcc(uint256 poolId) internal view returns (uint256 acc) {
        Pool storage p = pools[poolId];
        acc = p.accRewardPerShare;
        if (!started || p.totalStaked == 0) return acc;
        uint256 t = block.timestamp < endTime ? block.timestamp : endTime;
        if (t > p.lastUpdate) {
            // elapsed * (rewardPerPool / duration) / totalStaked, rounded down
            acc += ((t - p.lastUpdate) * rewardPerPool * PRECISION) / (duration * p.totalStaked);
        }
    }

    /// Updates the pool accumulator and books the user's earnings into u.rewards.
    function _book(uint256 poolId, address account) internal {
        if (poolId >= POOL_COUNT) revert InvalidPool();
        Pool storage p = pools[poolId];

        if (started) {
            uint256 t = block.timestamp < endTime ? block.timestamp : endTime;
            if (t > p.lastUpdate) {
                if (p.totalStaked > 0) {
                    p.accRewardPerShare = _currentAcc(poolId);
                }
                // empty pool: that time slice is simply skipped (not given to later stakers)
                p.lastUpdate = t;
            }
        }

        User storage u = users[poolId][account];
        u.rewards += (u.staked * (p.accRewardPerShare - u.paidAcc)) / PRECISION;
        u.paidAcc = p.accRewardPerShare;
    }

    function _pay(uint256 poolId, address account) internal {
        User storage u = users[poolId][account];
        uint256 amount = u.rewards;
        if (amount == 0) return;
        u.rewards = 0; // zero before transfer: cannot be claimed twice
        totalRewardsClaimed += amount;
        rewardToken.safeTransfer(account, amount);
        emit Claimed(account, poolId, amount);
    }
}

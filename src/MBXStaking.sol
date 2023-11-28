// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./MBXUtils.sol";
import "./interfaces/IERC20Lite.sol";
import "solmate/utils/ReentrancyGuard.sol";
import "./MBXRewardLibrary.sol";

contract StakingContract is ReentrancyGuard {
    /// @dev address which receives early unstake dev fees
    address public immutable devWallet;
    /// @dev address which is allowed to make state changes (ie: create staking pools)
    address public immutable owner;
    /// @dev tracks the identifier of the next staking pool created
    uint256 public nextPoolId;

    /// @dev named parameters for referencing staking tiers to minimize errors
    enum StakingTier
    // represents a staking tier that locks up for 15 days
    {
        Fifteen,
        // represents a staking tier that locks up for 30 days
        Thirty,
        // represents a staking tier that locks up for 60 days
        Sixty
    }

    /// @dev identifies a staking pool for a specific tier
    struct StakingPool {
        /// @dev the amount of tokens staked in this tier
        uint256 totalStaked;
        /// @dev the reward rate of tokens emitted in this tier
        uint256 rewardRate;
        /// @dev the time at which reward data was last updated
        uint256 lastUpdateTime;
        /// @dev the amount of reward tokens per staked token
        uint256 rewardPerTokenStored;
        /// @dev the tier that this staking pool represents
        StakingTier tier;
    }

    /// @dev allows staking a stakingToken in exchange for a rewardToken, with three available staking tiers
    /// @dev a depositor is only allowed to deposit into one tier
    struct StakingPools {
        /// @dev the identifier of the staking pool
        uint256 poolId;
        /// @dev the time at which the staking pool opens up
        uint256 startTime;
        /// @dev the time at which reward emission ends for this pool
        uint256 endTime;
        /// @dev the three available staking tiers
        StakingPool[3] pools;
        /// @dev ierc20 interface for the staking token
        IERC20 stakingToken;
        /// @dev ierc20 interface for the reward token
        IERC20 rewardToken;
    }

    /// @dev tracks deposit information for a tier + account + staking pool
    struct StakingPoolDeposit {
        /// @dev reward tracking data
        uint256 userRewardPerTokenPaid;
        /// @dev the amount of token staked by the user
        uint256 stakedAmount;
        /// @dev the pending rewards to be claimed
        uint256 rewards;
        /// @dev the time at which unstaking is permitted
        uint256 unlockTime;
        /// @dev the tier the user is staked in
        StakingTier tier;
        /// @dev indicates of the account is initialized and has received a first deposit
        bool initialized;
    }

    /// maps id => staking pool
    mapping(uint256 => StakingPools) public stakingPools;
    /// maps id => staking pool deposit, limited to one per pool
    mapping(uint256 => mapping(address => StakingPoolDeposit)) public deposits;

    event Staked(address _user, uint256 _poolId, uint256 _amount, uint256 _unlockTime, StakingTier _tier);

    event Unstaked(address _user, uint256 _poolId, uint256 _amount);

    event EarlyUnstake(address _user, uint256 _poolId, uint256 _devFee, uint256 _burnFee, uint256 _withdrawn);

    event RewardPaid(address _user, uint256 _poolId, uint256 _reward);

    constructor(address _devWallet, address _owner) {
        devWallet = _devWallet;
        owner = _owner;
    }

    /// @dev creates a new staking pool accepting _stakingToken in exchange for _rewardToken
    /// @notice the same reward and staking token is used for all three available staking tiers
    /// @param _rewardParameters contains the reward configuration for all three tiers
    /// @param _tiers ordering of tiers is expected to be [Fifteen, Thirty, Sixty]
    /// @param _timespan the start and end time of token emissions for each tier
    /// @param _stakingToken is the ERC20 token address that must be staked
    /// @param _rewardToken is the ERC20 token address that is given as rewards
    function newStakePool(
        MBXUtils.RewardParameters[3] calldata _rewardParameters,
        StakingTier[3] calldata _tiers,
        MBXUtils.TimeSpan calldata _timespan,
        address _stakingToken,
        address _rewardToken
    ) public {
        require(msg.sender == owner);
        StakingPool[3] memory pools;
        require(
            _tiers[0] == StakingTier.Fifteen && _tiers[1] == StakingTier.Thirty && _tiers[2] == StakingTier.Sixty,
            "invalid_tier_order"
        );
        pools[0] = StakingPool({
            totalStaked: 0,
            rewardRate: MBXUtils.computeRewardRate(
                _rewardParameters[0].rewardsToEmit, _rewardParameters[0].rewardDurationSeconds
                ),
            lastUpdateTime: block.timestamp,
            rewardPerTokenStored: 0,
            tier: _tiers[0]
        });
        pools[1] = StakingPool({
            totalStaked: 0,
            rewardRate: MBXUtils.computeRewardRate(
                _rewardParameters[1].rewardsToEmit, _rewardParameters[1].rewardDurationSeconds
                ),
            lastUpdateTime: block.timestamp,
            rewardPerTokenStored: 0,
            tier: _tiers[1]
        });

        pools[2] = StakingPool({
            totalStaked: 0,
            rewardRate: MBXUtils.computeRewardRate(
                _rewardParameters[2].rewardsToEmit, _rewardParameters[2].rewardDurationSeconds
                ),
            lastUpdateTime: block.timestamp,
            rewardPerTokenStored: 0,
            tier: _tiers[2]
        });
        StakingPools memory pool = StakingPools({
            poolId: nextPoolId,
            startTime: _timespan.start,
            endTime: _timespan.end,
            pools: pools,
            stakingToken: IERC20(_stakingToken),
            rewardToken: IERC20(_rewardToken)
        });

        stakingPools[nextPoolId] = pool;

        nextPoolId += 1;
    }

    /// @notice stakes `_amount` of the staking token used by staking pool `_poolId` into staking tier `_tier`
    /// @notice the same _tier must be specified on subsequent deposits as was used in the initial deposit
    /// @notice depositing refreshes a pre-existing unlock time for the staking duration of the tier
    /// @param _poolId identifier of an existing pool id
    /// @param _amount is the amount of staking tokens to stake, it must be greater than 100 wei
    /// @param _tier is the staking tier to deposit into, and is set the first time msg.sender deposits into the staking pool
    function stake(uint256 _poolId, uint256 _amount, StakingTier _tier) external nonReentrant {
        require(_amount > 100, "min_balance");
        StakingPoolDeposit memory deposit = deposits[_poolId][msg.sender];
        
        // initialize deposit tier before proceeding
        if (!deposit.initialized) {
            deposit.initialized = true;
            deposit.tier = _tier;
            // persist updates before calling updateReward
            deposits[_poolId][msg.sender] = deposit;
        } else {
            require(deposit.tier == _tier, "invalid_tier");
        }

        // update reward data
        updateReward(_poolId, msg.sender);

        StakingPools memory pool = stakingPools[_poolId];

        require(block.timestamp >= pool.startTime, "not_started");

        // load deposit data
        deposit = deposits[_poolId][msg.sender];

        // increment unlock time
        deposit.unlockTime = addDays(block.timestamp, _tier);
        // increment staked amount
        deposit.stakedAmount += _amount;
        // update total staked
        pool.pools[getIndex(_tier)].totalStaked += _amount;

        // persist changes
        stakingPools[_poolId] = pool;
        deposits[_poolId][msg.sender] = deposit;

        // transfer tokens
        pool.stakingToken.transferFrom(msg.sender, address(this), _amount);

        emit Staked(msg.sender, _poolId, _amount, deposit.unlockTime, _tier);
    }

    /// @notice unstakes _amount of tokens from staking pool _poolId
    /// @notice can only be called after the unlock time expires
    /// @param _poolId identifier of the staking pool to unstake from
    /// @param _amount non zero amount of tokens to unstake
    function unstake(uint256 _poolId, uint256 _amount) external nonReentrant {
        require(_amount > 0);

        // update reward data and claim pending rewards
        updateReward(_poolId, msg.sender);
        _claimReward(_poolId);

        StakingPools memory pool = stakingPools[_poolId];
        StakingPoolDeposit memory deposit = deposits[_poolId][msg.sender];

        require(block.timestamp >= deposit.unlockTime, "not_unlocked");
        require(deposit.initialized, "not_initialized");

        // reduce balances
        pool.pools[getIndex(deposit.tier)].totalStaked -= _amount;
        deposit.stakedAmount -= _amount;

        // persist updates
        stakingPools[_poolId] = pool;
        deposits[_poolId][msg.sender] = deposit;

        // transfer tokens
        pool.stakingToken.transfer(msg.sender, _amount);

        emit Unstaked(msg.sender, _poolId, _amount);
    }

    /// @notice allows unstaking the full balance staked into pool _poolId while penalizing msg.sender for 20% of their deposit
    /// @notice can be called as early as 900 seconds after the last deposit time
    /// @dev to view the early unstake penalty consule MBXUtils
    function earlyUnstake(uint256 _poolId) external nonReentrant {
        // update pools
        updateReward(_poolId, msg.sender);
        _claimReward(_poolId);

        StakingPools memory pool = stakingPools[_poolId];
        StakingPoolDeposit memory deposit = deposits[_poolId][msg.sender];

        // require that the pool has already started
        require(block.timestamp >= pool.startTime + 900);
        require(
            // ensure that the current block timestamp is at least 900 seconds
            // greater than the last deposit time. we calculate this by subtracting
            // the stake lock time from their unlock time
            block.timestamp >= (deposit.unlockTime - ((getDays(deposit.tier) * 86400))) + 900,
            "min_time"
        );
        require(deposit.stakedAmount > 0, "cannot unstake 0");
        require(deposit.initialized, "not initialized");

        MBXUtils.UnstakePenalty memory unstakePenalty =
            MBXUtils.calculateUnstakePenalty(deposit.stakedAmount, pool.stakingToken.decimals());

        // the total penalty to deduct from their withdrawable amount
        uint256 totalPenalty = MBXUtils.totalPenaltyFee(unstakePenalty);
        // the amount they can withdraw
        uint256 withdrawAmount = deposit.stakedAmount - totalPenalty;
        // validate the balances match up
        require(totalPenalty + withdrawAmount == deposit.stakedAmount, "invalid_penalty_calculation");

        // reduce balances
        pool.pools[getIndex(deposit.tier)].totalStaked -= deposit.stakedAmount;
        deposit.stakedAmount = 0;

        // persist updates
        stakingPools[_poolId] = pool;
        deposits[_poolId][msg.sender] = deposit;

        // transfer the withdrawable amount to caller
        pool.stakingToken.transfer(msg.sender, withdrawAmount);
        // transfer dev fee to dev wallet
        pool.stakingToken.transfer(devWallet, unstakePenalty.devFee);
        // burn the rest
        pool.stakingToken.transfer(address(0), unstakePenalty.burnAmount);

        emit EarlyUnstake(msg.sender, _poolId, unstakePenalty.devFee, unstakePenalty.burnAmount, withdrawAmount);
    }

    /// @notice used to update reward data for pool _poolId and claim any tokens the depositor has earned as rewards
    /// @param _poolId the identifier of the pool
    function claimReward(uint256 _poolId) external nonReentrant {
        updateReward(_poolId, msg.sender);
        _claimReward(_poolId);
    }

    /// @dev returns a memory reference to a user's staked capital in the specified pool
    /// @param _poolId the identifier of the staking pool
    /// @param _account the account of the staker to lookup
    function getUserStake(uint256 _poolId, address _account) public view returns (StakingPoolDeposit memory) {
        return deposits[_poolId][_account];
    }

    /// @dev returns a memory reference to the staking pool identified by the supplied id
    /// @param _poolId the staking pool to query
    function getStakingPool(uint256 _poolId) public view returns (StakingPools memory) {
        return stakingPools[_poolId];
    }

    /// @dev helper function to add the number of days a tier locksup for to the specified timestmap
    /// @param _timestamp the unix timestamp to add days too
    /// @param _tier the staking tier to use for date calculation
    function addDays(uint256 _timestamp, StakingTier _tier) public pure returns (uint256) {
        return MBXUtils.addDays(_timestamp, getDays(_tier));
    }

    /// @notice returns the amount of pending rewards earned by _account in pool _poolId
    /// @param _poolId the identifier of the staking pool
    /// @param _account the account of the staker to lookup
    function earned(uint256 _poolId, address _account) public view returns (uint256) {
        StakingPools memory pool = stakingPools[_poolId];
        StakingPoolDeposit memory deposit = deposits[_poolId][_account];
        uint256 index = getIndex(deposit.tier);
        return MBXReward.earned(
            MBXReward.RewardData({
                rewardRate: pool.pools[index].rewardRate,
                lastUpdateTime: pool.pools[index].lastUpdateTime,
                rewardPerTokenStored: pool.pools[index].rewardPerTokenStored,
                periodFinish: pool.endTime
            }),
            MBXReward.UserRewardData({userRewardPerTokenPaid: deposit.userRewardPerTokenPaid, rewards: deposit.rewards}),
            deposit.stakedAmount
        );
    }

    /// @dev used to update reward data for the staking tier the user account is deposited into, and for the account
    /// @param _poolId the identifier of the staking pool to update rewards for, limiting the update to the tier the caller is deposited into
    /// @param _account the address of the account to update rewards for
    function updateReward(uint256 _poolId, address _account) internal {
        StakingPools memory pool = stakingPools[_poolId];
        StakingPoolDeposit memory deposit = deposits[_poolId][_account];

        uint256 index = getIndex(deposit.tier);

        (MBXReward.RewardData memory poolRewards, MBXReward.UserRewardData memory userRewards) = MBXReward.updateReward(
            MBXReward.RewardData({
                rewardRate: pool.pools[index].rewardRate,
                lastUpdateTime: pool.pools[index].lastUpdateTime,
                rewardPerTokenStored: pool.pools[index].rewardPerTokenStored,
                periodFinish: pool.endTime
            }),
            MBXReward.UserRewardData({userRewardPerTokenPaid: deposit.userRewardPerTokenPaid, rewards: deposit.rewards}),
            pool.pools[index].totalStaked,
            deposit.stakedAmount
        );

        pool.pools[index].rewardPerTokenStored = poolRewards.rewardPerTokenStored;
        pool.pools[index].lastUpdateTime = poolRewards.lastUpdateTime;

        deposit.rewards = userRewards.rewards;
        deposit.userRewardPerTokenPaid = userRewards.userRewardPerTokenPaid;

        deposits[_poolId][_account] = deposit;
        stakingPools[_poolId] = pool;
    }

    /// @dev this is an internal function and should be used with caution
    /// @notice caller must update rewards before invoking this function
    /// @param _poolId the staking pool to claim rewards for
    function _claimReward(uint256 _poolId) internal {
        uint256 reward = deposits[_poolId][msg.sender].rewards;
        if (reward > 0) {
            deposits[_poolId][msg.sender].rewards = 0;
            stakingPools[_poolId].rewardToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, _poolId, reward);
        }
    }

    /// @dev returns the number of days a tier locks tokens for
    /// @param _tier the staking tier to lookup
    function getDays(StakingTier _tier) internal pure returns (uint256) {
        if (_tier == StakingTier.Fifteen) {
            return 15;
        } else if (_tier == StakingTier.Thirty) {
            return 30;
        } else if (_tier == StakingTier.Sixty) {
            return 60;
        } else {
            revert(":uhohstinky:");
        }
    }

    /// @dev returns the index used to lookup staking information for this tier within the staking pool
    /// @param _tier the staking tier to lookup
    function getIndex(StakingTier _tier) internal pure returns (uint256) {
        if (_tier == StakingTier.Fifteen) {
            return 0;
        } else if (_tier == StakingTier.Thirty) {
            return 1;
        } else if (_tier == StakingTier.Sixty) {
            return 2;
        } else {
            revert(":uhohstinky:");
        }
    }
}

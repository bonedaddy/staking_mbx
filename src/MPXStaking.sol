// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./MPXUtils.sol";
import "./interfaces/IERC20Lite.sol";
import "solmate/utils/ReentrancyGuard.sol";
import "./MPXRewardLibrary.sol";


contract StakingContract is ReentrancyGuard {
    address public immutable devWallet;
    address public immutable owner;
    uint256 public nextPoolId;

    enum StakingTier {
        Fifteen,
        Thirty,
        Sixty
    } 

    struct StakingPool {
        uint256 totalStaked;
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        uint256 rewardsToEmit;
        uint256 rewardsPaid;
        StakingTier tier;
    }

    struct StakingPools {
        uint256 poolId;
        uint256 startTime;
        uint256 endTime;
        StakingPool[3] pools;
        IERC20 stakingToken;
        IERC20 rewardToken;
    }

    struct StakingPoolDeposit {
        uint256 userRewardPerTokenPaid;
        uint256 stakedAmount;
        uint256 rewards;
        uint256 unlockTime;
        StakingTier tier;
        bool initialized;
    }

    /// maps id => staking pool
    mapping (uint256 => StakingPools) public stakingPools;
    /// maps id => staking pool deposit, limited to one per pool
    mapping (uint256 => mapping(address => StakingPoolDeposit)) public deposits;

    event Staked(
        address _user,
        uint256 _poolId,
        uint256 _amount,
        uint256 _unlockTime,
        StakingTier _tier
    );

    event Unstaked(
        address _user,
        uint256 _poolId,
        uint256 _amount
    );

    event EarlyUnstake(
        address _user,
        uint256 _poolId,
        uint256 _devFee,
        uint256 _burnFee,
        uint256 _withdrawn
    );

    event RewardPaid(
        address _user,
        uint256 _poolId,
        uint256 _reward
    );

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
        MPXUtils.RewardParameters[3] calldata _rewardParameters,
        StakingTier[3] calldata _tiers,
        MPXUtils.TimeSpan calldata _timespan,
        address _stakingToken,
        address _rewardToken
    ) public {
        require(msg.sender == owner);
        StakingPool[3] memory pools;
        require(
            _tiers[0] == StakingTier.Fifteen &&
            _tiers[1] == StakingTier.Thirty &&
            _tiers[2] == StakingTier.Sixty,
            "invalid_tier_order"
        );
        pools[0] = StakingPool({
            totalStaked: 0,
            rewardRate: MPXUtils.computeRewardRate(
                _rewardParameters[0].rewardsToEmit,
                _rewardParameters[0].rewardDurationSeconds
            ),
            lastUpdateTime: block.timestamp,
            rewardPerTokenStored: 0,
            rewardsToEmit: _rewardParameters[0].rewardsToEmit,
            rewardsPaid: 0,
            tier: _tiers[0]
        });
        pools[1] = StakingPool({
            totalStaked: 0,
            rewardRate: MPXUtils.computeRewardRate(
                _rewardParameters[1].rewardsToEmit,
                _rewardParameters[1].rewardDurationSeconds
            ),
            lastUpdateTime: block.timestamp,
            rewardPerTokenStored: 0,
            rewardsToEmit: _rewardParameters[1].rewardsToEmit,
            rewardsPaid: 0,
            tier: _tiers[1]
        });

        pools[2] = StakingPool({
            totalStaked: 0,
            rewardRate: MPXUtils.computeRewardRate(
                _rewardParameters[2].rewardsToEmit,
                _rewardParameters[2].rewardDurationSeconds
            ),
            lastUpdateTime: block.timestamp,
            rewardPerTokenStored: 0,
            rewardsToEmit: _rewardParameters[2].rewardsToEmit,
            rewardsPaid: 0,
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

    /// @notice requires staking a minimum of 100 wei of the staking token 
    function stake(uint256 _poolId, uint256 _amount, StakingTier _tier) external nonReentrant() {
        require(_amount > 100);

        // initialize deposit tier before proceeding
        if (!isDepositInitialized(_poolId, msg.sender)) {
            deposits[_poolId][msg.sender].initialized = true;
            deposits[_poolId][msg.sender].tier = _tier;
        } else {
            require(deposits[_poolId][msg.sender].tier == _tier, "invalid_tier");
        }

        // update reward data
        updateReward(_poolId, msg.sender);


        StakingPools memory pool = stakingPools[_poolId];
        StakingPoolDeposit memory deposit = deposits[_poolId][msg.sender];

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

        emit Staked(
            msg.sender,
            _poolId,
            _amount,
            deposit.unlockTime,
            _tier
        );
    }

    function unstake(uint256 _poolId, uint256 _amount) external nonReentrant() {
        require(_amount > 0);

        // update pools
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

    function earlyUnstake(uint256 _poolId) external nonReentrant() {

        // update pools
        updateReward(_poolId, msg.sender);
        _claimReward(_poolId);

        StakingPools memory pool = stakingPools[_poolId];
        StakingPoolDeposit memory deposit = deposits[_poolId][msg.sender];

        require(block.timestamp >= pool.startTime);
        require(deposit.stakedAmount > 0, "cannot unstake 0");
        require(deposit.initialized, "not initialized");

        MPXUtils.UnstakePenalty memory unstakePenalty =
            MPXUtils.calculateUnstakePenalty(deposit.stakedAmount, pool.stakingToken.decimals());

        // the total penalty to deduct from their withdrawable amount
        uint256 totalPenalty = MPXUtils.totalPenaltyFee(unstakePenalty);
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

        emit EarlyUnstake(
            msg.sender,
            _poolId,
            unstakePenalty.devFee,
            unstakePenalty.burnAmount,
            withdrawAmount
        );
    }

    function claimReward(uint256 _poolId) external nonReentrant() {
        updateReward(_poolId, msg.sender);
        _claimReward(_poolId);
    }

    /// @dev returns a memory reference to a user's staked capital in the specified pool
    function getUserStake(uint256 _poolId, address _account) public view returns (StakingPoolDeposit memory) {
        return deposits[_poolId][_account];
    }

    /// @dev returns a memory reference to the staking pool identified by the supplied id
    function getStakingPool(uint256 _poolId) public view returns (StakingPools memory) {
        return stakingPools[_poolId];
    }

        /// @dev helper function to add the number of days a tier locksup for to the specified timaestamp
    function addDays(uint256 _timestamp, StakingTier _tier) public pure returns (uint256) {
        return MPXUtils.addDays(_timestamp, getDays(_tier));
    }

    /// @dev returns the number of days a tier locks tokens for
    function getDays(StakingTier _tier) public pure returns (uint256) {
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

    function getIndex(StakingTier _tier) public pure returns (uint256) {
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

    function earned(uint256 _poolId, address _account) public view returns (uint256) {
        StakingPools memory pool = stakingPools[_poolId];
        StakingPoolDeposit memory deposit = deposits[_poolId][_account];
        uint256 index = getIndex(deposit.tier);
        return MPXReward.earned(
            MPXReward.RewardData({
                rewardRate: pool.pools[index].rewardRate,
                lastUpdateTime: pool.pools[index].lastUpdateTime,
                rewardPerTokenStored: pool.pools[index].rewardPerTokenStored,
                periodFinish: pool.endTime
            }),
            MPXReward.UserRewardData({
                userRewardPerTokenPaid: deposit.userRewardPerTokenPaid,
                rewards: deposit.rewards
            }),
            deposit.stakedAmount
        );
    }
    /// @dev returns if the deposit is initialized for _poolId, _account
    function isDepositInitialized(
        uint256 _poolId,
        address _account
    ) internal view returns (bool) {
        StakingPoolDeposit memory deposit = deposits[_poolId][_account];
        return deposit.initialized;
    }


    function updateReward(uint256 _poolId, address _account) internal {
        StakingPools memory pool = stakingPools[_poolId];
        StakingPoolDeposit memory deposit = deposits[_poolId][_account];
        
        uint256 index = getIndex(deposit.tier);

        (MPXReward.RewardData memory poolRewards, MPXReward.UserRewardData memory userRewards) = MPXReward.updateReward(
            MPXReward.RewardData({
                rewardRate: pool.pools[index].rewardRate,
                lastUpdateTime: pool.pools[index].lastUpdateTime,
                rewardPerTokenStored: pool.pools[index].rewardPerTokenStored,
                periodFinish: pool.endTime
            }),
            MPXReward.UserRewardData({
                userRewardPerTokenPaid: deposit.userRewardPerTokenPaid,
                rewards: deposit.rewards
            }),
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

    /// @notice caller must update rewards before invoking this function
    function _claimReward(uint256 _poolId) internal {
        uint256 reward = deposits[_poolId][msg.sender].rewards;
        if (reward > 0) {
            deposits[_poolId][msg.sender].rewards = 0;
            stakingPools[_poolId].rewardToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, _poolId, reward);
        }       
    }
}
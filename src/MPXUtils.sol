// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library MPXUtils {
    /// @dev number of seconds in a single day
    uint256 public constant SECONDS_PER_DAY = 86400;
    /// @dev during early unstake 5 % goes to dev
    uint256 public constant UNSTAKE_DEV_FEE_PERCENT = 5;
    /// @dev during early unstake 15% gets burned
    uint256 public constant UNSTAKE_BURN_PERCENT = 15;

    /// @dev object contains the start and end times of an actively emitting stake pool
    struct TimeSpan {
        uint256 start;
        uint256 end;
    }

    /// @dev object contains the amount of penalty to apply to early unstake
    struct UnstakePenalty {
        /// the amount of tokens being burned
        uint256 burnAmount;
        /// the amount of tokens to send to dev wallet as fee
        uint256 devFee;
    }

    /// @dev used to configure a staking pool during creation
    struct RewardParameters {
        /// @dev the amount of tokens to emit as rewards
        uint256 rewardsToEmit;
        /// @dev the amount of time in seconds to emit rewards for
        uint256 rewardDurationSeconds;
    }

    /// @dev used to compute the rewardRate parameters which will distribute _totalRewardAmount over _totalDurationInSeconds
    function computeRewardRate(uint256 _totalRewardAmount, uint256 _totalDurationInSeconds)
        public
        pure
        returns (uint256)
    {
        /// @todo this is probably incorrectly using MULTIPLIER_PRECISION
        // just check if this is needed
        // update: removed Multiplier precision for all contracts
        return (_totalRewardAmount ) / _totalDurationInSeconds;
    }

    /// @dev used to compute the start and end times in unix timestamp for which the staking pool is active
    function computeTimeSpan(uint256 _startTime, uint256 _rewardDurationSeconds) public pure returns (TimeSpan memory) {
        return TimeSpan(_startTime, _startTime + _rewardDurationSeconds);
    }

    /// @dev used to add _days to _timestamp
    function addDays(uint256 _timestamp, uint256 _days) public pure returns (uint256 newTimestamp) {
        newTimestamp = _timestamp + (_days * MPXUtils.SECONDS_PER_DAY);
        require(newTimestamp >= _timestamp);
    }

    /// @dev calculates the unstake penalty using the deciamls of the reward token
    function calculateUnstakePenalty(uint256 amount, uint8 decimals) public pure returns (UnstakePenalty memory) {
        require(decimals <= 18, "Decimals should not exceed 18");

        uint256 factor = 10 ** uint256(decimals);
        uint256 scaledAmount = amount * factor; // Scale up the amount to include decimals
        uint256 burnAmount = (scaledAmount * UNSTAKE_BURN_PERCENT) / 100;
        uint256 devFee = (scaledAmount * UNSTAKE_DEV_FEE_PERCENT) / 100;
        return UnstakePenalty({burnAmount: burnAmount / factor, devFee: devFee / factor});
    }

    /// @dev returns the total penalty fee for early unstake
    function totalPenaltyFee(UnstakePenalty memory _penalty) public pure returns (uint256) {
        return _penalty.burnAmount + _penalty.devFee;
    }

}

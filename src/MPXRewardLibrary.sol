// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library MPXReward {
    //uint256 public constant SECONDS_PER_DAY = 86400;
    uint256 public constant SCALING_FACTOR = 1e18;

    struct RewardData {
        uint256 rewardRate;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        uint256 periodFinish;
    }

    struct UserRewardData {
        uint256 userRewardPerTokenPaid; // The amount of reward per token that's already paid to the user
        uint256 rewards; // Total rewards earned by the user
    }

    function updateReward(
        RewardData memory rewardData,
        UserRewardData memory userRewardData,
        uint256 totalSupply,
        uint256 userBalance
    ) internal view returns (RewardData memory, UserRewardData memory) {
        rewardData.rewardPerTokenStored = rewardPerToken(
            rewardData,
            totalSupply
        );
        rewardData.lastUpdateTime = lastTimeRewardApplicable(rewardData.periodFinish);
        userRewardData.rewards = earned(
            rewardData,
            userRewardData,
            userBalance
        );
        userRewardData.userRewardPerTokenPaid = rewardData.rewardPerTokenStored;
        return (rewardData, userRewardData);
    }

    function rewardPerToken(
        RewardData memory rewardData,
        uint256 totalSupply
    ) internal view returns (uint256) {
        if (totalSupply == 0) {
            return rewardData.rewardPerTokenStored;
        }
        return
            rewardData.rewardPerTokenStored +
            (((lastTimeRewardApplicable(rewardData.periodFinish) - rewardData.lastUpdateTime) *
                rewardData.rewardRate *
                SCALING_FACTOR) / totalSupply);
    }

    function earned(
        RewardData memory rewardData,
        UserRewardData memory userRewardData,
        uint256 userBalance
    ) internal view returns (uint256) {
        return
            (userBalance *
                (rewardPerToken(rewardData, userBalance) -
                    userRewardData.userRewardPerTokenPaid)) /
            SCALING_FACTOR +
            userRewardData.rewards;
    }

    function lastTimeRewardApplicable(
        uint256 _periodFinish
    ) public view returns (uint256) {
        return
            block.timestamp < _periodFinish ? block.timestamp : _periodFinish;
    }
}

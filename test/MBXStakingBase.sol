// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/MBXStaking.sol";
import "../src/MBXUtils.sol";
import "./MockERC20.sol";
import "./StakingDepositor.sol";
import "../src/interfaces/IERC20Lite.sol";



contract StakingContractTestBase is Test {
    StakingContract public stakingContract;
    MockERC20 public stakingToken;
    MockERC20 public rewardToken;

    function newStakingDepositor(
        StakingContract.StakingTier _tier,
        uint256 _stakingTokensToFund,
        uint256 _poolId
    ) public returns (StakingDepositor) {
        StakingDepositor depositor = new StakingDepositor(
            address(stakingContract),
            address(stakingToken),
            _poolId,
            _tier
        );
        stakingToken.transfer(address(depositor), _stakingTokensToFund);
        return depositor;
    }

    function manualSetup(
        uint256 _startTime,
        uint256 _rewardDurationSeconds,
        uint256 _fifteenTierRewardsToEmit,
        uint256 _thirtyTierRewardsToEmit,
        uint256 _sixtyTierRewardsToEmit
    ) public {
        MBXUtils.TimeSpan memory tspan = MBXUtils.computeTimeSpan(
            _startTime,
            _rewardDurationSeconds
        );

        stakingToken = new MockERC20("Staking Token", "STK", 18);
        rewardToken = new MockERC20("Reward Token", "RWD", 18);
        stakingContract = new StakingContract(address(0x1), address(this));

        MBXUtils.RewardParameters[3] memory params;
        params[0] = MBXUtils.RewardParameters({
            rewardsToEmit: _fifteenTierRewardsToEmit,
            rewardDurationSeconds: _rewardDurationSeconds
        });
        params[1] = MBXUtils.RewardParameters({
            rewardsToEmit: _thirtyTierRewardsToEmit,
            rewardDurationSeconds: _rewardDurationSeconds
        });
        params[2] = MBXUtils.RewardParameters({
            rewardsToEmit: _sixtyTierRewardsToEmit,
            rewardDurationSeconds: _rewardDurationSeconds
        });

        StakingContract.StakingTier[3] memory tiers;
        tiers[0] = StakingContract.StakingTier.Fifteen;
        tiers[1] = StakingContract.StakingTier.Thirty;
        tiers[2] = StakingContract.StakingTier.Sixty;

        stakingContract.newStakePool(
            params,
            tiers,
            tspan,
            address(stakingToken),
            address(rewardToken)
        );

        // Mint tokens for the test
        stakingToken.mint(address(this), 100000000000 ether);
        rewardToken.mint(address(this), 100000000000 ether);
        rewardToken.transfer(address(stakingContract), 10000 ether);

        // Approve tokens for staking
        stakingToken.approve(address(stakingContract), 100000000000 ether);
    }    
}
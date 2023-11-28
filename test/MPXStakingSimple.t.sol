// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/MBXStaking.sol";
import "../src/MBXUtils.sol";
import "./MockERC20.sol";
import "./StakingDepositor.sol";
import "./MBXStakingBase.sol";
import "../src/interfaces/IERC20Lite.sol";

/// basic test contract which does single depositor single pool
contract StakingContractTestSimple is StakingContractTestBase {
    function testStake() public {
        uint256 depositAmount = 1e18;
        uint256 fundAmount = 2e18;
        manualSetup(block.timestamp, 86400 * 60, 2000 ether, 3000 ether, 5000 ether);
        StakingDepositor depositor = newStakingDepositor(StakingContract.StakingTier.Fifteen, fundAmount, 0);

        depositor.deposit(depositAmount);

        //stakingContract.stake(poolId, amount, StakingContract.StakingTier.Fourteen);

        StakingContract.StakingPoolDeposit memory deposit = stakingContract.getUserStake(0, address(depositor));

        // Assertions to check staking behavior
        assertEq(deposit.stakedAmount, depositAmount);
        assertEq(stakingToken.balanceOf(address(stakingContract)), depositAmount);

        vm.warp(block.timestamp + 300);
        uint256 oldUnlockTime = deposit.unlockTime;

        depositor.deposit(depositAmount);

        assertEq(stakingToken.balanceOf(address(stakingContract)), fundAmount);
        deposit = stakingContract.getUserStake(0, address(depositor));
        assertGt(deposit.unlockTime, oldUnlockTime);

        depositor.claimReward();
    }

    /// forge-config: default.fuzz.max-test-rejects = 131072
    function testFuzz_StakeReward(uint96 _rewardRate) public {
        uint256 depositAmount = 1e18;
        uint256 fundAmount = 2e18;
        vm.assume(_rewardRate > 0 && _rewardRate <= 10000);
        manualSetup(block.timestamp, 86400 * 60, 2000 ether, 3000 ether, 5000 ether);
        StakingDepositor depositor = newStakingDepositor(StakingContract.StakingTier.Fifteen, fundAmount, 0);

        depositor.deposit(depositAmount);

        //stakingContract.stake(poolId, amount, StakingContract.StakingTier.Fourteen);

        StakingContract.StakingPoolDeposit memory deposit = stakingContract.getUserStake(0, address(depositor));

        // Assertions to check staking behavior
        assertEq(deposit.stakedAmount, depositAmount);
        assertEq(stakingToken.balanceOf(address(stakingContract)), depositAmount);

        vm.warp(block.timestamp + 300);
        uint256 oldUnlockTime = deposit.unlockTime;

        depositor.deposit(depositAmount);

        assertEq(stakingToken.balanceOf(address(stakingContract)), fundAmount);
        deposit = stakingContract.getUserStake(0, address(depositor));
        assertGt(deposit.unlockTime, oldUnlockTime);
    }

    /// forge-config: default.fuzz.max-test-rejects = 131072
    function testFuzz_StakeAll(uint96 _depositAmount, uint96 _rewardRate) public {
        vm.assume(_depositAmount > 100 && _depositAmount < 1e18);
        uint96 fundAmount = 2 * _depositAmount;
        vm.assume(_rewardRate > 0 && _rewardRate <= 10000);
        manualSetup(block.timestamp, 86400 * 60, 2000 ether, 3000 ether, 5000 ether);
        StakingDepositor depositor = newStakingDepositor(StakingContract.StakingTier.Fifteen, fundAmount, 0);

        depositor.deposit(_depositAmount);

        //stakingContract.stake(poolId, amount, StakingContract.StakingTier.Fourteen);

        StakingContract.StakingPoolDeposit memory deposit = stakingContract.getUserStake(0, address(depositor));

        // Assertions to check staking behavior
        assertEq(deposit.stakedAmount, _depositAmount);
        assertEq(stakingToken.balanceOf(address(stakingContract)), _depositAmount);

        vm.warp(block.timestamp + 300);
        uint256 oldUnlockTime = deposit.unlockTime;

        depositor.deposit(_depositAmount);

        assertEq(stakingToken.balanceOf(address(stakingContract)), fundAmount);
        deposit = stakingContract.getUserStake(0, address(depositor));
        assertGt(deposit.unlockTime, oldUnlockTime);
    }

    function testUnstake() public {
        uint256 depositAmount = 1e18;
        uint256 fundAmount = 2e18;
        manualSetup(block.timestamp, 86400 * 60, 2000 ether, 3000 ether, 5000 ether);
        StakingDepositor depositor = newStakingDepositor(StakingContract.StakingTier.Fifteen, fundAmount, 0);

        depositor.deposit(depositAmount);

        vm.warp(MBXUtils.addDays(block.timestamp, 15));

        assertEq(stakingToken.balanceOf(address(stakingContract)), depositAmount);
        depositor.claimReward();
        depositor.unstake(depositAmount);
        assertEq(stakingToken.balanceOf(address(stakingContract)), 0);

        StakingContract.StakingPoolDeposit memory deposit = stakingContract.getUserStake(0, address(depositor));
        // Assertions to check unstaking behavior
        assertEq(deposit.stakedAmount, 0, "staked amount is 0");
    }

    /// forge-config: default.fuzz.max-test-rejects = 131072
    function testFuzz_UnstakeAll(uint96 _depositAmount) public {
        vm.assume(_depositAmount > 100 && _depositAmount < 1e18);
        uint96 fundAmount = 2 * _depositAmount;
        manualSetup(block.timestamp, 86400 * 60, 2000 ether, 3000 ether, 5000 ether);
        StakingDepositor depositor = newStakingDepositor(StakingContract.StakingTier.Fifteen, fundAmount, 0);

        depositor.deposit(_depositAmount);

        vm.warp(MBXUtils.addDays(block.timestamp, 15));

        assertEq(stakingToken.balanceOf(address(stakingContract)), _depositAmount);
        depositor.claimReward();
        depositor.unstake(_depositAmount);
        assertEq(stakingToken.balanceOf(address(stakingContract)), 0);

        StakingContract.StakingPoolDeposit memory deposit = stakingContract.getUserStake(0, address(depositor));
        // Assertions to check unstaking behavior
        assertEq(deposit.stakedAmount, 0, "staked amount is 0");
    }

    function testEarlyUnstake() public {
        uint256 depositAmount = 1e18;
        uint256 fundAmount = 2e18;
        manualSetup(block.timestamp, 86400 * 60, 2000 ether, 3000 ether, 5000 ether);
        StakingDepositor depositor = newStakingDepositor(StakingContract.StakingTier.Fifteen, fundAmount, 0);

        depositor.deposit(depositAmount);
        vm.warp(block.timestamp + 901);
        depositor.unstakeEarly();
        StakingContract.StakingPoolDeposit memory deposit = stakingContract.getUserStake(0, address(depositor));
        assertEq(deposit.stakedAmount, 0, "staked amount is 0");
    }

    function testFuzz_EarlyUnstakeAll(uint96 _depositAmount) public {
        vm.assume(_depositAmount > 100 && _depositAmount < 1e18);
        uint96 fundAmount = 2 * _depositAmount;
        manualSetup(block.timestamp, 86400 * 60, 2000 ether, 3000 ether, 5000 ether);
        StakingDepositor depositor = newStakingDepositor(StakingContract.StakingTier.Fifteen, fundAmount, 0);

        depositor.deposit(_depositAmount);
        vm.warp(block.timestamp + 901);
        depositor.unstakeEarly();
        StakingContract.StakingPoolDeposit memory deposit = stakingContract.getUserStake(0, address(depositor));
        assertEq(deposit.stakedAmount, 0, "staked amount is 0");
    }

    function testClaimReward() public {
        uint256 depositAmount = 1e18;
        uint256 fundAmount = 2e18;
        manualSetup(block.timestamp, 86400 * 60, 2000 ether, 3000 ether, 5000 ether);
        StakingDepositor depositor = newStakingDepositor(StakingContract.StakingTier.Fifteen, fundAmount, 0);

        depositor.deposit(depositAmount);

        vm.warp(block.timestamp + 300);

        StakingContract.StakingPoolDeposit memory deposit = stakingContract.getUserStake(0, address(depositor));
        // Assertions to check staking behavior
        assertEq(deposit.stakedAmount, depositAmount);
        assertEq(stakingToken.balanceOf(address(stakingContract)), depositAmount);

        // Simulate some blocks for rewards to accrue
        vm.warp(block.timestamp + (86400 * 14));

        depositor.claimReward();

        uint256 rewards = stakingContract.earned(0, address(depositor));
        assertEq(rewards, 0);
        // changing fuzz
        //assertEq(rewardToken.balanceOf(address(depositor)), 466782407407406839800);
        assertEq(rewardToken.balanceOf(address(depositor)), 466666666666666099200);

        vm.warp(block.timestamp + (86400 * 90));

        depositor.claimReward();

        rewards = stakingContract.earned(0, address(depositor));
        assertEq(rewards, 0);
        assertEq(rewardToken.balanceOf(address(depositor)), 1999999999999997568000);
    }

    function testFuzz_ClaimRewardAll(uint256 _depositAmount) public {
        vm.assume(_depositAmount > 100 && _depositAmount < 3e18);
        uint256 fundAmount = 2 * _depositAmount;
        manualSetup(block.timestamp, 86400 * 60, 2000 ether, 3000 ether, 5000 ether);
        StakingDepositor depositor = newStakingDepositor(StakingContract.StakingTier.Fifteen, fundAmount, 0);

        depositor.deposit(_depositAmount);

        vm.warp(block.timestamp + 300);

        StakingContract.StakingPoolDeposit memory deposit = stakingContract.getUserStake(0, address(depositor));
        // Assertions to check staking behavior
        assertEq(deposit.stakedAmount, _depositAmount);
        assertEq(stakingToken.balanceOf(address(stakingContract)), _depositAmount);

        // Simulate some blocks for rewards to accrue
        vm.warp(block.timestamp + (86400 * 14));

        depositor.claimReward();
        // todo: update
        //uint256 rewards = stakingContract.earned(0, address(depositor));
        //assertEq(rewards, 0);

        vm.warp(block.timestamp + (86400 * 15));

        depositor.claimReward();
        // todo: update
        //rewards = stakingContract.earned(0, address(this));
        //assertEq(rewards, 0);
        //assertEq(rewardToken.balanceOf(address(depositor)), 3000 ether);
    }

    function testComputeRewardRate() public returns (uint256, uint256) {
        // Example parameters
        uint256 totalRewardAmount = 10000 ether; // Total amount of rewards to be distributed
        uint256 totalDuration = 86400; // Duration over which rewards are distributed

        // Expected reward rate calculation
        uint256 expectedRewardRate = totalRewardAmount / totalDuration;

        // Actual reward rate from the function
        uint256 actualRewardRate = MBXUtils.computeRewardRate(totalRewardAmount, totalDuration);
        assertEq(actualRewardRate, expectedRewardRate, "reward rate incorrect");

        return (actualRewardRate, expectedRewardRate);
    }
}

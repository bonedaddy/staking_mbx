// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/MBStakingCheckpoint.sol";
import "./MockERC20.sol";
import "./CheckpointStakingDepositor.sol";
import "../src/interfaces/IERC20Lite.sol";

contract CheckpointStakingBaseTest is Test {
    StakingCheckpoint public stakingContract;
    MockERC20 public stakingToken;
    MockERC20 public rewardToken;

    function newStakingDepositor(uint256 _stakingTokensToFund) public returns (CheckpointStakingDepositor) {
        CheckpointStakingDepositor depositor = new CheckpointStakingDepositor(
            address(stakingContract),
            address(stakingToken)
        );
        stakingToken.transfer(address(depositor), _stakingTokensToFund);
        return depositor;
    }

    function setUp() public {
        stakingToken = new MockERC20("Staking Token", "STK", 18);
        stakingToken.mint(address(this), 100000000 ether);
        rewardToken = new MockERC20("Reward Token", "RWD", 18);
        rewardToken.mint(address(this), 100000000 ether);
        stakingContract = new StakingCheckpoint(address(rewardToken), address(stakingToken));

        // Approve tokens for staking
        stakingToken.approve(address(stakingContract), 100000000000 ether);

        rewardToken.approve(address(stakingContract), 1000000000 ether);
    }

    function test_Stake() public {
        // unpause the staking functionality
        stakingContract.togglePause();
        // activate staking
        stakingContract.enableStaking();

        StakingCheckpoint.DistributionPeriod memory distributionPeriod = stakingContract.getDistributionPeriod(1);
        require(distributionPeriod.periodStartedAt == block.timestamp);

        vm.warp(block.timestamp + 1);

        CheckpointStakingDepositor depositor = newStakingDepositor(1000 ether);
        depositor.deposit(1 ether);

        StakingCheckpoint.DepositCheckpoint[] memory depositCheckpoints =
            stakingContract.getDepositCheckpoints(address(depositor), 1);
        require(depositCheckpoints.length == 1, "invalid_length");

        StakingCheckpoint.DepositInformation memory depositInfo = stakingContract.getUserDeposit(address(depositor), 1);
        distributionPeriod = stakingContract.getDistributionPeriod(1);

        require(!distributionPeriod.finished, "not_finished");
        require(depositInfo.depositedBalance == distributionPeriod.totalDepositedBalance, "mismatch_deposit");
        require(depositInfo.depositedBalance == 1 ether, "invalid_balance");
        assertEq(depositInfo.lastDepositTime, block.timestamp);
        require(!depositInfo.revenueClaimed, "revenue_claimed");

        uint256 previousDepositTime = depositInfo.lastDepositTime;

        vm.warp(block.timestamp + 60);

        depositor.deposit(2 ether);

        depositCheckpoints = stakingContract.getDepositCheckpoints(address(depositor), 1);
        distributionPeriod = stakingContract.getDistributionPeriod(1);
        require(depositCheckpoints.length == 2, "invalid_length");
        require(distributionPeriod.totalDepositedBalance == 3 ether, "invalid_deposit");
        depositInfo = stakingContract.getUserDeposit(address(depositor), 1);
        require(depositInfo.lastDepositTime > previousDepositTime, "current_timestamp_not_greater");
        require(depositInfo.depositedBalance == distributionPeriod.totalDepositedBalance);

        previousDepositTime = depositInfo.lastDepositTime;

        // advance 7 days
        vm.warp(block.timestamp + 7 * 86400);

        // distribute revenue for the current period, advancing it
        stakingContract.distributeRevenue(100 ether);

        // claim reward (equal time so no rewards to claim)
        depositor.claimRewards(1);
        require(rewardToken.balanceOf(address(depositor)) == 0, "invalid_balance");

        // advance 6 days
        vm.warp(block.timestamp + 6 * 86400);
        depositor.claimRewards(1);

        // advance 2 days after the claim time finishes
        vm.warp(block.timestamp + 2 * 86400);

        depositor.claimRewards(1);
        depositInfo = stakingContract.getUserDeposit(address(depositor), 1);
        require(depositInfo.revenueClaimed, "not_claimed");

        depositor.deposit(1 ether);
        depositInfo = stakingContract.getUserDeposit(address(depositor), 2);
        require(depositInfo.depositedBalance == 4 ether, "invalid_balance");

        // period 1 claim should fail
        vm.expectRevert();
        depositor.claimRewards(1);

        vm.expectRevert();
        // period 2 claim should fail since its not started yet
        depositor.claimRewards(2);

        // warp 3 blocks and distribute revenue, indicating this period only lasted 3 days
        vm.warp(block.timestamp + 3 * 86400);

        // distribute revenue for current period, and advance new period
        stakingContract.distributeRevenue(300 ether);

        vm.warp(block.timestamp + 3);

        depositor.claimRewards(2);
    }

    function test_Unstake() public {
        // unpause the staking functionality
        stakingContract.togglePause();
        // activate staking
        stakingContract.enableStaking();

        StakingCheckpoint.DistributionPeriod memory distributionPeriod = stakingContract.getDistributionPeriod(1);
        require(distributionPeriod.periodStartedAt == block.timestamp);

        vm.warp(block.timestamp + 1);

        CheckpointStakingDepositor depositor = newStakingDepositor(1000 ether);
        depositor.deposit(1 ether);

        StakingCheckpoint.DepositCheckpoint[] memory depositCheckpoints =
            stakingContract.getDepositCheckpoints(address(depositor), 1);
        require(depositCheckpoints.length == 1, "invalid_length");

        StakingCheckpoint.DepositInformation memory depositInfo = stakingContract.getUserDeposit(address(depositor), 1);
        distributionPeriod = stakingContract.getDistributionPeriod(1);

        require(!distributionPeriod.finished, "not_finished");
        require(depositInfo.depositedBalance == distributionPeriod.totalDepositedBalance, "mismatch_deposit");
        require(depositInfo.depositedBalance == 1 ether, "invalid_balance");
        assertEq(depositInfo.lastDepositTime, block.timestamp);
        require(!depositInfo.revenueClaimed, "revenue_claimed");

        uint256 previousDepositTime = depositInfo.lastDepositTime;

        vm.warp(block.timestamp + 60);

        depositor.deposit(2 ether);

        depositCheckpoints = stakingContract.getDepositCheckpoints(address(depositor), 1);
        distributionPeriod = stakingContract.getDistributionPeriod(1);
        require(depositCheckpoints.length == 2, "invalid_length");
        require(distributionPeriod.totalDepositedBalance == 3 ether, "invalid_deposit");
        depositInfo = stakingContract.getUserDeposit(address(depositor), 1);
        require(depositInfo.lastDepositTime > previousDepositTime, "current_timestamp_not_greater");
        require(depositInfo.depositedBalance == distributionPeriod.totalDepositedBalance);

        previousDepositTime = depositInfo.lastDepositTime;

        // advance 60 days
        vm.warp(block.timestamp + 60 * 86400);

        // distribute revenue for the current period, advancing it
        stakingContract.distributeRevenue(100 ether);

        // claim reward (equal time so no rewards to claim)
        depositor.claimRewards(1);
        require(rewardToken.balanceOf(address(depositor)) == 0, "invalid_balance");

        // advance 6 days
        vm.warp(block.timestamp + 6 * 86400);
        depositor.claimRewards(1);

        // withdraw partial rewards, this will rollover their previous
        // deposit information to the new period
        depositor.withdraw(2 ether);

        // deposit information from period 1 should be unchanged
        // while current period deposit should be 1 ether
        depositInfo = stakingContract.getUserDeposit(address(depositor), 2);
        require(depositInfo.depositedBalance == 1 ether, "insufficient_funds");
        depositInfo = stakingContract.getUserDeposit(address(depositor), 1);
        require(depositInfo.depositedBalance == 3 ether);

        // advance 2 days after the claim time finishes
        vm.warp(block.timestamp + 2 * 86400);

        depositor.claimRewards(1);
        depositInfo = stakingContract.getUserDeposit(address(depositor), 1);
        require(depositInfo.revenueClaimed, "not_claimed");

        depositor.deposit(1 ether);
        depositInfo = stakingContract.getUserDeposit(address(depositor), 2);
        require(depositInfo.depositedBalance == 2 ether, "invalid_balance");

        // period 1 claim should fail
        vm.expectRevert();
        depositor.claimRewards(1);

        vm.expectRevert();
        // period 2 claim should fail since its not started yet
        depositor.claimRewards(2);

        // warp 3 blocks and distribute revenue, indicating this period only lasted 3 days
        vm.warp(block.timestamp + 3 * 86400);

        // distribute revenue for current period, and advance new period
        stakingContract.distributeRevenue(300 ether);

        vm.warp(block.timestamp + 3);

        depositor.claimRewards(2);

        vm.warp(block.timestamp + 7 * 86400);

        // claim remaining rewards
        depositor.claimRewards(2);
    }
}

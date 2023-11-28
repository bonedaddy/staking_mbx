// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/MBXStaking.sol";
import "../src/MBXUtils.sol";
import "./MockERC20.sol";
import "./StakingDepositor.sol";
import "./MBXStakingBase.sol";
import "../src/interfaces/IERC20Lite.sol";

/// basic test contract which does multiple depositors single pool
contract StakingContractTestSinglePool is StakingContractTestBase {

    function testStake() public {
        uint256 depositAmount = 1e18;
        uint256 fundAmount = 3e18;
        manualSetup(block.timestamp,86400 * 60, 2000 ether, 3000 ether, 5000 ether); 
        StakingDepositor depositor1 = newStakingDepositor(
            StakingContract.StakingTier.Fifteen,
            fundAmount,
            0
        );
        StakingDepositor depositor2 = newStakingDepositor(
            StakingContract.StakingTier.Thirty,
            fundAmount,
            0
        );
        StakingDepositor depositor3 = newStakingDepositor(
            StakingContract.StakingTier.Sixty,
            fundAmount,
            0
        );

        // deposit into the fifteen day tier once
        depositor1.deposit(depositAmount);
        StakingContract.StakingPools memory pool = stakingContract.getStakingPool(0);
        StakingContract.StakingPoolDeposit memory deposit = stakingContract.getUserStake(0, address(depositor1));
        // ensure pool balance was updated
        assertEq(pool.pools[0].totalStaked, depositAmount);
        // ensure user balance was updated
        assertEq(deposit.stakedAmount, depositAmount);

        // cache unlock time
        uint256 prevUnlockTime = deposit.unlockTime;


        // fast forward time
        vm.warp(block.timestamp + 30);

        // deposit into the fifteen day tier a second time
        depositor1.deposit(depositAmount);
        pool = stakingContract.getStakingPool(0);
        deposit = stakingContract.getUserStake(0, address(depositor1));
        assertEq(deposit.stakedAmount, depositAmount*2);
        assertEq(pool.pools[0].totalStaked, depositAmount*2);
        // ensure the lock time was updated
        assertGt(deposit.unlockTime, prevUnlockTime);

        // fast forward time
        vm.warp(block.timestamp + 2);

        // deposit into the thirty day tier once
        depositor2.deposit(depositAmount);
        pool = stakingContract.getStakingPool(0);
        deposit = stakingContract.getUserStake(0, address(depositor2));
        assertEq(pool.pools[1].totalStaked, depositAmount);
        assertEq(deposit.stakedAmount, depositAmount);
        prevUnlockTime = deposit.unlockTime;


        // fast forward time
        vm.warp(block.timestamp + 45);

        // deposit into the thirty day tier a second time
        depositor2.deposit(depositAmount);
        pool = stakingContract.getStakingPool(0);
        deposit = stakingContract.getUserStake(0, address(depositor2));
        assertEq(deposit.stakedAmount, depositAmount*2);
        assertEq(pool.pools[1].totalStaked, depositAmount*2);
        assertGt(deposit.unlockTime, prevUnlockTime);
        

        // fast forward time
        vm.warp(block.timestamp + 2);

        // deposit into the sixty day tier once
        depositor3.deposit(depositAmount);
        pool = stakingContract.getStakingPool(0);
        deposit = stakingContract.getUserStake(0, address(depositor3));
        assertEq(pool.pools[2].totalStaked, depositAmount);
        assertEq(deposit.stakedAmount, depositAmount);
        prevUnlockTime = deposit.unlockTime;

        // fast forward time
        vm.warp(block.timestamp + 6);

        // deposit into the sixty day tier a second time
        depositor3.deposit(depositAmount);
        pool = stakingContract.getStakingPool(0);
        deposit = stakingContract.getUserStake(0, address(depositor3));
        assertEq(pool.pools[2].totalStaked, depositAmount*2);
        assertEq(deposit.stakedAmount, depositAmount*2);

        // ensure the other pools total staked is the same
        assertEq(pool.pools[1].totalStaked, depositAmount*2);
        assertEq(pool.pools[0].totalStaked, depositAmount*2);

    }


    function testFuzz_Stake(
        uint96 _fifteenTierRewardAmount,
        uint96 _depositAmount
    ) public {
        vm.assume(_depositAmount > 100 && _depositAmount <= type(uint96).max && _depositAmount <= 50000000 ether);
        vm.assume(_fifteenTierRewardAmount >= 1e18 && _fifteenTierRewardAmount <= 10000000 ether);
        uint256 _thirtyTierRewardAmount = _fifteenTierRewardAmount + 100000 ether;
        uint256 _sixtyTierRewardAmount = _thirtyTierRewardAmount + 100000 ether;
        
        vm.assume(
            _fifteenTierRewardAmount + _thirtyTierRewardAmount + _sixtyTierRewardAmount <= type(uint96).max
        );
        uint256 fundAmount = 4*_depositAmount;
        manualSetup(block.timestamp,86400 * 60, _fifteenTierRewardAmount, _thirtyTierRewardAmount, _sixtyTierRewardAmount); 
        StakingDepositor depositor1 = newStakingDepositor(
            StakingContract.StakingTier.Fifteen,
            fundAmount,
            0
        );
        StakingDepositor depositor2 = newStakingDepositor(
            StakingContract.StakingTier.Thirty,
            fundAmount,
            0
        );
        StakingDepositor depositor3 = newStakingDepositor(
            StakingContract.StakingTier.Sixty,
            fundAmount,
            0
        );

        // deposit into the fifteen day tier once
        depositor1.deposit(_depositAmount);
        StakingContract.StakingPools memory pool = stakingContract.getStakingPool(0);
        StakingContract.StakingPoolDeposit memory deposit = stakingContract.getUserStake(0, address(depositor1));
        // ensure pool balance was updated
        assertEq(pool.pools[0].totalStaked, _depositAmount);
        // ensure user balance was updated
        assertEq(deposit.stakedAmount, _depositAmount);

        // cache unlock time
        uint256 prevUnlockTime = deposit.unlockTime;


        // fast forward time
        vm.warp(block.timestamp + 30);

        // deposit into the fifteen day tier a second time
        depositor1.deposit(_depositAmount);
        pool = stakingContract.getStakingPool(0);
        deposit = stakingContract.getUserStake(0, address(depositor1));
        assertEq(deposit.stakedAmount, _depositAmount*2);
        assertEq(pool.pools[0].totalStaked, _depositAmount*2);
        // ensure the lock time was updated
        assertGt(deposit.unlockTime, prevUnlockTime);

        // fast forward time
        vm.warp(block.timestamp + 2);

        // deposit into the thirty day tier once
        depositor2.deposit(_depositAmount);
        pool = stakingContract.getStakingPool(0);
        deposit = stakingContract.getUserStake(0, address(depositor2));
        assertEq(pool.pools[1].totalStaked, _depositAmount);
        assertEq(deposit.stakedAmount, _depositAmount);
        prevUnlockTime = deposit.unlockTime;


        // fast forward time
        vm.warp(block.timestamp + 45);

        // deposit into the thirty day tier a second time
        depositor2.deposit(_depositAmount);
        pool = stakingContract.getStakingPool(0);
        deposit = stakingContract.getUserStake(0, address(depositor2));
        assertEq(deposit.stakedAmount, _depositAmount*2);
        assertEq(pool.pools[1].totalStaked, _depositAmount*2);
        assertGt(deposit.unlockTime, prevUnlockTime);
        

        // fast forward time
        vm.warp(block.timestamp + 2);

        // deposit into the sixty day tier once
        depositor3.deposit(_depositAmount);
        pool = stakingContract.getStakingPool(0);
        deposit = stakingContract.getUserStake(0, address(depositor3));
        assertEq(pool.pools[2].totalStaked, _depositAmount);
        assertEq(deposit.stakedAmount, _depositAmount);
        prevUnlockTime = deposit.unlockTime;

        // fast forward time
        vm.warp(block.timestamp + 6);

        // deposit into the sixty day tier a second time
        depositor3.deposit(_depositAmount);
        pool = stakingContract.getStakingPool(0);
        deposit = stakingContract.getUserStake(0, address(depositor3));
        assertEq(pool.pools[2].totalStaked, _depositAmount*2);
        assertEq(deposit.stakedAmount, _depositAmount*2);

        // ensure the other pools total staked is the same
        assertEq(pool.pools[1].totalStaked, _depositAmount*2);
        assertEq(pool.pools[0].totalStaked, _depositAmount*2);

    }


    function testUnstake() public {
        uint256 depositAmount = 1e18;
        uint256 fundAmount = 3e18;
        manualSetup(block.timestamp,86400 * 60, 2000 ether, 3000 ether, 5000 ether); 
        StakingDepositor depositor1 = newStakingDepositor(
            StakingContract.StakingTier.Fifteen,
            fundAmount,
            0
        );
        StakingDepositor depositor2 = newStakingDepositor(
            StakingContract.StakingTier.Thirty,
            fundAmount,
            0
        );
        StakingDepositor depositor3 = newStakingDepositor(
            StakingContract.StakingTier.Sixty,
            fundAmount,
            0
        );

        // just do a bulk deposit
        depositor1.deposit(fundAmount);

        assertEq(
            stakingToken.balanceOf(address(stakingContract)),
            fundAmount
        );

        depositor2.deposit(fundAmount);

        assertEq(
            stakingToken.balanceOf(address(stakingContract)),
            fundAmount*2
        );

        depositor3.deposit(fundAmount);

        assertEq(
            stakingToken.balanceOf(address(stakingContract)),
            fundAmount*3
        );

        // all 3 unstakes should revert
        vm.expectRevert();
        depositor1.unstake(depositAmount);
        vm.expectRevert();
        depositor2.unstake(depositAmount);
        vm.expectRevert();
        depositor3.unstake(depositAmount);

        // total days advanced: 15
        vm.warp(MBXUtils.addDays(block.timestamp, 15) + 100);

        // do a partial unstake
        depositor1.unstake(depositAmount);
        StakingContract.StakingPools memory pool = stakingContract.getStakingPool(0);
        StakingContract.StakingPoolDeposit memory deposit = stakingContract.getUserStake(0, address(depositor1));
        assertEq(deposit.stakedAmount, depositAmount*2);
        assertEq(pool.pools[0].totalStaked, depositAmount*2);

        assertEq(
            stakingToken.balanceOf(address(stakingContract)),
            (fundAmount*3)-depositAmount
        );
        
        // unstake a tiny amount
        depositor1.unstake(1);
        deposit = stakingContract.getUserStake(0, address(depositor1));
        pool = stakingContract.getStakingPool(0);
        assertEq(deposit.stakedAmount, depositAmount*2 - 1);
        assertEq(pool.pools[0].totalStaked, depositAmount*2-1);
        assertEq(
            stakingToken.balanceOf(address(stakingContract)),
            (fundAmount*3)-(depositAmount+1)
        );

        // should revert due to excessive unstake
        vm.expectRevert();
        depositor1.unstake(deposit.stakedAmount+1);

        // unstake the rest
        depositor1.unstake(deposit.stakedAmount);
        deposit = stakingContract.getUserStake(0, address(depositor1));
        pool = stakingContract.getStakingPool(0);
        assertEq(deposit.stakedAmount, 0);
        assertEq(pool.pools[0].totalStaked, 0);
        assertEq(
            stakingToken.balanceOf(address(stakingContract)),
            (fundAmount*2)
        );



        vm.expectRevert();
        depositor2.unstake(fundAmount);
        vm.expectRevert();
        depositor3.unstake(fundAmount);

        // total days advanced: 30
        vm.warp(MBXUtils.addDays(block.timestamp, 15) + 100);

        depositor2.unstake(fundAmount);
        deposit = stakingContract.getUserStake(0, address(depositor2));
        pool = stakingContract.getStakingPool(0);
        assertEq(deposit.stakedAmount, 0);
        assertEq(pool.pools[1].totalStaked, 0);
        assertEq(
            stakingToken.balanceOf(address(stakingContract)),
            fundAmount
        );

        // should revert since depositor1 has no more tokens to unstake
        vm.expectRevert();
        depositor1.unstake(fundAmount);
        vm.expectRevert();
        // should revert since depositor3 hasnt unlocked yet
        depositor3.unstake(fundAmount);

        // total days advanced: 45
        vm.warp(MBXUtils.addDays(block.timestamp, 15) + 100);
        // depositor3 is still not unlocked
        vm.expectRevert();
        depositor3.unstake(fundAmount);

        // total days advanced: 60
        vm.warp(MBXUtils.addDays(block.timestamp, 15)+100);
        depositor3.unstake(fundAmount);
        deposit = stakingContract.getUserStake(0, address(depositor2));
        pool = stakingContract.getStakingPool(0);
        assertEq(deposit.stakedAmount, 0);
        assertEq(pool.pools[2].totalStaked, 0);

        assertEq(stakingToken.balanceOf(address(stakingContract)), 0);
    }

    function testEarlyUnstake() public {
        uint256 depositAmount = 1e18;
        uint256 fundAmount = 2e18;
        manualSetup(block.timestamp,86400 * 60, 2000 ether, 3000 ether, 5000 ether); 
        StakingDepositor depositor1 = newStakingDepositor(
            StakingContract.StakingTier.Fifteen,
            fundAmount,
            0
        );
        StakingDepositor depositor2 = newStakingDepositor(
            StakingContract.StakingTier.Thirty,
            fundAmount,
            0
        );
        StakingDepositor depositor3 = newStakingDepositor(
            StakingContract.StakingTier.Sixty,
            fundAmount,
            0
        );

        depositor1.deposit(depositAmount);
        depositor2.deposit(depositAmount);
        depositor3.deposit(depositAmount);

        MBXUtils.UnstakePenalty memory unstakePenalty = MBXUtils.calculateUnstakePenalty(
            depositAmount,
            stakingToken.decimals()
        );

        depositor1.unstakeEarly();
        depositor2.unstakeEarly();
        depositor3.unstakeEarly();

        StakingContract.StakingPoolDeposit memory deposit = stakingContract.getUserStake(0, address(depositor1));
        assertEq(deposit.stakedAmount, 0, "staked amount is 0");
         deposit = stakingContract.getUserStake(0, address(depositor2));
        assertEq(deposit.stakedAmount, 0, "staked amount is 0");
         deposit = stakingContract.getUserStake(0, address(depositor2));
        assertEq(deposit.stakedAmount, 0, "staked amount is 0");

        assertEq(
            stakingToken.balanceOf(stakingContract.devWallet()),
            unstakePenalty.devFee*3
        );

    }

}

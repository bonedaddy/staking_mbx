// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/MBXStaking.sol";
import "../src/MBXUtils.sol";
import "./MockERC20.sol";
import "../src/interfaces/IERC20Lite.sol";

contract StakingDepositor {
    IERC20 immutable stakingToken;
    uint256 immutable poolId;
    StakingContract immutable staking;
    StakingContract.StakingTier immutable tier;

    constructor(address _stakingContract, address _stakingToken, uint256 _poolId, StakingContract.StakingTier _tier) {
        stakingToken = IERC20(_stakingToken);
        stakingToken.approve(_stakingContract, 10000000000 ether);
        poolId = _poolId;
        tier = _tier;
        staking = StakingContract(_stakingContract);
    }

    function deposit(uint256 _amount) public {
        staking.stake(poolId, _amount, tier);
    }

    function unstake(uint256 _amount) public {
        staking.unstake(poolId, _amount);
    }

    function unstakeEarly() public {
        staking.earlyUnstake(poolId);
    }

    function claimReward() public {
        staking.claimReward(poolId);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/MBStakingCheckpoint.sol";
import "./MockERC20.sol";
import "../src/interfaces/IERC20Lite.sol";

contract CheckpointStakingDepositor {
    IERC20 immutable stakingToken;
    StakingCheckpoint public staking;

    constructor(address _stakingContract, address _stakingToken) {
        stakingToken = IERC20(_stakingToken);
        stakingToken.approve(_stakingContract, 10000000000 ether);
        staking = StakingCheckpoint(_stakingContract);
    }

    function deposit(uint256 _amount) public {
        stakingToken.approve(address(staking), 10000000000 ether);
        staking.stake(_amount);
    }

    function withdraw(uint256 _amount) public {
        staking.unstake(_amount);
    }

    function claimRewards(uint256 _periodId) public {
        staking.claimRewards(_periodId);
    }
}

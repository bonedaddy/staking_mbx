pragma solidity ^0.8.0;
import "./MBXUtils.sol";
import "./interfaces/IERC20Lite.sol";
import "solmate/utils/ReentrancyGuard.sol";
import "./MBXRewardLibrary.sol";

contract StakingCheckpoint is ReentrancyGuard {
    address immutable public rewardToken;
    address immutable public stakingToken;
    /// @dev we start the distribution period at 1 to prevent issues
    /// @dev as a measure of making development slightly easier to avoid
    /// @dev having to handle staking distributions for the first period due to default values of 0
    uint256 public currentDistributionPeriod = 1;

    struct DepositCheckpoint {
        /// @dev tracks their active deposit balance
        uint256 depositedBalance;
        uint256 lastDepositTime;
        /// @dev indicates if the user has claimd their revenue
        bool revenueClaimed;
    }

    struct DistributionPeriodCheckpoint {
        /// @dev total deposited balance in the checkpoint
        /// @dev value is fixed after the period is finished
        uint256 totalDepositedBalance;
        /// @dev 0 value that is only set when the period is finished and revenue deposited
        uint256 revenueDeposited;
        /// @dev indicates if the distribution period is finished and has rolled over to a new one
        bool finished;

    }

    /// @dev maps user address => distribution period => deposit
    mapping (address => mapping(uint256 => DepositCheckpoint)) public userDeposits;
    /// @dev maps period number => deposits
    mapping (uint256 => DistributionPeriodCheckpoint) public distributionPeriods;
    /// @dev indicates the period that the user last deposited into
    /// @dev used to determine whether or not a user's deposit needs to be rolled over
    mapping (address => uint256) public lastPeriodDeposited;

    constructor(address _rewardToken, address _stakingToken) {
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
    }

    function stake(uint256 _amount) external nonReentrant {
        require(_amount > 100, "insufficient_funds");
        IERC20(stakingToken).transferFrom(msg.sender, address(this), _amount);

        uint256 lastPeriodDepositAt = lastPeriodDeposited[msg.sender];
        uint256 currentPeriodId = currentDistributionPeriod;

        DepositCheckpoint memory dc;

        if (lastPeriodDepositAt != 0 && lastPeriodDepositAt < currentPeriodId) {
            // they have a previous deposit, but their deposit is an earlier distribution period
            // therefore we need to migrate their deposit balance to the current period
            dc = userDeposits[msg.sender][lastPeriodDepositAt];
        } else if (lastPeriodDepositAt != 0 && lastPeriodDepositAt == currentPeriodId) {
            // user is deposited into the current period, so copy balance information
            // from the current period
            dc = userDeposits[msg.sender][currentPeriodId];
        } else {
            revert("should not happen");
        }

        dc.depositedBalance += _amount;
        dc.lastDepositTime = block.timestamp;

    }
}

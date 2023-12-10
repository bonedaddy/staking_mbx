    pragma solidity ^0.8.0;
import "./interfaces/IERC20Lite.sol";
import "solmate/utils/ReentrancyGuard.sol";
import "forge-std/console.sol";

contract StakingCheckpoint is ReentrancyGuard {
    /// @dev number of seconds in a single day
    uint256 public constant SECONDS_PER_DAY = 86400;
    address immutable public owner;
    address immutable public rewardToken;
    address immutable public stakingToken;
    /// @dev indicates if the staking contract is paused
    bool public paused;
    /// @dev indicates if the staking contract has been initialized to begin reward distribution
    bool public initialized;
    /// @dev we start the distribution period at 1 to prevent issues
    /// @dev as a measure of making development slightly easier to avoid
    /// @dev having to handle staking distributions for the first period due to default values of 0
    uint256 public currentDistributionPeriod;

    /// @dev tracks a users current deposit 
    struct DepositInformation {
        /// @dev tracks their active deposit balance
        uint256 depositedBalance;
        /// @dev the time at which they deposited
        uint256 lastDepositTime;
        /// @dev indicates if the user has claimd their revenue
        bool revenueClaimed;
        /// @dev time at which the user last claimed rewards, used for
        ///      calculating the active rewards to be earned
        uint256 lastClaimTime;
        
    }

    /// @dev a checkpoint of their deposits
    struct DepositCheckpoint {
        uint256 amount;
        uint256 timestamp;
    }

    struct DistributionPeriod {
        /// @dev total deposited balance in the checkpoint
        /// @dev value is fixed after the period is finished
        uint256 totalDepositedBalance;
        /// @dev 0 value that is only set when the period is finished and revenue deposited
        uint256 revenueDeposited;
        /// @dev the timestamp the period started at
        uint256 periodStartedAt;
        /// @dev indicates if the distribution period is finished and has rolled over to a new one
        bool finished;

    }


    struct RevenueDistributionStats {
        /// @dev the time at which the revenue is deposited and rewards start
        uint256 startTime;
        /// @dev the time at which revenue finishes being distributed
        uint256 endTime;
        /// @dev the amount of revenue being distributed
        uint256 revenueToDistribute;
        /// @dev the rate at which rewards are emitted
        uint256 rewardRate;
    }

    /// @dev maps user address => distribution period => deposit
    mapping (address => mapping(uint256 => DepositInformation)) public userDeposits;
    /// @dev maps period number => deposits
    mapping (uint256 => DistributionPeriod) public distributionPeriods;
    /// @dev indicates the period that the user last deposited into
    /// @dev used to determine whether or not a user's deposit needs to be rolled over
    mapping (address => uint256) public lastPeriodDeposited;
    /// @dev tracks revenue distribution parameters
    mapping (uint256 => RevenueDistributionStats) public revenueStats;
    /// @dev records a checkpoint of all user deposits in a given period
    mapping (address => mapping(uint256 => DepositCheckpoint[])) internal depositCheckpoints;

    
    event Staked(
        address _depositor, 
        uint256 _amount, 
        uint256 _periodId, 
        uint256 _blockTime);

    event RevenueDistributed(
        uint256 _amount,
        uint256 _claimStart,
        uint256 _claimEnd,
        uint256 _rewardRate,
        uint256 _periodId
    );
    
    event RevenueClaimed(
        address _depositor,
        uint256 _amount,
        uint256 _rewardPerTokenStored,
        uint256 _periodTotalRevenue,
        uint256 _claimWindow,
        bool _revenueClaimed
    );

    constructor(address _rewardToken, address _stakingToken) {
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
        owner = msg.sender;
        paused = true;
    }

    /// @dev toggles the paused function moving from unpaused => paused, or paused => unpaused
    function togglePause() external nonReentrant {
        require(msg.sender == owner, "not_owner");
        paused = !paused;
    }

    function stake(uint256 _amount) external nonReentrant {
        require(_amount > 100, "insufficient_funds");
        require(!paused, "deposits_paused");

        uint256 lastPeriodDepositAt = lastPeriodDeposited[msg.sender];
        uint256 currentPeriodId = currentDistributionPeriod;


        DistributionPeriod memory dpc = distributionPeriods[currentPeriodId];
        // this case really shouldnt happen
        require(!dpc.finished, "period_finished");
        require(dpc.revenueDeposited == 0, "revenue_already_distributed");

        DepositInformation memory dc;

        if (lastPeriodDepositAt != 0 && lastPeriodDepositAt < currentPeriodId) {
            // they have a previous deposit, but their deposit is an earlier distribution period
            // therefore we need to migrate their deposit balance to the current period
            dc = userDeposits[msg.sender][lastPeriodDepositAt];
            // make sure to reset revenue claiemd in the current period
            dc.revenueClaimed = false;
        } else if (lastPeriodDepositAt != 0 && lastPeriodDepositAt == currentPeriodId) {
            // user is deposited into the current period, so copy balance information
            // from the current period
            //
            // deposit is for current period so revenue claimed will be false
            dc = userDeposits[msg.sender][currentPeriodId];
            require(!dc.revenueClaimed, "invalid_state");
        } else if (lastPeriodDepositAt == 0) {
            dc.depositedBalance = 0;
            dc.lastDepositTime = 0;
            dc.revenueClaimed = false;
        } else {
            revert("should not happen");
        }

        dc.depositedBalance += _amount;
        dc.lastDepositTime = block.timestamp;

        // update their last deposit period
        lastPeriodDeposited[msg.sender] = currentPeriodId;
        // update user deposit
        userDeposits[msg.sender][currentPeriodId] = dc;

        // update total deposits for thsi period
        dpc.totalDepositedBalance += _amount;
        // persist the updates
        distributionPeriods[currentPeriodId] = dpc;

        // record a deposit checkpoint
        depositCheckpoints[msg.sender][currentPeriodId].push(DepositCheckpoint({
            timestamp: block.timestamp,
            amount: _amount
        }));

        IERC20(stakingToken).transferFrom(msg.sender, address(this), _amount);

        emit Staked(msg.sender, _amount, currentPeriodId, block.timestamp);
    }

    function enableStaking() external nonReentrant {
        require(msg.sender == owner, "not_owner");
        require(!initialized, "already_initialized");
        require(currentDistributionPeriod == 0, "invalid_period");
        // set to 1
        currentDistributionPeriod = 1;
        // initialize the distribution period
        distributionPeriods[currentDistributionPeriod] = DistributionPeriod({
            totalDepositedBalance: 0,
            revenueDeposited: 0,
            periodStartedAt: block.timestamp,
            finished: false
        });
        // unpause staking
        paused = false;
    }

    function distributeRevenue(uint256 _amountToDistribute) external nonReentrant {
        IERC20 ercI = IERC20(rewardToken);
        require(ercI.balanceOf(msg.sender) >= _amountToDistribute, "insufficient_balance");

        // cache the id of the current period, which will become the last period
        uint256 previousPeriodId = currentDistributionPeriod;
        // increment the current period
        currentDistributionPeriod += 1;

        DistributionPeriod memory dpc = distributionPeriods[previousPeriodId];
        dpc.finished = true;
        dpc.revenueDeposited = _amountToDistribute;

        // update the parameters for the previous distribution period
        distributionPeriods[previousPeriodId] = dpc;

        // reset revenue finished status
        dpc.finished = false;
        // set revenue distributed to 0
        dpc.revenueDeposited = 0;
        // rollover the period start time
        dpc.periodStartedAt = block.timestamp;

        // the dpc as teh value of the current distribution period
        distributionPeriods[currentDistributionPeriod] = dpc;

        uint256 rewardRate = computeRewardRate(_amountToDistribute, 7 * SECONDS_PER_DAY);
        uint256 endTime = addDays(block.timestamp, 7);
        revenueStats[previousPeriodId] = RevenueDistributionStats({
            startTime: block.timestamp,
            endTime: endTime,
            revenueToDistribute: _amountToDistribute,
            rewardRate: rewardRate
        });

        

        ercI.transferFrom(msg.sender, address(this), _amountToDistribute);

        emit RevenueDistributed(
            _amountToDistribute,
            block.timestamp,
            endTime,
            rewardRate,
            previousPeriodId
        );
    }


    function claimRewards(uint256 _periodId) external nonReentrant {
        DepositInformation memory depositInfo = userDeposits[msg.sender][_periodId];
        require(!depositInfo.revenueClaimed, "revenue_already_claimed");
        require(depositInfo.depositedBalance > 0, "insufficient_funds");
        DistributionPeriod memory distributionPeriod = distributionPeriods[_periodId];
        RevenueDistributionStats memory rewardInfo = revenueStats[_periodId];
        require(rewardInfo.startTime != 0 && rewardInfo.endTime != 0, "invalid_reward_starts");
        require(distributionPeriod.finished, "period_not_finished");

        uint256 claimStartTime;
        if (depositInfo.lastClaimTime == 0) {
            // if the user hasn't claimed before set the last claim time to reward start time
            claimStartTime = rewardInfo.startTime;
        } else {
            claimStartTime = depositInfo.lastClaimTime;
        } 
        console.log("claimStartTime", claimStartTime);
        uint256 currentClaimTime;
        if (block.timestamp > rewardInfo.endTime) {
            // claiming after calculation period is over
            // so use the end time as the timestamp for calculation
            currentClaimTime = rewardInfo.endTime;
            // set their deposit info as having reward claimed
        } else {
            currentClaimTime = block.timestamp;
        }
        console.log("currentClaimTime", currentClaimTime);
        uint256 timeSinceLastClaim = currentClaimTime - claimStartTime;
        console.log("timeSinceLastClaim", timeSinceLastClaim);

        // divides the number of seconds the claim window is for by the amount of rewards per second
        uint256 rewardPerTokenStored = (timeSinceLastClaim * rewardInfo.rewardRate) / distributionPeriod.totalDepositedBalance;
        console.log("rewardPerTokenStored", rewardPerTokenStored);

        uint256 claimAmount = rewardPerTokenStored * depositInfo.depositedBalance;

        console.log("claimAmount", claimAmount);

        depositInfo.lastClaimTime = currentClaimTime;
        if (block.timestamp > rewardInfo.endTime) {
            // mark revenue as fully claimed
            depositInfo.revenueClaimed = true;
        }

        // persist deposit info
        userDeposits[msg.sender][_periodId] = depositInfo;

        emit RevenueClaimed(msg.sender, claimAmount, rewardPerTokenStored, rewardInfo.revenueToDistribute,timeSinceLastClaim, depositInfo.revenueClaimed);


    }

    /// @dev used to add _days to _timestamp
    function addDays(uint256 _timestamp, uint256 _days) internal pure returns (uint256 newTimestamp) {
        newTimestamp = _timestamp + (_days * SECONDS_PER_DAY);
        require(newTimestamp >= _timestamp);
    }

        /// @dev used to compute the rewardRate parameters which will distribute _totalRewardAmount over _totalDurationInSeconds
    function computeRewardRate(uint256 _totalRewardAmount, uint256 _totalDurationInSeconds)
        internal
        pure
        returns (uint256)
    {
        return (_totalRewardAmount) / _totalDurationInSeconds;
    }

    // Function to calculate the average balance of a user over the deposit window
    function calculateAverageBalance(
        address _depositor, 
        uint256 _periodNumber
    ) public view returns (uint256) {

        DepositCheckpoint[] memory deposits = depositCheckpoints[_depositor][_periodNumber];
        RevenueDistributionStats memory revenue = revenueStats[_periodNumber];
        //DistributionPeriod memory distributionPeriod = distributionPeriods[_periodNumber];
        
        uint256 timeWeightedBalance = 0;

        for (uint i = 0; i < deposits.length; i++) {
            uint256 depositTime = deposits[i].timestamp;
            uint256 depositAmount = deposits[i].amount;
            // this is likely incorrect
            uint256 timeHeld = revenue.endTime > depositTime ? revenue.endTime - depositTime : 0;
            timeWeightedBalance += depositAmount * timeHeld;
        }

        // Calculate the average balance
        return timeWeightedBalance;
    }
    
    /// @dev returns the users deposit for this particular information
    function getUserDeposit(address _depositor, uint256 _distributionPeriod) external view returns (DepositInformation memory) {
        return userDeposits[_depositor][_distributionPeriod];
    }

    /// @dev returns distribution information
    function getDistributionPeriod(uint256 _distributionPeriod) external view returns (DistributionPeriod memory) {
        return distributionPeriods[_distributionPeriod];
    }

    /// @dev returns revenue distribution stats for the given period
    function getRevenueStats(uint256 _distributionPeriod) external view returns (RevenueDistributionStats memory) {
        return revenueStats[_distributionPeriod];
    }

    /// @dev returns a deposit checkpoint for a depositor in the given distribution period
    function getDepositCheckpoints(address _depositor, uint256 _distributionPeriod) external view returns (DepositCheckpoint[] memory) {
        return depositCheckpoints[_depositor][_distributionPeriod];
    }
}

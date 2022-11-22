pragma solidity >=0.6.0 <0.7.0;

// Overview of the Staking dApp.
//
// For simplicity, we only expect a single user to interact with our staking dApp.
//
// We need to be able to deposit and withdraw from the Staker Contract.
//
// Staking is a single-use action, meaning once we stake we cannot re-stake again.
//
// Withdrawals from the contract removes the entire principal balance and any accrued interest.
//
// The Staker contract has an interest payout rate of 0.1 ETH for every second that the deposited ETH is eligible for interest accrument.
//
// Upon contract deployment, the Staker contract should begin witH 2 timestamp counters. The first deadline should be set to 2 minutes and the second set to 4 minutes.
//
// The 2-minute deadline dictates the period in which the staking user is able to deposit funds. (Between t=0 minutes and t=2 minutes, the staking user can deposit).
//
// All blocks that take place between the deposit of funds to the 2-minute deadline are valid for interest accrual.
//
// After the 2-minute withdrawal deadline has passed, the staking user is able to withdraw the entire principal balance and any accrued interest until the 4-minute deadline arrives.
//
// After the additional 2-minute window for withdrawals has passed, the user is blocked from withdrawing their funds since they timed out.
//
// If a staking user has funds left, we have one last function which we can call to "lock" the funds in an external contract that is already pre-installed
// in our Scaffold-Eth environment, ExampleExternalContract.sol
//

import "hardhat/console.sol";
import "./ExampleExternalContract.sol";

contract Staker {
    ExampleExternalContract public exampleExternalContract;

    constructor(address exampleExternalContractAddress) public {
        exampleExternalContract = ExampleExternalContract(
            exampleExternalContractAddress
        );
    }

    mapping(address => uint256) public balances;
    mapping(address => uint256) public depositTimestamps;

    // The reward rate sets the interest rate for the disbursement of ETH on the principal amount staked.
    // The withdrawal and claim deadlines set deadlines for the staking mechanics to begin/end.
    // A variable that we use to save the current block.
    //uint256 public constant rewardRatePerSecond = 0.1 ether;
    uint256 public constant rewardRatePerBlock = 0.1 ether;
    uint256 public withdrawalDeadline = block.timestamp + 120 seconds;
    uint256 public claimDeadline = block.timestamp + 240 seconds;
    uint256 public currentBlock = 0;

    // Events
    event Stake(address indexed sender, uint256 amount);
    event Received(address, uint256);
    event Execute(address indexed sender, uint256 amount);

    // Modifiers
    modifier withdrawalDeadlineReached(bool requireReached) {
        uint256 timeRemaining = withdrawalTimeLeft();
        if (requireReached) {
            require(timeRemaining == 0, "Withdrawal period is not reached yet");
        } else {
            require(timeRemaining > 0, "Withdrawal period has been reached");
        }
        _;
    }

    modifier claimDeadlineReached(bool requireReached) {
        uint256 timeRemaining = claimPeriodLeft();
        if (requireReached) {
            require(timeRemaining == 0, "Claim deadline is not reached yet");
        } else {
            require(timeRemaining > 0, "Claim deadline has been reached");
        }
        _;
    }

    // Calls on a function completed() from an external contract outside of Staker and checks to see
    // if it's returning true or false to confirm if that flag has been switched.
    modifier notCompleted() {
        bool completed = exampleExternalContract.completed();
        require(!completed, "Stake already completed!");
        _;
    }

    // The conditional simply checks whether the current time is greater than or less than the
    // deadlines dictated in the public variables section.
    // If the current time is greater than the pre-arranged deadlines, we know that the deadline
    // has passed and we return 0 to signify that a "state change" has occurred.
    // Otherwise, we simply return the remaining time before the deadline is reached.

    function withdrawalTimeLeft()
        public
        view
        returns (uint256 withdrawalTimeLeft)
    {
        if (block.timestamp >= withdrawalDeadline) {
            return (0);
        } else {
            return (withdrawalDeadline - block.timestamp);
        }
    }

    function claimPeriodLeft() public view returns (uint256 claimPeriodLeft) {
        if (block.timestamp >= claimDeadline) {
            return (0);
        } else {
            return (claimDeadline - block.timestamp);
        }
    }

    // Stake function for a user to stake ETH in the contract.
    function stake()
        public
        payable
        withdrawalDeadlineReached(false)
        claimDeadlineReached(false)
    {
        balances[msg.sender] = balances[msg.sender] + msg.value;
        depositTimestamps[msg.sender] = block.timestamp;
        emit Stake(msg.sender, msg.value);
    }

    // Withdraw function for a user to remove their staked ETH inclusive
    // of both the principle balance and any accrued interest.
    // ...
    // It checks to ensure that the person trying to withdraw ETH actually has a non-zero stake.
    // It calculates the amount of ETH owed in interest by taking the number of blocks that passed from deposit
    // to withdrawal and multiplying that by the interest constant.
    // It sets the user's balance staked ETH to 0 so that no double counting can occur.
    // It transfers the ETH from the smart contract back to the user's wallet.
    function withdraw()
        public
        withdrawalDeadlineReached(true)
        claimDeadlineReached(false)
        notCompleted
    {
        require(balances[msg.sender] > 0, "You have no balance to withdraw!");
        uint256 individualBalance = balances[msg.sender];
        uint256 indBalanceRewards = individualBalance +
            ((block.timestamp - depositTimestamps[msg.sender]) *
                rewardRatePerBlock);
        balances[msg.sender] = 0;
        // Transfer all ETH via call! (not transfer) cc: https://solidity-by-example.org/sending-ether
        (bool sent, bytes memory data) = msg.sender.call{
            value: indBalanceRewards
        }("");
        require(sent, "Withdrawal failed!");
    }

    // Allows any user to repatriate "unproductive" funds that are left in the staking contract
    // past the defined withdrawal period

    function execute() public claimDeadlineReached(true) notCompleted {
        uint256 contractBalance = address(this).balance;
        exampleExternalContract.complete{value: address(this).balance}();
    }
}

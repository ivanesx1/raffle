// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";


/**
 * @title A simple raffle contract
 * @author Ivan Sanchez
 * @notice This contract is for creating a simple raffle
 * @dev
 */
contract Raffle is VRFConsumerBaseV2, AutomationCompatibleInterface {
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UnkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        RaffleState raffleState
    );

    /** Type Declarations */

    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /** State Variables */

    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUMBER_WORDS = 1;

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /** Events */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);


    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
    }

    // external function is more gas efficient
    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        // Consider emit an event everytime a storage variable is updated.
        emit EnteredRaffle(msg.sender);
    }

    /**
     * @dev This is the function that Chainlink Automation Nodes calls
     * to see if it's time to perform an unkeep.
     * The following should be true for this to return true
     */
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasEth = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;

        upkeepNeeded = (timeHasPassed && isOpen && hasEth && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */) external override { 
        (bool unkeepNeeded, ) = checkUpkeep("");

        if (!unkeepNeeded) {
            revert Raffle__UnkeepNotNeeded(
                address(this).balance,
                s_players.length,
                RaffleState(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CALCULATING;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUMBER_WORDS
        );
        emit RequestedRaffleWinner(requestId);
    }

    // CEI: checks, effects and interations
    function fulfillRandomWords(
        uint256  /* _requestId */,
        uint256[] memory _randomWords
    ) internal override {
        // checks
        // effects(On our own contract)
        uint256 indexOfWinner = _randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit PickedWinner(winner);
        // interactions (in other contracts)
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /** Getter functions */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState){
        return s_raffleState;
    }

    function getPlayersLength() external view returns (uint256) {
        return s_players.length;
    }

    function getPlayer(uint256 indexPlayer) external view returns (address) {
        return s_players[indexPlayer];
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getlastTimestamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}

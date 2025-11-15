// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IReputationManager} from "../interfaces/IReputationManager.sol";
import {AssetTypes} from "../libraries/AssetTypes.sol";
import {Errors} from "../libraries/Errors.sol";
import {BaseMarketplaceContract} from "../base/BaseMarketplaceContract.sol";

/**
 * @title ReputationManager
 * @notice On-chain reputation system tracking user behavior
 * @dev Reputation affects marketplace access, dispute resolution, and trust
 *
 * Reputation Scoring:
 * - Base score: 100 points
 * - Successful sale (seller): +10 points
 * - Successful purchase (buyer): +5 points
 * - Verified asset: +20 points
 * - Dispute won: +10 points
 * - Dispute lost: -50 points
 * - Fraud detected: -100 points (permanent ban threshold)
 * - Inactivity: -1 point per 30 days
 *
 * Good Standing: Score >= 50
 * Banned: Score <= -100 or manually banned
 */
contract ReputationManager is IReputationManager, BaseMarketplaceContract {
    using AssetTypes for *;

    // ============================================
    //           STATE VARIABLES
    // ============================================

    /// @notice User address => reputation data
    mapping(address => Reputation) public reputations;

    /// @notice Authorized contracts that can update reputation (e.g., MarketplaceCore, EscrowManager, AuctionManager)
    mapping(address => bool) public authorizedContracts;

    int256 public constant POINTS_SUCCESSFUL_SALE = 10;
    int256 public constant POINTS_SUCCESSFUL_PURCHASE = 5;
    int256 public constant POINTS_VERIFIED_ASSET = 20;
    int256 public constant POINTS_DISPUTE_WON = 10;
    int256 public constant POINTS_DISPUTE_LOST = -50;
    int256 public constant POINTS_FRAUD = -100;
    int256 public constant POINTS_INACTIVITY_DECAY = -1;

    uint256 public constant INACTIVITY_PERIOD = 30 days;

    int256 public constant BAN_THRESHOLD = -100;

    constructor(address _roleManager) BaseMarketplaceContract(_roleManager) {}

    /**
     * @notice Update user reputation based on action
     * @param user User address
     * @param action Reputation action type
     */
    function updateReputation(address user, ReputationAction action) external {
        if (user == address(0)) revert Errors.InvalidUser();

        if (!authorizedContracts[msg.sender]) {
            revert Errors.NotAuthorized(msg.sender);
        }

        Reputation storage rep = reputations[user];

        // Initialize if first interaction
        if (rep.lastActivityTime == 0) {
            rep.score = 100; // Base score
            rep.lastActivityTime = uint32(block.timestamp);
        }

        // Apply inactivity decay before update
        _applyInactivityDecay(user);

        // Calculate points change
        int256 pointsChange = _getPointsForAction(action);

        // Update stats based on action
        if (action == ReputationAction.SuccessfulSale) {
            rep.successfulSales++;
        } else if (action == ReputationAction.SuccessfulPurchase) {
            rep.successfulPurchases++;
        } else if (action == ReputationAction.DisputeLost) {
            rep.disputesLost++;
        } else if (action == ReputationAction.DisputeWon) {
            rep.disputesWon++;
        } else if (action == ReputationAction.VerifiedAsset) {
            rep.verifiedAssets++;
        } else if (action == ReputationAction.FraudDetected) {
            // Permanent ban
            rep.isBanned = true;
        }

        // Update score
        rep.score += pointsChange;
        rep.lastActivityTime = uint32(block.timestamp);

        // Check if should be banned
        if (rep.score <= BAN_THRESHOLD && !rep.isBanned) {
            rep.isBanned = true;
            emit UserBanned(user, "Score below threshold", address(this));
        }

        emit ReputationUpdated(user, action, pointsChange, rep.score);
    }

    /**
     * @notice Manually ban a user (admin only)
     * @param user User to ban
     * @param reason Ban reason
     */
    function banUser(address user, string calldata reason) external onlyAdmin {
        Reputation storage rep = reputations[user];
        if (rep.isBanned) revert Errors.AlreadyBanned(user);

        rep.isBanned = true;

        emit UserBanned(user, reason, msg.sender);
    }

    /**
     * @notice Unban a user (admin only)
     * @param user User to unban
     */
    function unbanUser(address user) external onlyAdmin {
        Reputation storage rep = reputations[user];
        if (!rep.isBanned) revert Errors.NotBanned(user);

        rep.isBanned = false;

        emit UserUnbanned(user, msg.sender);
    }

    /**
     * @notice Add authorized contract that can update reputations
     * @param contractAddress Contract to authorize (e.g., MarketplaceCore, EscrowManager, AuctionManager)
     * @dev Only admin can add authorized contracts
     */
    function addAuthorizedContract(address contractAddress) external onlyAdmin {
        if (contractAddress == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (authorizedContracts[contractAddress]) {
            revert Errors.AlreadyAuthorized(contractAddress);
        }

        authorizedContracts[contractAddress] = true;

        emit AuthorizedContractAdded(contractAddress, msg.sender);
    }

    /**
     * @notice Remove authorized contract
     * @param contractAddress Contract to deauthorize
     * @dev Only admin can remove authorized contracts
     */
    function removeAuthorizedContract(address contractAddress) external onlyAdmin {
        if (!authorizedContracts[contractAddress]) {
            revert Errors.NotAuthorized(contractAddress);
        }

        authorizedContracts[contractAddress] = false;

        emit AuthorizedContractRemoved(contractAddress, msg.sender);
    }

    /**
     * @notice Check if contract is authorized to update reputations
     * @param contractAddress Contract to check
     * @return True if authorized
     */
    function isAuthorizedContract(address contractAddress) external view returns (bool) {
        return authorizedContracts[contractAddress];
    }

    // ============================================
    //           INTERNAL FUNCTIONS
    // ============================================

    function _getPointsForAction(ReputationAction action) internal pure returns (int256) {
        if (action == ReputationAction.SuccessfulSale) {
            return POINTS_SUCCESSFUL_SALE;
        }
        if (action == ReputationAction.SuccessfulPurchase) {
            return POINTS_SUCCESSFUL_PURCHASE;
        }
        if (action == ReputationAction.VerifiedAsset) {
            return POINTS_VERIFIED_ASSET;
        }
        if (action == ReputationAction.DisputeWon) return POINTS_DISPUTE_WON;
        if (action == ReputationAction.DisputeLost) return POINTS_DISPUTE_LOST;
        if (action == ReputationAction.FraudDetected) return POINTS_FRAUD;
        if (action == ReputationAction.InactivityDecay) {
            return POINTS_INACTIVITY_DECAY;
        }

        revert InvalidReputationAction();
    }

    function _applyInactivityDecay(address user) internal {
        Reputation storage rep = reputations[user];

        if (rep.lastActivityTime == 0) return;

        uint256 inactiveDays = (block.timestamp - rep.lastActivityTime) / INACTIVITY_PERIOD;

        if (inactiveDays > 0) {
            int256 decayPoints = int256(inactiveDays) * POINTS_INACTIVITY_DECAY;
            rep.score += decayPoints;
        }
    }

    // ============================================
    //          VIEW FUNCTIONS
    // ============================================

    function getReputation(address user) external view returns (Reputation memory) {
        return reputations[user];
    }

    function getReputationScore(address user) external view returns (int256) {
        Reputation memory rep = reputations[user];

        if (rep.lastActivityTime == 0) return 100; // New user

        uint256 inactiveDays = (block.timestamp - rep.lastActivityTime) / INACTIVITY_PERIOD;
        int256 decayPoints = int256(inactiveDays) * POINTS_INACTIVITY_DECAY;

        return rep.score + decayPoints;
    }

    function isGoodStanding(address user) external view returns (bool) {
        Reputation memory rep = reputations[user];

        if (rep.isBanned) return false;

        int256 currentScore = this.getReputationScore(user);
        return currentScore >= AssetTypes.MIN_GOOD_STANDING_SCORE;
    }

    function isBanned(address user) external view returns (bool) {
        return reputations[user].isBanned;
    }
}

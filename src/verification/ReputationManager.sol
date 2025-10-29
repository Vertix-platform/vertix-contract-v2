// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../interfaces/IReputationManager.sol";
import "../libraries/AssetTypes.sol";
import "../access/RoleManager.sol";

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
contract ReputationManager is IReputationManager {
    using AssetTypes for *;

    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice User address => reputation data
    mapping(address => Reputation) public reputations;

    /// @notice Reference to role manager
    RoleManager public immutable roleManager;

    /// @notice Reputation points per action
    int256 public constant POINTS_SUCCESSFUL_SALE = 10;
    int256 public constant POINTS_SUCCESSFUL_PURCHASE = 5;
    int256 public constant POINTS_VERIFIED_ASSET = 20;
    int256 public constant POINTS_DISPUTE_WON = 10;
    int256 public constant POINTS_DISPUTE_LOST = -50;
    int256 public constant POINTS_FRAUD = -100;
    int256 public constant POINTS_INACTIVITY_DECAY = -1;

    /// @notice Inactivity period for decay (30 days)
    uint256 public constant INACTIVITY_PERIOD = 30 days;

    /// @notice Ban threshold score
    int256 public constant BAN_THRESHOLD = -100;

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(address _roleManager) {
        require(_roleManager != address(0), "Invalid role manager");
        roleManager = RoleManager(_roleManager);
    }

    // ============================================
    // CORE FUNCTIONS
    // ============================================

    /**
     * @notice Update user reputation based on action
     * @param user User address
     * @param action Reputation action type
     */
    function updateReputation(address user, ReputationAction action) external {
        require(user != address(0), "Invalid user");

        // Only authorized contracts can update reputation
        // In production, check msg.sender is authorized contract
        bool isAuthorized = roleManager.hasRole(
            roleManager.ADMIN_ROLE(),
            msg.sender
        ) || msg.sender == address(this); // Allow internal calls
        require(isAuthorized, "Not authorized to update reputation");

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
    function banUser(address user, string calldata reason) external {
        require(
            roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender),
            "Not admin"
        );

        Reputation storage rep = reputations[user];
        require(!rep.isBanned, "Already banned");

        rep.isBanned = true;

        emit UserBanned(user, reason, msg.sender);
    }

    /**
     * @notice Unban a user (admin only)
     * @param user User to unban
     */
    function unbanUser(address user) external {
        require(
            roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender),
            "Not admin"
        );

        Reputation storage rep = reputations[user];
        require(rep.isBanned, "Not banned");

        rep.isBanned = false;

        emit UserUnbanned(user, msg.sender);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get full reputation data for user
     */
    function getReputation(
        address user
    ) external view returns (Reputation memory) {
        return reputations[user];
    }

    /**
     * @notice Get reputation score (with decay applied)
     */
    function getReputationScore(address user) external view returns (int256) {
        Reputation memory rep = reputations[user];

        if (rep.lastActivityTime == 0) return 100; // New user

        // Calculate decay
        uint256 inactiveDays = (block.timestamp - rep.lastActivityTime) /
            INACTIVITY_PERIOD;
        int256 decayPoints = int256(inactiveDays) * POINTS_INACTIVITY_DECAY;

        return rep.score + decayPoints;
    }

    /**
     * @notice Check if user is in good standing
     */
    function isGoodStanding(address user) external view returns (bool) {
        Reputation memory rep = reputations[user];

        if (rep.isBanned) return false;

        int256 currentScore = this.getReputationScore(user);
        return currentScore >= AssetTypes.MIN_GOOD_STANDING_SCORE;
    }

    /**
     * @notice Check if user is banned
     */
    function isBanned(address user) external view returns (bool) {
        return reputations[user].isBanned;
    }

    /**
     * @notice Get user statistics
     */
    function getUserStats(
        address user
    )
        external
        view
        returns (
            uint32 successfulSales,
            uint32 successfulPurchases,
            uint32 disputesLost,
            uint32 disputesWon,
            uint32 verifiedAssets
        )
    {
        Reputation memory rep = reputations[user];
        return (
            rep.successfulSales,
            rep.successfulPurchases,
            rep.disputesLost,
            rep.disputesWon,
            rep.verifiedAssets
        );
    }

    /**
     * @notice Calculate success rate
     * @return Success rate in basis points (0-10000)
     */
    function getSuccessRate(address user) external view returns (uint256) {
        Reputation memory rep = reputations[user];

        uint256 totalTransactions = uint256(rep.successfulSales) +
            uint256(rep.successfulPurchases);
        uint256 totalDisputes = uint256(rep.disputesLost) +
            uint256(rep.disputesWon);

        if (totalTransactions == 0) return 10000; // 100% for new users
        if (totalDisputes == 0) return 10000; // 100% if no disputes

        // Success rate = (total - disputes lost) / total
        uint256 successful = totalTransactions - uint256(rep.disputesLost);
        return (successful * 10000) / totalTransactions;
    }

    // ============================================
    // INTERNAL FUNCTIONS
    // ============================================

    /**
     * @notice Get points for a reputation action
     */
    function _getPointsForAction(
        ReputationAction action
    ) internal pure returns (int256) {
        if (action == ReputationAction.SuccessfulSale)
            return POINTS_SUCCESSFUL_SALE;
        if (action == ReputationAction.SuccessfulPurchase)
            return POINTS_SUCCESSFUL_PURCHASE;
        if (action == ReputationAction.VerifiedAsset)
            return POINTS_VERIFIED_ASSET;
        if (action == ReputationAction.DisputeWon) return POINTS_DISPUTE_WON;
        if (action == ReputationAction.DisputeLost) return POINTS_DISPUTE_LOST;
        if (action == ReputationAction.FraudDetected) return POINTS_FRAUD;
        if (action == ReputationAction.InactivityDecay)
            return POINTS_INACTIVITY_DECAY;

        revert InvalidReputationAction();
    }

    /**
     * @notice Apply inactivity decay to reputation
     */
    function _applyInactivityDecay(address user) internal {
        Reputation storage rep = reputations[user];

        if (rep.lastActivityTime == 0) return;

        uint256 inactiveDays = (block.timestamp - rep.lastActivityTime) /
            INACTIVITY_PERIOD;

        if (inactiveDays > 0) {
            int256 decayPoints = int256(inactiveDays) * POINTS_INACTIVITY_DECAY;
            rep.score += decayPoints;
        }
    }
}

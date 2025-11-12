// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IReputationManager {
    struct Reputation {
        int256 score; // Reputation score (can be negative)
        uint32 successfulSales; // As seller
        uint32 successfulPurchases; // As buyer
        uint32 disputesLost; // Disputes lost
        uint32 disputesWon; // Disputes won
        uint32 verifiedAssets; // Number of verified assets
        uint32 lastActivityTime; // Last transaction timestamp
        bool isBanned; // Permanently banned flag
    }

    enum ReputationAction {
        SuccessfulSale, // +10 points
        SuccessfulPurchase, // +5 points
        DisputeLost, // -50 points
        DisputeWon, // +10 points
        VerifiedAsset, // +20 points
        FraudDetected, // -100 points (permanent)
        InactivityDecay // -1 point per 30 days

    }

    // ============================================
    //                EVENTS
    // ============================================

    event ReputationUpdated(address indexed user, ReputationAction action, int256 pointsChange, int256 newScore);

    event UserBanned(address indexed user, string reason, address bannedBy);

    event UserUnbanned(address indexed user, address unbannedBy);

    event AuthorizedContractAdded(address indexed contractAddress, address indexed addedBy);

    event AuthorizedContractRemoved(address indexed contractAddress, address indexed removedBy);

    // ============================================
    //           ERRORS
    // ============================================

    error UserIsBanned(address user);
    error UnauthorizedUpdater(address caller);
    error InvalidReputationAction();

    // ============================================
    //                FUNCTIONS
    // ============================================

    function updateReputation(address user, ReputationAction action) external;

    function getReputation(address user) external view returns (Reputation memory);

    function getReputationScore(address user) external view returns (int256);

    function isGoodStanding(address user) external view returns (bool);

    function isBanned(address user) external view returns (bool);
}

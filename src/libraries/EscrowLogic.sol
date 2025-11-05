// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./AssetTypes.sol";
import "./Errors.sol";

/**
 * @title EscrowLogic
 * @notice Shared escrow calculation, validation, and business logic
 * @dev Provides reusable functions for escrow operations across contracts
 */
library EscrowLogic {
    using AssetTypes for AssetTypes.AssetType;

    // ============================================
    //           CUSTOM ERRORS
    // ============================================

    error InvalidBuyer(address buyer);
    error InvalidSeller(address seller);
    error BuyerAndSellerSame(address account);
    error InvalidAmount(uint256 amount);
    error DurationTooShort(uint256 provided, uint256 minimum);
    error DurationTooLong(uint256 provided, uint256 maximum);
    error InvalidEscrowState(
        AssetTypes.EscrowState current,
        AssetTypes.EscrowState required
    );
    error EscrowNotReleasable();
    error EscrowNotCancellable();
    error VerificationPeriodNotEnded(uint256 currentTime, uint256 deadline);

    // ============================================
    //        VALIDATION FUNCTIONS
    // ============================================

    /**
     * @notice Validate escrow creation parameters
     * @param buyer Address of the buyer
     * @param seller Address of the seller
     * @param amount Payment amount
     * @param duration Escrow duration in seconds
     *
     * @dev Reverts if any parameter is invalid
     */
    function validateEscrowParams(
        address buyer,
        address seller,
        uint256 amount,
        uint256 duration
    ) internal pure {
        // Validate addresses
        if (buyer == address(0)) revert InvalidBuyer(buyer);
        if (seller == address(0)) revert InvalidSeller(seller);
        if (buyer == seller) revert BuyerAndSellerSame(buyer);

        // Validate amount
        if (amount == 0) revert InvalidAmount(amount);
        if (amount > AssetTypes.MAX_LISTING_PRICE) revert InvalidAmount(amount);

        // Validate duration
        if (duration < AssetTypes.MIN_ESCROW_DURATION) {
            revert DurationTooShort(duration, AssetTypes.MIN_ESCROW_DURATION);
        }
        if (duration > AssetTypes.MAX_ESCROW_DURATION) {
            revert DurationTooLong(duration, AssetTypes.MAX_ESCROW_DURATION);
        }
    }

    /**
     * @notice Validate escrow state transition
     * @param currentState Current escrow state
     * @param newState Desired new state
     *
     * @dev Reverts if transition is invalid
     */
    function validateStateTransition(
        AssetTypes.EscrowState currentState,
        AssetTypes.EscrowState newState
    ) internal pure {
        if (!AssetTypes.isValidStateTransition(currentState, newState)) {
            revert InvalidEscrowState(currentState, newState);
        }
    }

    /**
     * @notice Validate hash parameter is not empty
     * @param hash The hash to validate
     */
    function validateHash(bytes32 hash) internal pure {
        if (hash == bytes32(0)) revert Errors.InvalidHash();
    }

    /**
     * @notice Validate metadata URI is not empty
     * @param uri The URI to validate
     */
    function validateMetadataURI(string calldata uri) internal pure {
        if (bytes(uri).length == 0) revert Errors.EmptyString("metadataURI");
        if (bytes(uri).length > 256)
            revert Errors.StringTooLong(bytes(uri).length, 256);
    }

    // ============================================
    //      DEADLINE CALCULATION FUNCTIONS
    // ============================================

    /**
     * @notice Calculate escrow deadlines based on duration
     * @param duration Escrow duration in seconds
     * @return releaseTime When funds can be auto-released
     * @return verificationDeadline Buyer verification deadline (50% of duration)
     * @return disputeDeadline Last moment to open dispute (7 days after release)
     *
     * @dev Verification deadline is midpoint to encourage early checking
     */
    function calculateDeadlines(
        uint256 duration
    )
        internal
        view
        returns (
            uint256 releaseTime,
            uint256 verificationDeadline,
            uint256 disputeDeadline
        )
    {
        releaseTime = block.timestamp + duration;
        verificationDeadline = block.timestamp + (duration / 2); // First half for verification
        disputeDeadline = releaseTime + 7 days; // 7 days grace period after release

        return (releaseTime, verificationDeadline, disputeDeadline);
    }

    /**
     * @notice Calculate escrow release time from creation timestamp
     * @param createdAt Escrow creation timestamp
     * @param duration Escrow duration
     * @return release Release timestamp
     */
    function calculateReleaseTime(
        uint256 createdAt,
        uint256 duration
    ) internal pure returns (uint256 release) {
        release = createdAt + duration;
        return release;
    }

    // ============================================
    //        RELEASE LOGIC FUNCTIONS
    // ============================================

    /**
     * @notice Check if escrow can be released
     * @param buyerConfirmed Whether buyer confirmed receipt
     * @param sellerDelivered Whether seller marked as delivered
     * @param releaseTime Scheduled release time
     * @return True if escrow can be released
     *
     * @dev Can release if:
     *      1. Buyer explicitly confirmed, OR
     *      2. Seller delivered AND release time passed (auto-release)
     */
    function canRelease(
        bool buyerConfirmed,
        bool sellerDelivered,
        uint256 releaseTime
    ) internal view returns (bool) {
        // Immediate release if buyer confirmed
        if (buyerConfirmed) return true;

        // Auto-release if seller delivered and deadline passed
        if (sellerDelivered && block.timestamp >= releaseTime) return true;

        return false;
    }

    /**
     * @notice Check if escrow release is overdue
     * @param sellerDelivered Whether seller marked as delivered
     * @param releaseTime Scheduled release time
     * @return True if release time has passed and seller delivered
     */
    function isReleaseOverdue(
        bool sellerDelivered,
        uint256 releaseTime
    ) internal view returns (bool) {
        return sellerDelivered && block.timestamp >= releaseTime;
    }

    /**
     * @notice Get time remaining until release
     * @param releaseTime Scheduled release time
     * @return Seconds remaining (0 if already passed)
     */
    function timeUntilRelease(
        uint256 releaseTime
    ) internal view returns (uint256) {
        if (block.timestamp >= releaseTime) return 0;
        return releaseTime - block.timestamp;
    }

    // ============================================
    //      CANCELLATION LOGIC FUNCTIONS
    // ============================================

    /**
     * @notice Check if escrow can be cancelled
     * @param sellerDelivered Whether seller has delivered
     * @param caller Address attempting to cancel
     * @param buyer Escrow buyer address
     * @return True if cancellation is allowed
     *
     * @dev Only buyer can cancel, and only before seller delivers
     */
    function canCancel(
        bool sellerDelivered,
        address caller,
        address buyer
    ) internal pure returns (bool) {
        return !sellerDelivered && caller == buyer;
    }

    /**
     * @notice Calculate amounts for cancellation
     * @param amount Original escrow amount
     * @param sellerDelivered Whether seller has delivered
     * @return buyerRefund Amount to refund buyer
     * @return sellerCompensation Amount to compensate seller (if work done)
     *
     * @dev If seller already delivered, they get 10% compensation for wasted effort
     */
    function calculateCancellationFees(
        uint256 amount,
        bool sellerDelivered
    ) internal pure returns (uint256 buyerRefund, uint256 sellerCompensation) {
        if (!sellerDelivered) {
            // Full refund if seller hasn't started
            return (amount, 0);
        }

        // Seller gets 10% compensation if they already did the work
        sellerCompensation =
            (amount * AssetTypes.CANCELLATION_PENALTY_BPS) /
            AssetTypes.BPS_DENOMINATOR;
        buyerRefund = amount - sellerCompensation;

        return (buyerRefund, sellerCompensation);
    }

    // ============================================
    //       DISPUTE LOGIC FUNCTIONS
    // ============================================

    /**
     * @notice Check if dispute can be opened
     * @param state Current escrow state
     * @param disputeDeadline Last moment to dispute
     * @return True if dispute can be opened
     *
     * @dev Can dispute if:
     *      1. Escrow is Active or Delivered, AND
     *      2. Dispute deadline hasn't passed
     */
    function canOpenDispute(
        AssetTypes.EscrowState state,
        uint256 disputeDeadline
    ) internal view returns (bool) {
        bool validState = (state == AssetTypes.EscrowState.Active ||
            state == AssetTypes.EscrowState.Delivered);
        bool beforeDeadline = block.timestamp <= disputeDeadline;

        return validState && beforeDeadline;
    }

    /**
     * @notice Check if caller can open dispute
     * @param caller Address attempting to dispute
     * @param buyer Buyer address
     * @param seller Seller address
     * @return True if caller is buyer or seller
     */
    function canCallerDispute(
        address caller,
        address buyer,
        address seller
    ) internal pure returns (bool) {
        return caller == buyer || caller == seller;
    }

    // ============================================
    //       TIME CALCULATION FUNCTIONS
    // ============================================

    /**
     * @notice Calculate escrow age in days
     * @param createdAt Creation timestamp
     * @return Age in days
     */
    function escrowAgeInDays(
        uint256 createdAt
    ) internal view returns (uint256) {
        if (block.timestamp < createdAt) return 0;
        return (block.timestamp - createdAt) / 1 days;
    }

    /**
     * @notice Calculate progress percentage
     * @param createdAt Creation timestamp
     * @param duration Total duration
     * @return Progress in basis points (0-10000)
     *
     * @dev Returns 10000 (100%) if duration has elapsed
     */
    function escrowProgress(
        uint256 createdAt,
        uint256 duration
    ) internal view returns (uint256) {
        if (block.timestamp < createdAt) return 0;

        uint256 elapsed = block.timestamp - createdAt;
        if (elapsed >= duration) return AssetTypes.BPS_DENOMINATOR; // 100%

        return (elapsed * AssetTypes.BPS_DENOMINATOR) / duration;
    }

    /**
     * @notice Check if escrow is in verification period
     * @param verificationDeadline Verification deadline timestamp
     * @return True if still in verification period
     */
    function isInVerificationPeriod(
        uint256 verificationDeadline
    ) internal view returns (bool) {
        return block.timestamp <= verificationDeadline;
    }

    /**
     * @notice Check if verification period has ended
     * @param verificationDeadline Verification deadline timestamp
     * @return True if verification period ended
     */
    function hasVerificationPeriodEnded(
        uint256 verificationDeadline
    ) internal view returns (bool) {
        return block.timestamp > verificationDeadline;
    }

    // ============================================
    //        UTILITY FUNCTIONS
    // ============================================

    /**
     * @notice Generate unique escrow ID
     * @param counter Current escrow counter
     * @param buyer Buyer address
     * @param seller Seller address
     * @return Deterministic escrow ID
     *
     * @dev Useful for off-chain indexing and tracking
     */
    function generateEscrowId(
        uint256 counter,
        address buyer,
        address seller
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(counter, buyer, seller));
    }

    /**
     * @notice Check if escrow is terminal state
     * @param state Current state
     * @return True if state is final (Completed, Cancelled, Refunded)
     */
    function isTerminalState(
        AssetTypes.EscrowState state
    ) internal pure returns (bool) {
        return
            state == AssetTypes.EscrowState.Completed ||
            state == AssetTypes.EscrowState.Cancelled ||
            state == AssetTypes.EscrowState.Refunded;
    }

    /**
     * @notice Check if escrow is active (can be modified)
     * @param state Current state
     * @return True if state is Active or Delivered
     */
    function isActiveState(
        AssetTypes.EscrowState state
    ) internal pure returns (bool) {
        return
            state == AssetTypes.EscrowState.Active ||
            state == AssetTypes.EscrowState.Delivered;
    }

    /**
     * @notice Validate escrow amount is reasonable for asset type
     * @param amount Payment amount
     * @param assetType Type of asset
     * @return True if amount seems reasonable
     *
     * @dev Basic sanity check to prevent obvious mistakes
     */
    function isReasonableAmount(
        uint256 amount,
        AssetTypes.AssetType assetType
    ) internal pure returns (bool) {
        // Minimum 0.001 ETH for any asset
        if (amount < 0.001 ether) return false;

        // Different maximums for different asset types
        if (AssetTypes.isSocialMediaType(assetType)) {
            return amount <= 10000 ether; // Max 10k ETH for social media
        }

        if (assetType == AssetTypes.AssetType.Website) {
            return amount <= 50000 ether; // Max 50k ETH for websites
        }

        // General max
        return amount <= AssetTypes.MAX_LISTING_PRICE;
    }
}

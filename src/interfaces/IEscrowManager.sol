// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetTypes} from "../libraries/AssetTypes.sol";

/**
 * @title IEscrowManager
 * @notice Interface for time-locked escrow management
 * @dev Central contract for handling off-chain asset sales with verification periods
 */
interface IEscrowManager {
    // ============================================
    //               STRUCTS
    // ============================================

    /**
     * @notice Escrow data structure
     * @dev Optimized for storage packing (4 slots)
     */
    struct Escrow {
        address buyer;
        uint96 amount; // (up to 79B ETH)
        address seller; //
        address paymentToken;
        // (address(0) for native)
        AssetTypes.AssetType assetType;
        AssetTypes.EscrowState state;
        uint32 createdAt;
        uint32 releaseTime;
        uint32 verificationDeadline;
        uint32 disputeDeadline;
        bool buyerConfirmed;
        bool sellerDelivered;
        bytes32 assetHash;
    }

    // ============================================
    //            EVENTS
    // ============================================

    /**
     * @notice Emitted when a new escrow is created
     * @param escrowId Unique escrow identifier
     * @param buyer Buyer address
     * @param seller Seller address
     * @param amount Payment amount
     * @param assetType Type of asset being sold
     * @param releaseTime When funds can be auto-released
     * @param metadataURI IPFS link to asset details
     */
    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed buyer,
        address indexed seller,
        uint256 amount,
        AssetTypes.AssetType assetType,
        uint256 releaseTime,
        string metadataURI
    );

    /**
     * @notice Emitted when seller marks asset as delivered
     * @param escrowId Escrow identifier
     * @param seller Seller address
     * @param deliveryTimestamp When marked delivered
     */
    event AssetDelivered(uint256 indexed escrowId, address indexed seller, uint256 deliveryTimestamp);

    /**
     * @notice Emitted when buyer confirms receipt
     * @param escrowId Escrow identifier
     * @param buyer Buyer address
     * @param confirmationTimestamp When confirmed
     */
    event AssetReceiptConfirmed(uint256 indexed escrowId, address indexed buyer, uint256 confirmationTimestamp);

    /**
     * @notice Emitted when escrow funds are released
     * @param escrowId Escrow identifier
     * @param seller Seller receiving funds
     * @param amount Total amount released
     * @param platformFee Fee collected by platform
     * @param sellerNet Net amount to seller after fees
     */
    event EscrowReleased(
        uint256 indexed escrowId, address indexed seller, uint256 amount, uint256 platformFee, uint256 sellerNet
    );

    /**
     * @notice Emitted when a dispute is opened
     * @param escrowId Escrow identifier
     * @param disputedBy Who opened the dispute (buyer or seller)
     * @param reason Dispute reason/description
     * @param timestamp When dispute opened
     */
    event DisputeOpened(uint256 indexed escrowId, address indexed disputedBy, string reason, uint256 timestamp);

    /**
     * @notice Emitted when a dispute is resolved
     * @param escrowId Escrow identifier
     * @param winner Who won the dispute
     * @param amount Amount awarded
     * @param resolver Admin who resolved
     */
    event DisputeResolved(uint256 indexed escrowId, address indexed winner, uint256 amount, address resolver);

    /**
     * @notice Emitted when escrow is cancelled
     * @param escrowId Escrow identifier
     * @param buyer Buyer receiving refund
     * @param refundAmount Amount refunded
     * @param sellerCompensation Compensation to seller (if applicable)
     */
    event EscrowCancelled(
        uint256 indexed escrowId, address indexed buyer, uint256 refundAmount, uint256 sellerCompensation
    );

    /**
     * @notice Emitted when platform fee is updated
     * @param oldFeeBps Previous fee in basis points
     * @param newFeeBps New fee in basis points
     * @param updatedBy Who updated the fee
     */
    event PlatformFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps, address updatedBy);

    // ============================================
    //              ERRORS
    // ============================================

    error InvalidEscrowId(uint256 escrowId);
    error UnauthorizedCaller(address caller, address required);
    error EscrowNotActive(uint256 escrowId, AssetTypes.EscrowState currentState);
    error EscrowAlreadyDelivered(uint256 escrowId);
    error EscrowNotDelivered(uint256 escrowId);
    error EscrowAlreadyConfirmed(uint256 escrowId);
    error EscrowNotReleasable(uint256 escrowId);
    error EscrowInDispute(uint256 escrowId);
    error EscrowNotDisputed(uint256 escrowId);
    error DisputeDeadlinePassed(uint256 escrowId);
    error InvalidDisputeResolution(uint256 amount, uint256 escrowAmount);
    error InsufficientPayment(uint256 provided, uint256 required);
    error InvalidFee(uint256 feeBps);

    // ============================================
    //           CORE FUNCTIONS
    // ============================================

    /**
     * @notice Create a new escrow for digital asset purchase
     * @param buyer Address of the asset buyer (explicitly passed for marketplace integrations)
     * @param seller Address of the asset seller
     * @param assetType Type of asset being sold
     * @param duration Escrow duration in seconds
     * @param assetHash Hash of asset details (for verification)
     * @param metadataURI IPFS link to full asset metadata
     * @return escrowId Unique identifier for the created escrow
     */
    function createEscrow(
        address buyer,
        address seller,
        AssetTypes.AssetType assetType,
        uint256 duration,
        bytes32 assetHash,
        string calldata metadataURI
    ) external payable returns (uint256 escrowId);

    /**
     * @notice Seller marks asset as delivered
     * @param escrowId Escrow identifier
     * @dev Can only be called by seller, moves state to Delivered
     */
    function markAssetDelivered(uint256 escrowId) external;

    /**
     * @notice Buyer confirms asset received and working
     * @param escrowId Escrow identifier
     * @dev Triggers immediate release of funds to seller
     */
    function confirmAssetReceived(uint256 escrowId) external;

    /**
     * @notice Release escrow funds to seller
     * @param escrowId Escrow identifier
     * @dev Can be called by anyone after conditions met:
     *      - Buyer confirmed, OR
     *      - Release time passed AND seller delivered
     */
    function releaseEscrow(uint256 escrowId) external;

    /**
     * @notice Open a dispute on an escrow
     * @param escrowId Escrow identifier
     * @param reason Description of the dispute
     * @dev Freezes escrow, can be called by buyer or seller
     */
    function openDispute(uint256 escrowId, string calldata reason) external;

    /**
     * @notice Resolve a disputed escrow (admin only)
     * @param escrowId Escrow identifier
     * @param winner Address to receive funds (buyer or seller)
     * @param amount Amount to award (can be partial)
     * @dev Remaining funds go to the other party
     */
    function resolveDispute(uint256 escrowId, address winner, uint256 amount) external;

    /**
     * @notice Cancel escrow and refund buyer
     * @param escrowId Escrow identifier
     * @dev Only buyer can cancel, only before seller delivers
     *      If seller already delivered, they get compensation
     */
    function cancelEscrow(uint256 escrowId) external;

    // ============================================
    //            VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get escrow details
     * @param escrowId Escrow identifier
     * @return Escrow struct with all details
     */
    function getEscrow(uint256 escrowId) external view returns (Escrow memory);

    /**
     * @notice Get all escrows for a buyer
     * @param buyer Buyer address
     * @return Array of escrow IDs
     */
    function getBuyerEscrows(address buyer) external view returns (uint256[] memory);

    /**
     * @notice Get all escrows for a seller
     * @param seller Seller address
     * @return Array of escrow IDs
     */
    function getSellerEscrows(address seller) external view returns (uint256[] memory);

    /**
     * @notice Get current platform fee
     * @return Fee in basis points (250 = 2.5%)
     */
    function platformFeeBps() external view returns (uint256);

    /**
     * @notice Get total number of escrows created
     * @return Escrow counter
     */
    function escrowCounter() external view returns (uint256);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetTypes} from "../libraries/AssetTypes.sol";

/**
 * @title IOfferManager
 * @notice Interface for offer management system
 * @dev Handles offers and counter-offers for all asset types (NFTs and off-chain assets)
 */
interface IOfferManager {
    // ============================================
    //                STRUCTS
    // ============================================

    /**
     * @notice Offer data structure (storage optimized)
     */
    struct Offer {
        address buyer; // Person making the offer (buyer)
        uint96 amount; // Offer amount
        address seller; // Original seller
        uint32 createdAt; // Offer creation timestamp
        uint32 expiresAt; // Offer expiration timestamp
        bool active; // Offer is active
        bool accepted; // Offer has been accepted
        uint256 listingId; // Reference to marketplace listing
        AssetTypes.AssetType assetType;
    }

    // ============================================
    //                EVENTS
    // ============================================

    /**
     * @notice Emitted when an offer is made
     */
    event OfferMade(
        uint256 indexed offerId,
        uint256 indexed listingId,
        address indexed buyer,
        address seller,
        uint256 amount,
        uint256 expiresAt,
        AssetTypes.AssetType assetType
    );

    /**
     * @notice Emitted when an offer is accepted
     */
    event OfferAccepted(
        uint256 indexed offerId, uint256 indexed listingId, address indexed seller, address buyer, uint256 amount
    );

    /**
     * @notice Emitted when an offer is rejected
     */
    event OfferRejected(
        uint256 indexed offerId, uint256 indexed listingId, address indexed seller, address buyer, string reason
    );

    /**
     * @notice Emitted when an offer is cancelled by buyer
     */
    event OfferCancelled(
        uint256 indexed offerId, uint256 indexed listingId, address indexed buyer, uint256 refundAmount
    );

    /**
     * @notice Emitted when an offer expires
     */
    event OfferExpired(uint256 indexed offerId, uint256 indexed listingId, address indexed buyer);

    /**
     * @notice Emitted when offer funds are refunded
     */
    event OfferRefunded(uint256 indexed offerId, address indexed buyer, uint256 amount);

    // ============================================
    //                   ERRORS
    // ============================================

    error InvalidOfferId(uint256 offerId);
    error InvalidListingId(uint256 listingId);
    error OfferNotActive(uint256 offerId);
    error OfferExpiredError(uint256 offerId, uint256 expiresAt);
    error OfferAlreadyAccepted(uint256 offerId);
    error UnauthorizedSeller(address caller, address seller);
    error UnauthorizedBuyer(address caller, address buyer);
    error InvalidOfferAmount(uint256 amount);
    error InvalidOfferDuration(uint256 duration);
    error CannotOfferOwnListing(address buyer);
    error ListingNotActive(uint256 listingId);
    error InsufficientOfferAmount();
    error TransferFailed(address recipient, uint256 amount);
    error ListingAlreadySold(uint256 listingId);
    error NFTNotApproved(address nftContract, uint256 tokenId);
    error BatchSizeTooLarge(uint256 provided, uint256 maximum);

    // ============================================
    //                FUNCTIONS
    // ============================================

    /**
     * @notice Make an offer on a listing
     * @param listingId Listing identifier from MarketplaceCore
     * @param duration Offer validity duration in seconds
     * @return offerId Unique offer identifier
     * @dev Offer amount is msg.value, funds are locked until offer resolved
     */
    function makeOffer(uint256 listingId, uint256 duration) external payable returns (uint256 offerId);

    /**
     * @notice Accept an offer (seller only)
     * @param offerId Offer identifier
     * @dev Triggers asset transfer (NFT instant, others create escrow)
     */
    function acceptOffer(uint256 offerId) external;

    /**
     * @notice Reject an offer (seller only)
     * @param offerId Offer identifier
     * @param reason Reason for rejection
     * @dev Refunds buyer immediately
     */
    function rejectOffer(uint256 offerId, string calldata reason) external;

    /**
     * @notice Cancel an offer (buyer only)
     * @param offerId Offer identifier
     * @dev Can only cancel active, non-accepted offers
     */
    function cancelOffer(uint256 offerId) external;

    /**
     * @notice Claim refund for expired offer
     * @param offerId Offer identifier
     * @dev Anyone can call to clean up expired offers
     */
    function claimExpiredOffer(uint256 offerId) external;

    /**
     * @notice Batch cancel multiple offers
     * @param offerIds Array of offer identifiers
     * @dev Useful for buyer to cancel multiple offers at once
     */
    function batchCancelOffers(uint256[] calldata offerIds) external;

    /**
     * @notice Claim refund for offer on sold/cancelled listing
     * @param offerId Offer identifier
     * @dev Allows buyers to claim refunds when their offer becomes invalid
     */
    function claimRefundForInvalidOffer(uint256 offerId) external;

    // ============================================
    //             VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get offer details
     * @param offerId Offer identifier
     * @return offer Offer struct
     */
    function getOffer(uint256 offerId) external view returns (Offer memory offer);

    /**
     * @notice Get all offers for a listing
     * @param listingId Listing identifier
     * @return Array of offer IDs
     */
    function getListingOffers(uint256 listingId) external view returns (uint256[] memory);

    /**
     * @notice Get active offers for a listing
     * @param listingId Listing identifier
     * @return Array of active offer IDs
     */
    function getActiveListingOffers(uint256 listingId) external view returns (uint256[] memory);

    /**
     * @notice Get offers made by an address
     * @param buyer Buyer address
     * @return Array of offer IDs
     */
    function getBuyerOffers(address buyer) external view returns (uint256[] memory);

    /**
     * @notice Get offers received by a seller
     * @param seller Seller address
     * @return Array of offer IDs
     */
    function getSellerOffers(address seller) external view returns (uint256[] memory);

    /**
     * @notice Check if offer is active
     * @param offerId Offer identifier
     * @return True if offer is active and not expired
     */
    function isOfferActive(uint256 offerId) external view returns (bool);

    /**
     * @notice Check if offer has expired
     * @param offerId Offer identifier
     * @return True if offer expiration time has passed
     */
    function hasOfferExpired(uint256 offerId) external view returns (bool);
}

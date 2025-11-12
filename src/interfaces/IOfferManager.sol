// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetTypes} from "../libraries/AssetTypes.sol";

interface IOfferManager {
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

    event OfferMade(
        uint256 indexed offerId,
        uint256 indexed listingId,
        address indexed buyer,
        address seller,
        uint256 amount,
        uint256 expiresAt,
        AssetTypes.AssetType assetType
    );

    event OfferAccepted(
        uint256 indexed offerId, uint256 indexed listingId, address indexed seller, address buyer, uint256 amount
    );

    event OfferRejected(
        uint256 indexed offerId, uint256 indexed listingId, address indexed seller, address buyer, string reason
    );

    event OfferCancelled(
        uint256 indexed offerId, uint256 indexed listingId, address indexed buyer, uint256 refundAmount
    );

    event OfferExpired(uint256 indexed offerId, uint256 indexed listingId, address indexed buyer);

    event OfferRefunded(uint256 indexed offerId, address indexed buyer, uint256 amount);

    event OfferInvalidated(uint256 indexed offerId, uint256 indexed listingId, address indexed buyer, uint256 amount);

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
    error NoRefundAvailable(uint256 offerId);

    // ============================================
    //                FUNCTIONS
    // ============================================

    function makeOffer(uint256 listingId, uint256 duration) external payable returns (uint256 offerId);

    function acceptOffer(uint256 offerId) external;

    function rejectOffer(uint256 offerId, string calldata reason) external;

    function cancelOffer(uint256 offerId) external;

    function claimExpiredOffer(uint256 offerId) external;

    function batchCancelOffers(uint256[] calldata offerIds) external;

    function claimRefundForInvalidOffer(uint256 offerId) external;

    function claimFailedRefund(uint256 offerId) external;

    // ============================================
    //             VIEW FUNCTIONS
    // ============================================

    function getOffer(uint256 offerId) external view returns (Offer memory offer);

    function getListingOffers(uint256 listingId) external view returns (uint256[] memory);

    function getActiveListingOffers(uint256 listingId) external view returns (uint256[] memory);

    function getBuyerOffers(address buyer) external view returns (uint256[] memory);

    function getSellerOffers(address seller) external view returns (uint256[] memory);

    function isOfferActive(uint256 offerId) external view returns (bool);

    function hasOfferExpired(uint256 offerId) external view returns (bool);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IOfferManager} from "../interfaces/IOfferManager.sol";
import {IMarketplace} from "../interfaces/IMarketplace.sol";
import {IEscrowManager} from "../interfaces/IEscrowManager.sol";
import {AssetTypes} from "../libraries/AssetTypes.sol";
import {PercentageMath} from "../libraries/PercentageMath.sol";
import {Errors} from "../libraries/Errors.sol";
import {NFTOperations} from "../libraries/NFTOperations.sol";
import {PaymentUtils} from "../libraries/PaymentUtils.sol";
import {FeeDistributor} from "../core/FeeDistributor.sol";
import {BaseMarketplaceContract} from "../base/BaseMarketplaceContract.sol";

/**
 * @title OfferManager
 * @notice Manages offers and counter-offers for all asset types on Vertix marketplace
 * @dev Handles offers for both NFTs (instant transfer) and off-chain assets (via escrow)
 *
 * Features:
 * - Make offer on any listing (below/above asking price)
 * - Multiple simultaneous offers per listing
 * - Time-limited offers with expiration
 * - Seller can accept/reject offers
 * - Buyer can cancel active offers
 * - Automatic routing: NFT = instant transfer, others = escrow creation
 * - Locked funds when offer made (ensures buyer has funds)
 */
contract OfferManager is IOfferManager, BaseMarketplaceContract {
    using PercentageMath for uint256;
    using AssetTypes for AssetTypes.AssetType;

    uint256 public offerCounter;

    uint256 public platformFeeBps;

    uint256 public constant MAX_BATCH_CANCEL_SIZE = 50;

    uint256 public constant MIN_OFFER_AMOUNT = 0.001 ether;

    /// @notice Mapping from offer ID to offer data
    mapping(uint256 => Offer) public offers;

    /// @notice Mapping listingId => array of offer IDs
    mapping(uint256 => uint256[]) public listingOffers;

    /// @notice Mapping buyer => array of offer IDs
    mapping(address => uint256[]) public buyerOffers;

    /// @notice Mapping seller => array of offer IDs
    mapping(address => uint256[]) public sellerOffers;

    /// @notice Mapping offer ID => whether refund is available for claim
    mapping(uint256 => bool) public offerRefundAvailable;

    FeeDistributor public immutable feeDistributor;
    IMarketplace public immutable marketplace;
    IEscrowManager public immutable escrowManager;

    constructor(
        address _roleManager,
        address _feeDistributor,
        address _marketplace,
        address _escrowManager,
        uint256 _platformFeeBps
    )
        BaseMarketplaceContract(_roleManager)
    {
        if (_feeDistributor == address(0)) {
            revert Errors.InvalidFeeDistributor();
        }
        if (_marketplace == address(0)) revert Errors.InvalidMarketplace();
        if (_escrowManager == address(0)) revert Errors.InvalidEscrowManager();

        PercentageMath.validateBps(_platformFeeBps, AssetTypes.MAX_FEE_BPS);

        feeDistributor = FeeDistributor(payable(_feeDistributor));
        marketplace = IMarketplace(_marketplace);
        escrowManager = IEscrowManager(_escrowManager);
        platformFeeBps = _platformFeeBps;

        emit PlatformFeeUpdated(0, _platformFeeBps);
    }

    // ============================================
    //                EVENTS
    // ============================================

    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);

    /**
     * @notice Make an offer on a listing
     * @param listingId Listing identifier from MarketplaceCore
     * @param duration Offer validity duration in seconds
     * @return offerId Unique offer identifier
     * @dev Offer amount is msg.value, funds are locked in contract
     */
    function makeOffer(
        uint256 listingId,
        uint256 duration
    )
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 offerId)
    {
        if (msg.value < MIN_OFFER_AMOUNT || msg.value > AssetTypes.MAX_LISTING_PRICE) {
            revert InvalidOfferAmount(msg.value);
        }

        if (!AssetTypes.isValidOfferDuration(duration)) {
            revert InvalidOfferDuration(duration);
        }

        IMarketplace.Listing memory listing = marketplace.getListing(listingId);

        if (listing.listingId == 0) {
            revert InvalidListingId(listingId);
        }

        if (listing.status != AssetTypes.ListingStatus.Active) {
            revert ListingNotActive(listingId);
        }

        if (msg.sender == listing.seller) {
            revert CannotOfferOwnListing(msg.sender);
        }

        offerCounter++;
        offerId = offerCounter;

        uint256 expiresAt = block.timestamp + duration;

        offers[offerId] = Offer({
            buyer: msg.sender,
            amount: uint96(msg.value),
            seller: listing.seller,
            createdAt: uint32(block.timestamp),
            expiresAt: uint32(expiresAt),
            active: true,
            accepted: false,
            listingId: listingId,
            assetType: listing.assetType
        });

        listingOffers[listingId].push(offerId);
        buyerOffers[msg.sender].push(offerId);
        sellerOffers[listing.seller].push(offerId);

        emit OfferMade(
            offerId,
            listingId,
            msg.sender, // buyer
            listing.seller,
            msg.value,
            expiresAt,
            listing.assetType
        );

        return offerId;
    }

    /**
     * @notice Accept an offer (seller only)
     * @param offerId Offer identifier
     * @dev Triggers asset transfer (NFT instant, others create escrow)
     */
    function acceptOffer(uint256 offerId) external whenNotPaused nonReentrant {
        Offer storage offer = offers[offerId];

        _validateOfferExists(offerId);

        if (!offer.active) {
            revert OfferNotActive(offerId);
        }

        if (offer.accepted) {
            revert OfferAlreadyAccepted(offerId);
        }

        if (msg.sender != offer.seller) {
            revert UnauthorizedSeller(msg.sender, offer.seller);
        }

        if (block.timestamp >= offer.expiresAt) {
            revert OfferExpiredError(offerId, offer.expiresAt);
        }

        IMarketplace.Listing memory listing = marketplace.getListing(offer.listingId);

        if (listing.status != AssetTypes.ListingStatus.Active) {
            revert ListingAlreadySold(offer.listingId);
        }

        if (AssetTypes.isNFTType(offer.assetType)) {
            IMarketplace.NFTDetails memory nft = marketplace.getNFTDetails(offer.listingId);

            if (nft.standard == AssetTypes.TokenStandard.ERC721) {
                address approved = IERC721(nft.nftContract).getApproved(nft.tokenId);
                bool isApprovedForAll = IERC721(nft.nftContract).isApprovedForAll(msg.sender, address(this));
                if (approved != address(this) && !isApprovedForAll) {
                    revert NFTNotApproved(nft.nftContract, nft.tokenId);
                }
            } else {
                if (!IERC1155(nft.nftContract).isApprovedForAll(msg.sender, address(this))) {
                    revert NFTNotApproved(nft.nftContract, nft.tokenId);
                }
            }
        }

        offer.active = false;
        offer.accepted = true;

        // Route based on asset type
        if (AssetTypes.isNFTType(offer.assetType)) {
            _handleNFTOfferAcceptance(offer);
        } else {
            _handleOffChainOfferAcceptance(offer, listing);
        }

        _refundOtherOffersOnListing(offer.listingId, offerId);

        emit OfferAccepted(offerId, offer.listingId, msg.sender, offer.buyer, offer.amount);
    }

    /**
     * @notice Reject an offer (seller only)
     * @param offerId Offer identifier
     * @param reason Reason for rejection
     * @dev Refunds buyer immediately
     */
    function rejectOffer(uint256 offerId, string calldata reason) external whenNotPaused nonReentrant {
        Offer storage offer = offers[offerId];

        _validateOfferExists(offerId);

        if (!offer.active) {
            revert OfferNotActive(offerId);
        }

        if (msg.sender != offer.seller) {
            revert UnauthorizedSeller(msg.sender, offer.seller);
        }

        offer.active = false;

        uint256 refundAmount = offer.amount;
        PaymentUtils.safeTransferETH(offer.buyer, refundAmount);

        emit OfferRejected(offerId, offer.listingId, msg.sender, offer.buyer, reason);
        emit OfferRefunded(offerId, offer.buyer, refundAmount);
    }

    /**
     * @notice Cancel an offer (buyer only)
     * @param offerId Offer identifier
     * @dev Can only cancel active, non-accepted offers
     */
    function cancelOffer(uint256 offerId) external whenNotPaused nonReentrant {
        Offer storage offer = offers[offerId];

        _validateOfferExists(offerId);

        if (!offer.active) {
            revert OfferNotActive(offerId);
        }

        if (msg.sender != offer.buyer) {
            revert UnauthorizedBuyer(msg.sender, offer.buyer);
        }

        offer.active = false;

        // Refund buyer
        uint256 refundAmount = offer.amount;
        PaymentUtils.safeTransferETH(offer.buyer, refundAmount);

        emit OfferCancelled(offerId, offer.listingId, msg.sender, refundAmount);
        emit OfferRefunded(offerId, offer.buyer, refundAmount);
    }

    /**
     * @notice Claim refund for expired offer
     * @param offerId Offer identifier
     * @dev Anyone can call to clean up expired offers
     */
    function claimExpiredOffer(uint256 offerId) external whenNotPaused nonReentrant {
        Offer storage offer = offers[offerId];

        _validateOfferExists(offerId);

        if (!offer.active) {
            revert OfferNotActive(offerId);
        }

        if (block.timestamp < offer.expiresAt) {
            revert OfferNotActive(offerId);
        }

        offer.active = false;

        uint256 refundAmount = offer.amount;
        PaymentUtils.safeTransferETH(offer.buyer, refundAmount);

        emit OfferExpired(offerId, offer.listingId, offer.buyer);
        emit OfferRefunded(offerId, offer.buyer, refundAmount);
    }

    /**
     * @notice Batch cancel multiple offers
     * @param offerIds Array of offer identifiers
     * @dev Useful for buyer to cancel multiple offers at once
     */
    function batchCancelOffers(uint256[] calldata offerIds) external nonReentrant {
        if (offerIds.length > MAX_BATCH_CANCEL_SIZE) {
            revert BatchSizeTooLarge(offerIds.length, MAX_BATCH_CANCEL_SIZE);
        }

        for (uint256 i = 0; i < offerIds.length; i++) {
            uint256 offerId = offerIds[i];
            Offer storage offer = offers[offerId];

            // Skip if invalid or already inactive
            if (offerId == 0 || offerId > offerCounter || !offer.active || msg.sender != offer.buyer) {
                continue;
            }

            offer.active = false;

            uint256 refundAmount = offer.amount;
            PaymentUtils.safeTransferETH(offer.buyer, refundAmount);

            emit OfferCancelled(offerId, offer.listingId, msg.sender, refundAmount);
            emit OfferRefunded(offerId, offer.buyer, refundAmount);
        }
    }

    // ============================================
    //          INTERNAL FUNCTIONS
    // ============================================

    /**
     * @notice Handle NFT offer acceptance (instant transfer)
     */
    function _handleNFTOfferAcceptance(Offer memory offer) internal {
        IMarketplace.NFTDetails memory nft = marketplace.getNFTDetails(offer.listingId);

        if (nft.standard == AssetTypes.TokenStandard.ERC721) {
            IERC721(nft.nftContract).safeTransferFrom(offer.seller, offer.buyer, nft.tokenId);
        } else {
            IERC1155(nft.nftContract).safeTransferFrom(offer.seller, offer.buyer, nft.tokenId, nft.quantity, "");
        }

        // Calculate and distribute payment
        uint256 amount = offer.amount;

        // Calculate platform fee
        uint256 platformFee = amount.percentOf(platformFeeBps);
        uint256 sellerNet = amount - platformFee;

        // Transfer platform fee
        PaymentUtils.safeTransferETH(address(feeDistributor), platformFee);

        // Transfer seller net
        PaymentUtils.safeTransferETH(offer.seller, sellerNet);

        marketplace.markListingAsSold(offer.listingId);
    }

    /**
     * @notice Handle off-chain asset offer acceptance (create escrow)
     */
    function _handleOffChainOfferAcceptance(Offer memory offer, IMarketplace.Listing memory listing) internal {
        uint256 escrowDuration = AssetTypes.recommendedEscrowDuration(offer.assetType);

        escrowManager.createEscrow{value: offer.amount}(
            offer.buyer, // buyer (the person who made the offer)
            offer.seller, // seller
            offer.assetType, // assetType
            escrowDuration, // duration
            listing.assetHash, // assetHash
            listing.metadataURI // metadataURI
        );
    }

    /**
     * @notice Claim refund for offer on sold/cancelled listing
     * @param offerId Offer identifier
     * @dev Allows buyers to claim refunds when their offer becomes invalid
     */
    function claimRefundForInvalidOffer(uint256 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];

        _validateOfferExists(offerId);

        if (!offer.active) {
            revert OfferNotActive(offerId);
        }

        if (msg.sender != offer.buyer) {
            revert UnauthorizedBuyer(msg.sender, offer.buyer);
        }

        IMarketplace.Listing memory listing = marketplace.getListing(offer.listingId);

        if (listing.status != AssetTypes.ListingStatus.Active) {
            offer.active = false;

            // Refund buyer
            uint256 refundAmount = offer.amount;
            PaymentUtils.safeTransferETH(offer.buyer, refundAmount);

            emit OfferCancelled(offerId, offer.listingId, msg.sender, refundAmount);
            emit OfferRefunded(offerId, offer.buyer, refundAmount);
        } else {
            revert OfferNotActive(offerId);
        }
    }

    /**
     * @notice Claim refund for an offer where automatic refund failed
     * @param offerId Offer identifier
     * @dev This allows buyers to manually claim refunds when automatic transfer fails
     * @dev Common scenarios: buyer is a contract that reverts, or has high gas requirements
     */
    function claimFailedRefund(uint256 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];

        _validateOfferExists(offerId);

        if (msg.sender != offer.buyer) {
            revert UnauthorizedBuyer(msg.sender, offer.buyer);
        }

        if (!offerRefundAvailable[offerId]) {
            revert NoRefundAvailable(offerId);
        }

        offerRefundAvailable[offerId] = false;

        uint256 refundAmount = offer.amount;
        PaymentUtils.safeTransferETH(offer.buyer, refundAmount);

        emit OfferRefunded(offerId, offer.buyer, refundAmount);
    }

    /**
     * @notice Refund all other active offers on a listing (except the accepted one)
     * @param listingId Listing ID
     * @param acceptedOfferId The offer ID that was accepted (skip this one)
     * @dev Called when an offer is accepted to invalidate competing offers
     * @dev Uses pull-over-push pattern: tries to refund, but allows manual claim if transfer fails
     */
    function _refundOtherOffersOnListing(uint256 listingId, uint256 acceptedOfferId) internal {
        uint256[] memory allOffers = listingOffers[listingId];

        for (uint256 i = 0; i < allOffers.length; i++) {
            uint256 currentOfferId = allOffers[i];

            if (currentOfferId == acceptedOfferId) {
                continue;
            }

            Offer storage offer = offers[currentOfferId];

            if (!offer.active) {
                continue;
            }

            offer.active = false;

            uint256 refundAmount = offer.amount;
            (bool success,) = offer.buyer.call{value: refundAmount, gas: 100_000}("");

            if (success) {
                emit OfferRefunded(currentOfferId, offer.buyer, refundAmount);
            } else {
                // If refund fails (e.g., buyer is a contract that reverts),
                // mark refund as available for manual claim
                offerRefundAvailable[currentOfferId] = true;

                emit OfferInvalidated(currentOfferId, listingId, offer.buyer, refundAmount);
            }
        }
    }

    /**
     * @notice Validate offer exists
     */
    function _validateOfferExists(uint256 offerId) internal view {
        if (offerId == 0 || offerId > offerCounter) {
            revert InvalidOfferId(offerId);
        }
    }

    // ============================================
    //             VIEW FUNCTIONS
    // ============================================

    function getOffer(uint256 offerId) external view returns (Offer memory) {
        _validateOfferExists(offerId);
        return offers[offerId];
    }

    function getListingOffers(uint256 listingId) external view returns (uint256[] memory) {
        return listingOffers[listingId];
    }

    function getBuyerOffers(address buyer) external view returns (uint256[] memory) {
        return buyerOffers[buyer];
    }

    function getSellerOffers(address seller) external view returns (uint256[] memory) {
        return sellerOffers[seller];
    }

    function isOfferActive(uint256 offerId) external view returns (bool) {
        return _isOfferActiveInternal(offerId);
    }

    function _isOfferActiveInternal(uint256 offerId) internal view returns (bool) {
        if (offerId == 0 || offerId > offerCounter) return false;

        Offer memory offer = offers[offerId];
        return offer.active && block.timestamp < offer.expiresAt;
    }

    function hasOfferExpired(uint256 offerId) external view returns (bool) {
        if (offerId == 0 || offerId > offerCounter) return false;

        Offer memory offer = offers[offerId];
        return block.timestamp >= offer.expiresAt;
    }

    function updatePlatformFee(uint256 newFeeBps) external onlyFeeManager {
        PercentageMath.validateBps(newFeeBps, AssetTypes.MAX_FEE_BPS);

        uint256 oldFee = platformFeeBps;
        platformFeeBps = newFeeBps;

        emit PlatformFeeUpdated(oldFee, newFeeBps);
    }

    function getActiveListingOffers(uint256 listingId) external view returns (uint256[] memory) {
        uint256[] memory allOffers = listingOffers[listingId];

        // First pass: count active offers
        uint256 activeCount = 0;
        for (uint256 i = 0; i < allOffers.length; i++) {
            if (offers[allOffers[i]].active) {
                activeCount++;
            }
        }

        // Second pass: populate active offers array
        uint256[] memory activeOffers = new uint256[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allOffers.length; i++) {
            if (offers[allOffers[i]].active) {
                activeOffers[index] = allOffers[i];
                index++;
            }
        }

        return activeOffers;
    }
}

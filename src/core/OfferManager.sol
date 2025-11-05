// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IOfferManager.sol";
import "../interfaces/IMarketplace.sol";
import "../interfaces/IEscrowManager.sol";
import "../libraries/AssetTypes.sol";
import "../libraries/PercentageMath.sol";
import "../libraries/Errors.sol";
import "../core/FeeDistributor.sol";
import "../access/RoleManager.sol";

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
 * - Offeran cancel active offers
 * - Automatic routing: NFT = instant transfer, others = escrow creation
 * - Locked funds when offer made (ensures buyer has funds)
 *
 */
contract OfferManager is IOfferManager, ReentrancyGuard, Pausable {
    using PercentageMath for uint256;
    using AssetTypes for AssetTypes.AssetType;

    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Offer counter for unique IDs
    uint256 public offerCounter;

    /// @notice Platform fee in basis points
    uint256 public platformFeeBps;

    /// @notice Mapping from offer ID to offer data
    mapping(uint256 => Offer) public offers;

    /// @notice Mapping listingId => array of offer IDs
    mapping(uint256 => uint256[]) public listingOffers;

    /// @notice Mapping offeror => array of offer IDs
    mapping(address => uint256[]) public offerorOffers;

    /// @notice Mapping seller => array of offer IDs
    mapping(address => uint256[]) public sellerOffers;

    /// @notice References to external contracts
    RoleManager public immutable roleManager;
    FeeDistributor public immutable feeDistributor;
    IMarketplace public immutable marketplace;
    IEscrowManager public immutable escrowManager;

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /**
     * @notice Initialize offer manager
     * @param _roleManager Address of role manager contract
     * @param _feeDistributor Address of fee distributor contract
     * @param _marketplace Address of marketplace core contract
     * @param _escrowManager Address of escrow manager contract
     * @param _platformFeeBps Initial platform fee in basis points
     */
    constructor(
        address _roleManager,
        address _feeDistributor,
        address _marketplace,
        address _escrowManager,
        uint256 _platformFeeBps
    ) {
        if (_roleManager == address(0)) revert Errors.InvalidRoleManager();
        if (_feeDistributor == address(0))
            revert Errors.InvalidFeeDistributor();
        if (_marketplace == address(0)) revert Errors.InvalidMarketplace();
        if (_escrowManager == address(0)) revert Errors.InvalidEscrowManager();

        PercentageMath.validateBps(_platformFeeBps, AssetTypes.MAX_FEE_BPS);

        roleManager = RoleManager(_roleManager);
        feeDistributor = FeeDistributor(payable(_feeDistributor));
        marketplace = IMarketplace(_marketplace);
        escrowManager = IEscrowManager(_escrowManager);
        platformFeeBps = _platformFeeBps;
    }

    // ============================================
    //               CORE FUNCTIONS
    // ============================================

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
    ) external payable whenNotPaused nonReentrant returns (uint256 offerId) {
        // Validate offer amount
        if (msg.value == 0) {
            revert InvalidOfferAmount(msg.value);
        }

        if (msg.value > AssetTypes.MAX_LISTING_PRICE) {
            revert InvalidOfferAmount(msg.value);
        }

        // Validate duration
        if (!AssetTypes.isValidOfferDuration(duration)) {
            revert InvalidOfferDuration(duration);
        }

        // Get listing details
        IMarketplace.Listing memory listing = marketplace.getListing(listingId);

        // Validate listing exists and is active
        if (listing.listingId == 0) {
            revert InvalidListingId(listingId);
        }

        if (listing.status != AssetTypes.ListingStatus.Active) {
            revert ListingNotActive(listingId);
        }

        // Cannot offer on own listing
        if (msg.sender == listing.seller) {
            revert CannotOfferOwnListing(msg.sender);
        }

        // Increment counter
        offerCounter++;
        offerId = offerCounter;

        // Calculate expiration
        uint256 expiresAt = block.timestamp + duration;

        // Create offer (storage optimized)
        offers[offerId] = Offer({
            offeror: msg.sender,
            amount: uint96(msg.value),
            seller: listing.seller,
            createdAt: uint32(block.timestamp),
            expiresAt: uint32(expiresAt),
            active: true,
            accepted: false,
            listingId: listingId,
            assetType: listing.assetType
        });

        // Track offers
        listingOffers[listingId].push(offerId);
        offerorOffers[msg.sender].push(offerId);
        sellerOffers[listing.seller].push(offerId);

        emit OfferMade(
            offerId,
            listingId,
            msg.sender,
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

        // Validate offer
        _validateOfferExists(offerId);

        if (!offer.active) {
            revert OfferNotActive(offerId);
        }

        if (offer.accepted) {
            revert OfferAlreadyAccepted(offerId);
        }

        // Only seller can accept
        if (msg.sender != offer.seller) {
            revert UnauthorizedSeller(msg.sender, offer.seller);
        }

        // Check not expired
        if (block.timestamp >= offer.expiresAt) {
            revert OfferExpiredError(offerId, offer.expiresAt);
        }

        // Get listing details
        IMarketplace.Listing memory listing = marketplace.getListing(
            offer.listingId
        );

        // Validate listing is still active
        if (listing.status != AssetTypes.ListingStatus.Active) {
            revert ListingAlreadySold(offer.listingId);
        }

        // Mark offer as accepted
        offer.active = false;
        offer.accepted = true;

        // Route based on asset type
        if (AssetTypes.isNFTType(offer.assetType)) {
            // NFT - instant transfer with payment distribution
            _handleNFTOfferAcceptance(offer, listing);
        } else {
            // Off-chain asset - create escrow
            _handleOffChainOfferAcceptance(offer, listing);
        }

        // Cancel all other offers for this listing
        _cancelOtherListingOffers(offer.listingId, offerId);

        emit OfferAccepted(
            offerId,
            offer.listingId,
            msg.sender,
            offer.offeror,
            offer.amount
        );
    }

    /**
     * @notice Reject an offer (seller only)
     * @param offerId Offer identifier
     * @param reason Reason for rejection
     * @dev Refunds offeror immediately
     */
    function rejectOffer(
        uint256 offerId,
        string calldata reason
    ) external nonReentrant {
        Offer storage offer = offers[offerId];

        // Validate
        _validateOfferExists(offerId);

        if (!offer.active) {
            revert OfferNotActive(offerId);
        }

        // Only seller can reject
        if (msg.sender != offer.seller) {
            revert UnauthorizedSeller(msg.sender, offer.seller);
        }

        // Mark as inactive
        offer.active = false;

        // Refund offeror
        uint256 refundAmount = offer.amount;
        _safeTransfer(offer.offeror, refundAmount);

        emit OfferRejected(
            offerId,
            offer.listingId,
            msg.sender,
            offer.offeror,
            reason
        );
        emit OfferRefunded(offerId, offer.offeror, refundAmount);
    }

    /**
     * @notice Cancel an offer (offeror only)
     * @param offerId Offer identifier
     * @dev Can only cancel active, non-accepted offers
     */
    function cancelOffer(uint256 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];

        // Validate
        _validateOfferExists(offerId);

        if (!offer.active) {
            revert OfferNotActive(offerId);
        }

        // Only offeror can cancel
        if (msg.sender != offer.offeror) {
            revert UnauthorizedOfferor(msg.sender, offer.offeror);
        }

        // Mark as inactive
        offer.active = false;

        // Refund offeror
        uint256 refundAmount = offer.amount;
        _safeTransfer(offer.offeror, refundAmount);

        emit OfferCancelled(offerId, offer.listingId, msg.sender, refundAmount);
        emit OfferRefunded(offerId, offer.offeror, refundAmount);
    }

    /**
     * @notice Claim refund for expired offer
     * @param offerId Offer identifier
     * @dev Anyone can call to clean up expired offers
     */
    function claimExpiredOffer(uint256 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];

        // Validate
        _validateOfferExists(offerId);

        if (!offer.active) {
            revert OfferNotActive(offerId);
        }

        // Check expired
        if (block.timestamp < offer.expiresAt) {
            revert OfferNotActive(offerId);
        }

        // Mark as inactive
        offer.active = false;

        // Refund offeror
        uint256 refundAmount = offer.amount;
        _safeTransfer(offer.offeror, refundAmount);

        emit OfferExpired(offerId, offer.listingId, offer.offeror);
        emit OfferRefunded(offerId, offer.offeror, refundAmount);
    }

    /**
     * @notice Batch cancel multiple offers
     * @param offerIds Array of offer identifiers
     * @dev Useful for offeror to cancel multiple offers at once
     */
    function batchCancelOffers(
        uint256[] calldata offerIds
    ) external nonReentrant {
        for (uint256 i = 0; i < offerIds.length; i++) {
            uint256 offerId = offerIds[i];
            Offer storage offer = offers[offerId];

            // Skip if invalid or already inactive
            if (
                offerId == 0 ||
                offerId > offerCounter ||
                !offer.active ||
                msg.sender != offer.offeror
            ) {
                continue;
            }

            // Mark as inactive
            offer.active = false;

            // Refund offeror
            uint256 refundAmount = offer.amount;
            _safeTransfer(offer.offeror, refundAmount);

            emit OfferCancelled(
                offerId,
                offer.listingId,
                msg.sender,
                refundAmount
            );
            emit OfferRefunded(offerId, offer.offeror, refundAmount);
        }
    }

    // ============================================
    //          INTERNAL FUNCTIONS
    // ============================================

    /**
     * @notice Handle NFT offer acceptance (instant transfer)
     */
    function _handleNFTOfferAcceptance(
        Offer memory offer,
        IMarketplace.Listing memory /* listing */
    ) internal {
        // For NFTs, we need to coordinate with NFT marketplace
        // This is a simplified version - in production, you'd want tighter integration

        uint256 amount = offer.amount;

        // Calculate platform fee
        uint256 platformFee = amount.percentOf(platformFeeBps);
        uint256 sellerNet = amount - platformFee;

        // Transfer platform fee
        _safeTransfer(address(feeDistributor), platformFee);

        // Transfer seller net
        _safeTransfer(offer.seller, sellerNet);

        // Note: NFT transfer would need to be coordinated externally
        // or this contract needs NFT approval from seller
    }

    /**
     * @notice Handle off-chain asset offer acceptance (create escrow)
     */
    function _handleOffChainOfferAcceptance(
        Offer memory offer,
        IMarketplace.Listing memory listing
    ) internal {
        // Get recommended escrow duration for asset type
        uint256 escrowDuration = AssetTypes.recommendedEscrowDuration(
            offer.assetType
        );

        // Create escrow with offer amount
        escrowManager.createEscrow{value: offer.amount}(
            offer.offeror, // buyer (the person who made the offer)
            offer.seller, // seller
            offer.assetType, // assetType
            escrowDuration, // duration
            listing.assetHash, // assetHash
            listing.metadataURI // metadataURI
        );

        // Escrow created successfully
        // Buyer (offeror) is now the escrow buyer
        // Seller must deliver and complete escrow process
    }

    /**
     * @notice Cancel all other offers for a listing when one is accepted
     */
    function _cancelOtherListingOffers(
        uint256 listingId,
        uint256 acceptedOfferId
    ) internal {
        uint256[] memory offerIds = listingOffers[listingId];

        for (uint256 i = 0; i < offerIds.length; i++) {
            uint256 offerId = offerIds[i];

            // Skip the accepted offer
            if (offerId == acceptedOfferId) continue;

            Offer storage offer = offers[offerId];

            // Skip if already inactive
            if (!offer.active) continue;

            // Mark as inactive
            offer.active = false;

            // Refund offeror
            _safeTransfer(offer.offeror, offer.amount);

            emit OfferCancelled(offerId, listingId, offer.seller, offer.amount);
            emit OfferRefunded(offerId, offer.offeror, offer.amount);
        }
    }

    /**
     * @notice Safe ETH transfer with proper error handling
     */
    function _safeTransfer(address recipient, uint256 amount) internal {
        if (amount == 0) return;
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) revert TransferFailed(recipient, amount);
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
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get offer details
     */
    function getOffer(uint256 offerId) external view returns (Offer memory) {
        _validateOfferExists(offerId);
        return offers[offerId];
    }

    /**
     * @notice Get all offers for a listing
     */
    function getListingOffers(
        uint256 listingId
    ) external view returns (uint256[] memory) {
        return listingOffers[listingId];
    }

    /**
     * @notice Get active offers for a listing
     */
    function getActiveListingOffers(
        uint256 listingId
    ) external view returns (uint256[] memory) {
        uint256[] memory allOffers = listingOffers[listingId];
        uint256 activeCount = 0;

        // Count active offers
        for (uint256 i = 0; i < allOffers.length; i++) {
            if (_isOfferActiveInternal(allOffers[i])) {
                activeCount++;
            }
        }

        // Build active offers array
        uint256[] memory activeOffers = new uint256[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < allOffers.length; i++) {
            if (_isOfferActiveInternal(allOffers[i])) {
                activeOffers[index] = allOffers[i];
                index++;
            }
        }

        return activeOffers;
    }

    /**
     * @notice Get offers made by an address
     */
    function getOfferorOffers(
        address offeror
    ) external view returns (uint256[] memory) {
        return offerorOffers[offeror];
    }

    /**
     * @notice Get offers received by a seller
     */
    function getSellerOffers(
        address seller
    ) external view returns (uint256[] memory) {
        return sellerOffers[seller];
    }

    /**
     * @notice Check if offer is active
     */
    function isOfferActive(uint256 offerId) external view returns (bool) {
        return _isOfferActiveInternal(offerId);
    }

    /**
     * @notice Internal check if offer is active
     */
    function _isOfferActiveInternal(
        uint256 offerId
    ) internal view returns (bool) {
        if (offerId == 0 || offerId > offerCounter) return false;

        Offer memory offer = offers[offerId];
        return offer.active && block.timestamp < offer.expiresAt;
    }

    /**
     * @notice Check if offer has expired
     */
    function hasOfferExpired(uint256 offerId) external view returns (bool) {
        if (offerId == 0 || offerId > offerCounter) return false;

        Offer memory offer = offers[offerId];
        return block.timestamp >= offer.expiresAt;
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    /**
     * @notice Update platform fee (FEE_MANAGER_ROLE only)
     */
    function updatePlatformFee(uint256 newFeeBps) external {
        if (!roleManager.hasRole(roleManager.FEE_MANAGER_ROLE(), msg.sender)) {
            revert Errors.NotFeeManager(msg.sender);
        }
        PercentageMath.validateBps(newFeeBps, AssetTypes.MAX_FEE_BPS);
        platformFeeBps = newFeeBps;
    }

    /**
     * @notice Pause contract (PAUSER_ROLE only)
     */
    function pause() external {
        if (!roleManager.hasRole(roleManager.PAUSER_ROLE(), msg.sender)) {
            revert Errors.NotPauser(msg.sender);
        }
        _pause();
    }

    /**
     * @notice Unpause contract (ADMIN_ROLE only)
     */
    function unpause() external {
        if (!roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender)) {
            revert Errors.NotAdmin(msg.sender);
        }
        _unpause();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IOfferManager} from "../interfaces/IOfferManager.sol";
import {IMarketplace} from "../interfaces/IMarketplace.sol";
import {IEscrowManager} from "../interfaces/IEscrowManager.sol";
import {AssetTypes} from "../libraries/AssetTypes.sol";
import {PercentageMath} from "../libraries/PercentageMath.sol";
import {Errors} from "../libraries/Errors.sol";
import {FeeDistributor} from "../core/FeeDistributor.sol";
import {RoleManager} from "../access/RoleManager.sol";

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
contract OfferManager is IOfferManager, ReentrancyGuard, Pausable {
    using PercentageMath for uint256;
    using AssetTypes for AssetTypes.AssetType;

    // ============================================
    //          STATE VARIABLES
    // ============================================

    /// @notice Offer counter for unique IDs
    uint256 public offerCounter;

    /// @notice Platform fee in basis points
    uint256 public platformFeeBps;

    /// @notice Maximum number of offers that can be cancelled in a single batch
    uint256 public constant MAX_BATCH_CANCEL_SIZE = 50;

    /// @notice Minimum offer amount to prevent spam (0.001 ETH)
    uint256 public constant MIN_OFFER_AMOUNT = 0.001 ether;

    /// @notice Mapping from offer ID to offer data
    mapping(uint256 => Offer) public offers;

    /// @notice Mapping listingId => array of offer IDs
    mapping(uint256 => uint256[]) public listingOffers;

    /// @notice Mapping buyer => array of offer IDs
    mapping(address => uint256[]) public buyerOffers;

    /// @notice Mapping seller => array of offer IDs
    mapping(address => uint256[]) public sellerOffers;

    /// @notice Pending refunds for rejected/cancelled offers (pull-over-push pattern)
    mapping(address => uint256) public pendingRefunds;

    /// @notice References to external contracts
    RoleManager public immutable roleManager;
    FeeDistributor public immutable feeDistributor;
    IMarketplace public immutable marketplace;
    IEscrowManager public immutable escrowManager;

    // ============================================
    //           CONSTRUCTOR
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
        if (_feeDistributor == address(0)) {
            revert Errors.InvalidFeeDistributor();
        }
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
    )
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 offerId)
    {
        // Validate offer amount (minimum to prevent spam, maximum for safety)
        if (msg.value < MIN_OFFER_AMOUNT || msg.value > AssetTypes.MAX_LISTING_PRICE) {
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

        // Track offers
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
        IMarketplace.Listing memory listing = marketplace.getListing(offer.listingId);

        // Validate listing is still active
        if (listing.status != AssetTypes.ListingStatus.Active) {
            revert ListingAlreadySold(offer.listingId);
        }

        // For NFT offers, verify seller has approved this contract
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

        // Note: Other offers for this listing are automatically invalidated
        // because the listing status changed to Sold. Users can claim refunds
        // via claimRefundForInvalidOffer()

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

        // Refund buyer
        uint256 refundAmount = offer.amount;
        _safeTransfer(offer.buyer, refundAmount);

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

        // Validate
        _validateOfferExists(offerId);

        if (!offer.active) {
            revert OfferNotActive(offerId);
        }

        // Only buyer can cancel
        if (msg.sender != offer.buyer) {
            revert UnauthorizedBuyer(msg.sender, offer.buyer);
        }

        // Mark as inactive
        offer.active = false;

        // Refund buyer
        uint256 refundAmount = offer.amount;
        _safeTransfer(offer.buyer, refundAmount);

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

        // Refund buyer
        uint256 refundAmount = offer.amount;
        _safeTransfer(offer.buyer, refundAmount);

        emit OfferExpired(offerId, offer.listingId, offer.buyer);
        emit OfferRefunded(offerId, offer.buyer, refundAmount);
    }

    /**
     * @notice Batch cancel multiple offers
     * @param offerIds Array of offer identifiers
     * @dev Useful for buyer to cancel multiple offers at once
     */
    function batchCancelOffers(uint256[] calldata offerIds) external nonReentrant {
        // Validate batch size to prevent gas limit issues
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

            // Mark as inactive
            offer.active = false;

            // Refund buyer
            uint256 refundAmount = offer.amount;
            _safeTransfer(offer.buyer, refundAmount);

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
    function _handleNFTOfferAcceptance(Offer memory offer, IMarketplace.Listing memory /* listing */ ) internal {
        // Get NFT details from marketplace
        IMarketplace.NFTDetails memory nft = marketplace.getNFTDetails(offer.listingId);

        // Transfer NFT from seller to buyer
        if (nft.standard == AssetTypes.TokenStandard.ERC721) {
            IERC721(nft.nftContract).safeTransferFrom(offer.seller, offer.buyer, nft.tokenId);
        } else {
            // ERC1155
            IERC1155(nft.nftContract).safeTransferFrom(offer.seller, offer.buyer, nft.tokenId, nft.quantity, "");
        }

        // Calculate and distribute payment
        uint256 amount = offer.amount;

        // Calculate platform fee
        uint256 platformFee = amount.percentOf(platformFeeBps);
        uint256 sellerNet = amount - platformFee;

        // Transfer platform fee
        _safeTransfer(address(feeDistributor), platformFee);

        // Transfer seller net
        _safeTransfer(offer.seller, sellerNet);

        // Mark listing as sold in marketplace
        marketplace.markListingAsSold(offer.listingId);
    }

    /**
     * @notice Handle off-chain asset offer acceptance (create escrow)
     */
    function _handleOffChainOfferAcceptance(Offer memory offer, IMarketplace.Listing memory listing) internal {
        // Get recommended escrow duration for asset type
        uint256 escrowDuration = AssetTypes.recommendedEscrowDuration(offer.assetType);

        // Create escrow with offer amount
        escrowManager.createEscrow{value: offer.amount}(
            offer.buyer, // buyer (the person who made the offer)
            offer.seller, // seller
            offer.assetType, // assetType
            escrowDuration, // duration
            listing.assetHash, // assetHash
            listing.metadataURI // metadataURI
        );

        // Escrow created successfully
        // Buyer is now the escrow buyer
        // Seller must deliver and complete escrow process
    }

    /**
     * @notice Claim refund for offer on sold/cancelled listing
     * @param offerId Offer identifier
     * @dev Allows buyers to claim refunds when their offer becomes invalid
     */
    function claimRefundForInvalidOffer(uint256 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];

        // Validate
        _validateOfferExists(offerId);

        if (!offer.active) {
            revert OfferNotActive(offerId);
        }

        // Only the buyer can claim
        if (msg.sender != offer.buyer) {
            revert UnauthorizedBuyer(msg.sender, offer.buyer);
        }

        // Get listing to check if it's still active
        IMarketplace.Listing memory listing = marketplace.getListing(offer.listingId);

        // Offer is invalid if listing is no longer active
        if (listing.status != AssetTypes.ListingStatus.Active) {
            // Mark as inactive
            offer.active = false;

            // Refund buyer
            uint256 refundAmount = offer.amount;
            _safeTransfer(offer.buyer, refundAmount);

            emit OfferCancelled(offerId, offer.listingId, msg.sender, refundAmount);
            emit OfferRefunded(offerId, offer.buyer, refundAmount);
        } else {
            revert OfferNotActive(offerId);
        }
    }

    /**
     * @notice Safe ETH transfer with proper error handling
     */
    function _safeTransfer(address recipient, uint256 amount) internal {
        if (amount == 0) return;
        (bool success,) = recipient.call{value: amount}("");
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
    //             VIEW FUNCTIONS
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
    function getListingOffers(uint256 listingId) external view returns (uint256[] memory) {
        return listingOffers[listingId];
    }

    /**
     * @notice Get offers made by an address
     */
    function getBuyerOffers(address buyer) external view returns (uint256[] memory) {
        return buyerOffers[buyer];
    }

    /**
     * @notice Get offers received by a seller
     */
    function getSellerOffers(address seller) external view returns (uint256[] memory) {
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
    function _isOfferActiveInternal(uint256 offerId) internal view returns (bool) {
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
     * @notice Get active offers for a listing
     * @param listingId Listing identifier
     * @return Array of active offer IDs
     */
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

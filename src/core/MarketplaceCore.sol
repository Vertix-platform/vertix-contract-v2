// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IMarketplace.sol";
import "../interfaces/IEscrowManager.sol";
import "../interfaces/INFTMarketplace.sol";
import "../libraries/AssetTypes.sol";
import "../access/RoleManager.sol";

/**
 * @title MarketplaceCore
 * @notice Main orchestrator routing listings to appropriate handlers
 * @dev Routes NFT sales to NFTMarketplace, off-chain assets to EscrowManager
 *
 * Architecture:
 * - NFTs (ERC721/1155) → NFTMarketplace (instant atomic swaps)
 * - Social Media, Websites, etc. → EscrowManager (time-locked escrow)
 * - Single entry point for all asset types
 * - Delegates to specialized contracts
 */
contract MarketplaceCore is IMarketplace, ReentrancyGuard, Pausable {
    using AssetTypes for AssetTypes.AssetType;

    // ============================================
    // STATE VARIABLES
    // ============================================

    uint256 public listingCounter;

    mapping(uint256 => Listing) public listings;
    mapping(address => uint256[]) public sellerListings;
    mapping(address => uint256[]) public buyerPurchases;

    RoleManager public immutable roleManager;
    IEscrowManager public immutable escrowManager;
    INFTMarketplace public immutable nftMarketplace;

    // Track which handler manages each listing
    mapping(uint256 => address) public listingHandler; // EscrowManager or NFTMarketplace
    mapping(uint256 => uint256) public listingToHandlerId; // ID in handler contract

    // ============================================
    // CONSTRUCTOR
    // ============================================

    constructor(
        address _roleManager,
        address _escrowManager,
        address _nftMarketplace
    ) {
        require(_roleManager != address(0), "Invalid role manager");
        require(_escrowManager != address(0), "Invalid escrow manager");
        require(_nftMarketplace != address(0), "Invalid NFT marketplace");

        roleManager = RoleManager(_roleManager);
        escrowManager = IEscrowManager(_escrowManager);
        nftMarketplace = INFTMarketplace(_nftMarketplace);
    }

    // ============================================
    // LISTING FUNCTIONS
    // ============================================

    /**
     * @notice Create a listing (routes to appropriate handler)
     * @param assetType Type of asset
     * @param price Listing price
     * @param assetHash Hash of asset details
     * @param metadataURI IPFS link to metadata
     * @return listingId Universal listing ID
     */
    function createListing(
        AssetTypes.AssetType assetType,
        uint256 price,
        bytes32 assetHash,
        string calldata metadataURI
    ) external payable whenNotPaused nonReentrant returns (uint256 listingId) {
        require(price > 0, "Invalid price");
        assetType.validateAssetType();

        listingCounter++;
        listingId = listingCounter;

        // Create universal listing record
        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            assetType: assetType,
            price: price,
            status: AssetTypes.ListingStatus.Active,
            createdAt: block.timestamp,
            assetHash: assetHash,
            metadataURI: metadataURI
        });

        sellerListings[msg.sender].push(listingId);

        // Route to appropriate handler
        if (assetType.isNFTType()) {
            // NFTs go to NFTMarketplace (handled separately, user calls NFTMarketplace directly)
            listingHandler[listingId] = address(nftMarketplace);
        } else {
            // Off-chain assets require escrow
            listingHandler[listingId] = address(escrowManager);
        }

        emit ListingCreated(listingId, msg.sender, assetType, price);

        return listingId;
    }

    /**
     * @notice Purchase an asset (routes to handler)
     * @param listingId Listing ID
     */
    function purchaseAsset(
        uint256 listingId
    ) external payable whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];

        require(
            listing.status == AssetTypes.ListingStatus.Active,
            "Listing not active"
        );
        require(msg.value == listing.price, "Incorrect payment");
        require(msg.sender != listing.seller, "Cannot buy own listing");

        // Update status
        listing.status = AssetTypes.ListingStatus.Sold;

        // Track purchase
        buyerPurchases[msg.sender].push(listingId);

        // Route to handler
        address handler = listingHandler[listingId];

        if (handler == address(escrowManager)) {
            // Create escrow for off-chain asset
            uint256 duration = listing.assetType.recommendedEscrowDuration();

            uint256 escrowId = escrowManager.createEscrow{value: msg.value}(
                listing.seller,
                listing.assetType,
                duration,
                listing.assetHash,
                listing.metadataURI
            );

            listingToHandlerId[listingId] = escrowId;
        } else {
            // NFT marketplace handles its own logic
            // This path shouldn't be hit as NFT sales go directly to NFTMarketplace
            revert("Use NFTMarketplace directly for NFTs");
        }

        emit ListingSold(listingId, msg.sender, listing.seller, listing.price);
    }

    /**
     * @notice Cancel a listing
     * @param listingId Listing ID
     */
    function cancelListing(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];

        require(listing.seller == msg.sender, "Not seller");
        require(
            listing.status == AssetTypes.ListingStatus.Active,
            "Not active"
        );

        listing.status = AssetTypes.ListingStatus.Cancelled;

        emit ListingCancelled(listingId, msg.sender);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    function getListing(
        uint256 listingId
    ) external view returns (Listing memory) {
        return listings[listingId];
    }

    function getSellerListings(
        address seller
    ) external view returns (uint256[] memory) {
        return sellerListings[seller];
    }

    function getBuyerPurchases(
        address buyer
    ) external view returns (uint256[] memory) {
        return buyerPurchases[buyer];
    }

    function getListingHandler(
        uint256 listingId
    ) external view returns (address) {
        return listingHandler[listingId];
    }

    function getHandlerListingId(
        uint256 listingId
    ) external view returns (uint256) {
        return listingToHandlerId[listingId];
    }

    // ============================================
    // STATISTICS
    // ============================================

    function getTotalListings() external view returns (uint256) {
        return listingCounter;
    }

    function getSellerListingCount(
        address seller
    ) external view returns (uint256) {
        return sellerListings[seller].length;
    }

    function getBuyerPurchaseCount(
        address buyer
    ) external view returns (uint256) {
        return buyerPurchases[buyer].length;
    }

    /**
     * @notice Get active listings count for a seller
     */
    function getSellerActiveListings(
        address seller
    ) external view returns (uint256 count) {
        uint256[] memory sellerListing = sellerListings[seller];
        for (uint256 i = 0; i < sellerListing.length; i++) {
            if (
                listings[sellerListing[i]].status ==
                AssetTypes.ListingStatus.Active
            ) {
                count++;
            }
        }
        return count;
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    function pause() external {
        require(
            roleManager.hasRole(roleManager.PAUSER_ROLE(), msg.sender),
            "Not pauser"
        );
        _pause();
    }

    function unpause() external {
        require(
            roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender),
            "Not admin"
        );
        _unpause();
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    /**
     * @notice Check if listing requires escrow
     */
    function requiresEscrow(uint256 listingId) external view returns (bool) {
        AssetTypes.AssetType assetType = listings[listingId].assetType;
        return assetType.requiresEscrow();
    }

    /**
     * @notice Get recommended escrow duration for listing
     */
    function getRecommendedDuration(
        uint256 listingId
    ) external view returns (uint256) {
        AssetTypes.AssetType assetType = listings[listingId].assetType;
        return assetType.recommendedEscrowDuration();
    }
}

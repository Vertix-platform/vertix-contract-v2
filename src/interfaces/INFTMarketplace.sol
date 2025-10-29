// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {AssetTypes} from "../libraries/AssetTypes.sol";

/**
 * @title INFTMarketplace
 * @notice Interface for NFT marketplace with atomic swaps
 * @dev Handles instant NFT trading without escrow (trustless via smart contract)
 */
interface INFTMarketplace {
    // ============================================
    //                STRUCTS
    // ============================================

    /**
     * @notice NFT listing data structure
     * @dev Optimized for storage packing (2 slots)
     */
    struct Listing {
        address seller;
        uint96 price;
        address nftContract;
        uint64 tokenId;
        uint16 quantity;
        AssetTypes.TokenStandard standard;
        bool active;
    }

    // ============================================
    //               EVENTS
    // ============================================

    /**
     * @notice Emitted when a new NFT listing is created
     * @param listingId Unique listing identifier
     * @param seller Seller address
     * @param nftContract NFT contract address
     * @param tokenId Token ID being listed
     * @param quantity Quantity (1 for ERC721, multiple for ERC1155)
     * @param price Listing price
     * @param standard Token standard (ERC721 or ERC1155)
     */
    event ListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 quantity,
        uint256 price,
        AssetTypes.TokenStandard standard
    );

    /**
     * @notice Emitted when an NFT is sold
     * @param listingId Listing identifier
     * @param buyer Buyer address
     * @param seller Seller address
     * @param nftContract NFT contract
     * @param tokenId Token ID
     * @param quantity Quantity sold
     * @param price Sale price
     * @param platformFee Fee collected by platform
     * @param royaltyFee Royalty paid to creator
     * @param sellerNet Net amount to seller
     */
    event NFTSold(
        uint256 indexed listingId,
        address indexed buyer,
        address indexed seller,
        address nftContract,
        uint256 tokenId,
        uint256 quantity,
        uint256 price,
        uint256 platformFee,
        uint256 royaltyFee,
        uint256 sellerNet
    );

    /**
     * @notice Emitted when a listing is cancelled
     * @param listingId Listing identifier
     * @param seller Seller who cancelled
     * @param nftContract NFT contract
     * @param tokenId Token ID
     */
    event ListingCancelled(
        uint256 indexed listingId,
        address indexed seller,
        address nftContract,
        uint256 tokenId
    );

    /**
     * @notice Emitted when listing price is updated
     * @param listingId Listing identifier
     * @param oldPrice Previous price
     * @param newPrice New price
     */
    event ListingPriceUpdated(
        uint256 indexed listingId,
        uint256 oldPrice,
        uint256 newPrice
    );

    // ============================================
    //                ERRORS
    // ============================================

    error InvalidListingId(uint256 listingId);
    error ListingNotActive(uint256 listingId);
    error UnauthorizedSeller(address caller, address seller);
    error InvalidPrice(uint256 price);
    error InvalidQuantity(uint256 quantity);
    error NFTNotOwned(
        address nftContract,
        uint256 tokenId,
        address expectedOwner
    );
    error NFTNotApproved(address nftContract, address marketplace);
    error InsufficientBalance(
        address nftContract,
        uint256 tokenId,
        uint256 required,
        uint256 actual
    );
    error IncorrectPayment(uint256 provided, uint256 required);
    error CannotBuyOwnNFT();
    error TransferFailed(address recipient, uint256 amount);
    error InvalidTokenStandard();

    // ============================================
    //              CORE FUNCTIONS
    // ============================================

    /**
     * @notice Create a new NFT listing
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to list
     * @param quantity Quantity to list (1 for ERC721, multiple for ERC1155)
     * @param price Listing price
     * @param standard Token standard (ERC721 or ERC1155)
     * @return listingId Unique identifier for the listing
     * @dev Seller must approve marketplace before listing
     */
    function createListing(
        address nftContract,
        uint256 tokenId,
        uint256 quantity,
        uint256 price,
        AssetTypes.TokenStandard standard
    ) external returns (uint256 listingId);

    /**
     * @notice Buy an NFT (atomic swap)
     * @param listingId Listing identifier
     * @dev Transfers NFT to buyer and distributes payment in single transaction
     *      Payment distribution: Platform fee + Royalty (if ERC2981) + Seller net
     */
    function buyNFT(uint256 listingId) external payable;

    /**
     * @notice Cancel an NFT listing
     * @param listingId Listing identifier
     * @dev Only seller can cancel
     */
    function cancelListing(uint256 listingId) external;

    /**
     * @notice Update listing price
     * @param listingId Listing identifier
     * @param newPrice New price
     * @dev Only seller can update, listing must be active
     */
    function updateListingPrice(uint256 listingId, uint256 newPrice) external;

    // ============================================
    //             VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get listing details
     * @param listingId Listing identifier
     * @return Listing struct
     */
    function getListing(
        uint256 listingId
    ) external view returns (Listing memory);

    /**
     * @notice Check if listing is active
     * @param listingId Listing identifier
     * @return True if active
     */
    function isListingActive(uint256 listingId) external view returns (bool);

    /**
     * @notice Get all active listings for a seller
     * @param seller Seller address
     * @return Array of listing IDs
     */
    function getSellerListings(
        address seller
    ) external view returns (uint256[] memory);

    /**
     * @notice Get listing ID for a specific NFT (if listed)
     * @param nftContract NFT contract address
     * @param tokenId Token ID
     * @return listingId (0 if not listed)
     */
    function getListingByNFT(
        address nftContract,
        uint256 tokenId
    ) external view returns (uint256);

    /**
     * @notice Calculate payment distribution for a listing
     * @param listingId Listing identifier
     * @return platformFee Platform fee amount
     * @return royaltyFee Royalty fee amount (if applicable)
     * @return sellerNet Net amount to seller
     * @return royaltyReceiver Royalty recipient (if applicable)
     */
    function calculatePaymentDistribution(
        uint256 listingId
    )
        external
        view
        returns (
            uint256 platformFee,
            uint256 royaltyFee,
            uint256 sellerNet,
            address royaltyReceiver
        );

    /**
     * @notice Get total number of listings created
     * @return Listing counter
     */
    function listingCounter() external view returns (uint256);

    /**
     * @notice Get platform fee in basis points
     * @return Fee BPS (250 = 2.5%)
     */
    function platformFeeBps() external view returns (uint256);
}

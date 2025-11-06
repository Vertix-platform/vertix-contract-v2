// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetTypes} from "../libraries/AssetTypes.sol";

/**
 * @title IMarketplace
 * @notice Interface for unified marketplace router
 * @dev Routes NFT and off-chain asset listings to appropriate handlers
 */
interface IMarketplace {
    // ============================================
    //                STRUCTS
    // ============================================

    /**
     * @notice Universal listing structure
     */
    struct Listing {
        uint256 listingId;
        address seller;
        AssetTypes.AssetType assetType;
        uint256 price;
        AssetTypes.ListingStatus status;
        uint256 createdAt;
        bytes32 assetHash;
        string metadataURI;
    }

    /**
     * @notice NFT-specific data
     * @dev Only populated for NFT listings
     */
    struct NFTDetails {
        address nftContract;
        uint64 tokenId;
        uint16 quantity;
        AssetTypes.TokenStandard standard;
    }

    // ============================================
    //                EVENTS
    // ============================================

    event ListingCreated(
        uint256 indexed listingId, address indexed seller, AssetTypes.AssetType assetType, uint256 price
    );

    event ListingSold(uint256 indexed listingId, address indexed buyer, address indexed seller, uint256 price);

    event ListingCancelled(uint256 indexed listingId, address indexed seller);

    // ============================================
    //          LISTING FUNCTIONS
    // ============================================

    /**
     * @notice Create NFT listing
     */
    function createNFTListing(
        address nftContract,
        uint256 tokenId,
        uint256 quantity,
        uint256 price,
        AssetTypes.TokenStandard standard
    ) external returns (uint256 listingId);

    /**
     * @notice Create off-chain asset listing
     */
    function createOffChainListing(
        AssetTypes.AssetType assetType,
        uint256 price,
        bytes32 assetHash,
        string calldata metadataURI
    ) external returns (uint256 listingId);

    /**
     * @notice Purchase any asset (auto-routes)
     */
    function purchaseAsset(uint256 listingId) external payable;

    /**
     * @notice Cancel listing
     */
    function cancelListing(uint256 listingId) external;

    /**
     * @notice Update listing price
     */
    function updatePrice(uint256 listingId, uint256 newPrice) external;

    // ============================================
    //             VIEW FUNCTIONS
    // ============================================

    function getListing(uint256 listingId) external view returns (Listing memory);

    function getSellerListings(address seller) external view returns (uint256[] memory);

    function isNFTListing(uint256 listingId) external view returns (bool);

    /**
     * @notice Get NFT details for a listing
     * @param listingId Listing identifier
     * @return NFT details
     */
    function getNFTDetails(uint256 listingId) external view returns (NFTDetails memory);

    /**
     * @notice Mark listing as sold (called by OfferManager/AuctionManager)
     * @param listingId Listing identifier
     */
    function markListingAsSold(uint256 listingId) external;
}

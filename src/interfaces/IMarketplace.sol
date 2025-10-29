// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {AssetTypes} from "../libraries/AssetTypes.sol";

/**
 * @title IMarketplace
 * @notice Interface for main marketplace orchestrator
 * @dev Routes listings to appropriate handlers (NFT or Escrow)
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

    // ============================================
    //                EVENTS
    // ============================================

    event ListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        AssetTypes.AssetType assetType,
        uint256 price
    );

    event ListingSold(
        uint256 indexed listingId,
        address indexed buyer,
        address indexed seller,
        uint256 price
    );

    event ListingCancelled(uint256 indexed listingId, address indexed seller);

    // ============================================
    //                   ERRORS
    // ============================================

    error InvalidListing();
    error UnauthorizedAccess();

    // ============================================
    //                FUNCTIONS
    // ============================================

    function createListing(
        AssetTypes.AssetType assetType,
        uint256 price,
        bytes32 assetHash,
        string calldata metadataURI
    ) external payable returns (uint256 listingId);

    function purchaseAsset(uint256 listingId) external payable;

    function cancelListing(uint256 listingId) external;

    function getListing(
        uint256 listingId
    ) external view returns (Listing memory);
}

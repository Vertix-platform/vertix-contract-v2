// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetTypes} from "../libraries/AssetTypes.sol";

interface IMarketplace {
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

    struct NFTDetails {
        address nftContract;
        uint64 tokenId;
        uint16 quantity;
        AssetTypes.TokenStandard standard;
    }

    event ListingCreated(
        uint256 indexed listingId, address indexed seller, AssetTypes.AssetType assetType, uint256 price
    );

    event ListingSold(uint256 indexed listingId, address indexed buyer, address indexed seller, uint256 price);

    event ListingCancelled(uint256 indexed listingId, address indexed seller);

    function createNFTListing(
        address nftContract,
        uint256 tokenId,
        uint256 quantity,
        uint256 price,
        AssetTypes.TokenStandard standard
    )
        external
        returns (uint256 listingId);

    function createOffChainListing(
        AssetTypes.AssetType assetType,
        uint256 price,
        bytes32 assetHash,
        string calldata metadataURI
    )
        external
        returns (uint256 listingId);

    function purchaseAsset(uint256 listingId) external payable;

    function cancelListing(uint256 listingId) external;

    function updatePrice(uint256 listingId, uint256 newPrice) external;

    function getListing(uint256 listingId) external view returns (Listing memory);

    function getSellerListings(address seller) external view returns (uint256[] memory);

    function isNFTListing(uint256 listingId) external view returns (bool);

    function getNFTDetails(uint256 listingId) external view returns (NFTDetails memory);

    function markListingAsSold(uint256 listingId) external;
}

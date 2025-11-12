// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IMarketplace} from "../../src/interfaces/IMarketplace.sol";
import {AssetTypes} from "../../src/libraries/AssetTypes.sol";

/**
 * @title MockMarketplace
 * @notice Mock marketplace for testing OfferManager
 */
contract MockMarketplace is IMarketplace {
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => NFTDetails) public nftDetails;
    uint256 public listingCounter;

    function createListing(
        address seller,
        AssetTypes.AssetType assetType,
        uint256 price,
        bytes32 assetHash,
        string memory metadataURI
    )
        external
        returns (uint256)
    {
        listingCounter++;
        listings[listingCounter] = Listing({
            listingId: listingCounter,
            seller: seller,
            assetType: assetType,
            price: price,
            status: AssetTypes.ListingStatus.Active,
            createdAt: block.timestamp,
            assetHash: assetHash,
            metadataURI: metadataURI
        });
        return listingCounter;
    }

    function createNFTListingMock(
        address seller,
        address nftContract,
        uint256 tokenId,
        uint256 quantity,
        uint256 price,
        AssetTypes.TokenStandard standard
    )
        external
        returns (uint256)
    {
        listingCounter++;
        listings[listingCounter] = Listing({
            listingId: listingCounter,
            seller: seller,
            assetType: standard == AssetTypes.TokenStandard.ERC721
                ? AssetTypes.AssetType.NFT721
                : AssetTypes.AssetType.NFT1155,
            price: price,
            status: AssetTypes.ListingStatus.Active,
            createdAt: block.timestamp,
            assetHash: bytes32(0),
            metadataURI: ""
        });

        nftDetails[listingCounter] = NFTDetails({
            nftContract: nftContract,
            tokenId: uint64(tokenId),
            quantity: uint16(quantity),
            standard: standard
        });

        return listingCounter;
    }

    function getListing(uint256 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }

    function getNFTDetails(uint256 listingId) external view returns (NFTDetails memory) {
        return nftDetails[listingId];
    }

    function markListingAsSold(uint256 listingId) external {
        listings[listingId].status = AssetTypes.ListingStatus.Sold;
    }

    function cancelListingMock(uint256 listingId) external {
        listings[listingId].status = AssetTypes.ListingStatus.Cancelled;
    }

    // Unimplemented interface functions
    function createNFTListing(
        address,
        uint256,
        uint256,
        uint256,
        AssetTypes.TokenStandard
    )
        external
        pure
        returns (uint256)
    {
        revert("Not implemented");
    }

    function createOffChainListing(
        AssetTypes.AssetType,
        uint256,
        bytes32,
        string calldata
    )
        external
        pure
        returns (uint256)
    {
        revert("Not implemented");
    }

    function purchaseAsset(uint256) external payable {
        revert("Not implemented");
    }

    function cancelListing(uint256) external pure {
        revert("Not implemented");
    }

    function updatePrice(uint256, uint256) external pure {
        revert("Not implemented");
    }

    function getSellerListings(address) external pure returns (uint256[] memory) {
        revert("Not implemented");
    }

    function isNFTListing(uint256) external pure returns (bool) {
        revert("Not implemented");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VertixSinglesNFT721} from "./VertixSinglesNFT721.sol";
import {VertixSinglesNFT1155} from "./VertixSinglesNFT1155.sol";
import {MarketplaceCore} from "../core/MarketplaceCore.sol";
import {AssetTypes} from "../libraries/AssetTypes.sol";
import {Errors} from "../libraries/Errors.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title SinglesNFTHelper
 * @notice  functions for minting single NFTs and listing them in one transaction
 */
contract SinglesNFTHelper is IERC721Receiver, IERC1155Receiver {
    VertixSinglesNFT721 public immutable singlesNFT721;
    VertixSinglesNFT1155 public immutable singlesNFT1155;
    MarketplaceCore public immutable marketplaceCore;

    event SingleNFTMintedAndListed(
        address indexed creator, uint256 indexed tokenId, uint256 indexed listingId, uint256 price, address nftContract
    );

    constructor(address _singlesNFT721, address _singlesNFT1155, address _marketplaceCore) {
        if (_singlesNFT721 == address(0)) revert Errors.ZeroAddress();
        if (_singlesNFT1155 == address(0)) revert Errors.ZeroAddress();
        if (_marketplaceCore == address(0)) revert Errors.ZeroAddress();

        singlesNFT721 = VertixSinglesNFT721(_singlesNFT721);
        singlesNFT1155 = VertixSinglesNFT1155(_singlesNFT1155);
        marketplaceCore = MarketplaceCore(_marketplaceCore);
    }

    /**
     * @notice Mint a single ERC-721 NFT and list it on the marketplace
     * @param tokenURI NFT metadata URI
     * @param price Listing price in wei
     * @return tokenId Minted token ID
     * @return listingId Marketplace listing ID
     * @dev User must have approved this helper contract via setApprovalForAll before calling
     */
    function mintAndList721(
        string memory tokenURI,
        uint256 price
    )
        external
        returns (uint256 tokenId, uint256 listingId)
    {
        // Mint NFT to helper temporarily
        tokenId = singlesNFT721.mintPublic(tokenURI);

        // Transfer NFT from helper to actual user
        singlesNFT721.transferFrom(address(this), msg.sender, tokenId);

        // As approved operator, approve NFTMarketplace on user's behalf (for purchase transfers)
        singlesNFT721.approve(address(marketplaceCore.nftMarketplace()), tokenId);

        // Create listing on behalf of user (helper is approved operator)
        listingId = marketplaceCore.createNFTListingFor(
            msg.sender, address(singlesNFT721), tokenId, 1, price, AssetTypes.TokenStandard.ERC721
        );

        emit SingleNFTMintedAndListed(msg.sender, tokenId, listingId, price, address(singlesNFT721));

        return (tokenId, listingId);
    }

    /**
     * @notice Mint ERC-1155 editions and list them on the marketplace
     * @param amount Number of editions to mint
     * @param maxSupply Maximum supply for this token (0 = unlimited)
     * @param tokenURI Token metadata URI
     * @param price Listing price per edition in wei
     * @param quantityToList Number of editions to list (must be <= amount)
     * @return tokenId Minted token ID
     * @return listingId Marketplace listing ID
     */
    function mintAndList1155(
        uint256 amount,
        uint256 maxSupply,
        string memory tokenURI,
        uint256 price,
        uint256 quantityToList
    )
        external
        returns (uint256 tokenId, uint256 listingId)
    {
        if (quantityToList == 0 || quantityToList > amount) {
            revert Errors.InvalidAmount();
        }

        // Verify user has approved NFTMarketplace (required for ERC-1155 purchase transfers)
        if (!singlesNFT1155.isApprovedForAll(msg.sender, address(marketplaceCore.nftMarketplace()))) {
            revert Errors.NotApproved();
        }

        // Mint editions to helper temporarily
        tokenId = singlesNFT1155.mintPublic(amount, maxSupply, tokenURI, "");

        // Transfer editions from helper to actual user
        singlesNFT1155.safeTransferFrom(address(this), msg.sender, tokenId, amount, "");

        // Create listing on behalf of user (helper is approved operator)
        listingId = marketplaceCore.createNFTListingFor(
            msg.sender, address(singlesNFT1155), tokenId, quantityToList, price, AssetTypes.TokenStandard.ERC1155
        );

        emit SingleNFTMintedAndListed(msg.sender, tokenId, listingId, price, address(singlesNFT1155));

        return (tokenId, listingId);
    }

    // ============================================
    //         VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Check if user has approved this helper for their singles NFTs
     * @param user User address
     * @return approved721 True if approved for ERC-721
     * @return approved1155 True if approved for ERC-1155
     */
    function isApproved(address user) external view returns (bool approved721, bool approved1155) {
        approved721 = singlesNFT721.isApprovedForAll(user, address(this));
        approved1155 = singlesNFT1155.isApprovedForAll(user, address(this));
        return (approved721, approved1155);
    }

    /**
     * @notice Get the shared collection addresses
     * @return nft721 Address of the shared ERC-721 collection
     * @return nft1155 Address of the shared ERC-1155 collection
     */
    function getSharedCollections() external view returns (address nft721, address nft1155) {
        return (address(singlesNFT721), address(singlesNFT1155));
    }

    /**
     * @notice Handle ERC721 token receipt
     * @dev Required to receive ERC721 tokens
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
     * @notice Handle ERC1155 single token receipt
     * @dev Required to receive ERC1155 tokens
     */
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    )
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /**
     * @notice Handle ERC1155 batch token receipt
     * @dev Required to receive ERC1155 tokens in batches
     */
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    )
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }
}

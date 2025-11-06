// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetTypes} from "../libraries/AssetTypes.sol";

/**
 * @title INFTMarketplace
 * @notice Interface for stateless NFT executor
 * @dev Called only by MarketplaceCore to execute NFT transfers + payment distribution
 */
interface INFTMarketplace {
    // ============================================
    //               EVENTS
    // ============================================

    event NFTTransferred(
        address indexed nftContract, uint256 indexed tokenId, address indexed from, address to, uint256 quantity
    );

    event PaymentDistributed(
        address indexed seller, uint256 sellerNet, uint256 platformFee, address royaltyReceiver, uint256 royaltyAmount
    );

    // ============================================
    //                ERRORS
    // ============================================

    error OnlyMarketplaceCore();
    error TransferFailed(address recipient, uint256 amount);
    error InvalidNFTContract();
    error InsufficientOwnership();
    error NotApproved();

    // ============================================
    //          EXECUTION FUNCTION
    // ============================================

    /**
     * @notice Execute NFT purchase (only callable by MarketplaceCore)
     * @param buyer Address receiving the NFT
     * @param seller Address selling the NFT
     * @param nftContract NFT contract address
     * @param tokenId Token ID
     * @param quantity Quantity (1 for ERC721, >1 for ERC1155)
     * @param standard Token standard (ERC721 or ERC1155)
     * @dev Payment sent as msg.value
     */
    function executePurchase(
        address buyer,
        address seller,
        address nftContract,
        uint256 tokenId,
        uint256 quantity,
        AssetTypes.TokenStandard standard
    )
        external
        payable;

    // ============================================
    //             VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Calculate payment distribution for an NFT sale
     * @param nftContract NFT contract address
     * @param tokenId Token ID
     * @param salePrice Total sale price
     * @return platformFee Platform fee amount
     * @return royaltyFee Royalty amount
     * @return sellerNet Net amount to seller
     * @return royaltyReceiver Address receiving royalty
     */
    function calculatePaymentDistribution(
        address nftContract,
        uint256 tokenId,
        uint256 salePrice
    )
        external
        view
        returns (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet, address royaltyReceiver);

    function marketplaceCore() external view returns (address);
    function platformFeeBps() external view returns (uint256);
}

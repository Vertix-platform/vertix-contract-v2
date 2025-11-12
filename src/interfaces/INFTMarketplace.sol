// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetTypes} from "../libraries/AssetTypes.sol";

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

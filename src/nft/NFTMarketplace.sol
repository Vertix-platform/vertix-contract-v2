// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AssetTypes} from "../libraries/AssetTypes.sol";
import {PercentageMath} from "../libraries/PercentageMath.sol";
import {Errors} from "../libraries/Errors.sol";
import {NFTOperations} from "../libraries/NFTOperations.sol";
import {PaymentUtils} from "../libraries/PaymentUtils.sol";
import {FeeDistributor} from "../core/FeeDistributor.sol";

/**
 * @title NFTMarketplace
 * @notice Stateless NFT executor - handles only transfers and payments
 * @dev Called by MarketplaceCore, doesn't store listings
 *
 * Design Philosophy:
 * - NO state storage (listings tracked in MarketplaceCore)
 * - Pure execution contract for NFT transfers + payment distribution
 */
contract NFTMarketplace is ReentrancyGuard {
    using PercentageMath for uint256;

    // ============================================
    //               ERRORS
    // ============================================

    error OnlyMarketplaceCore();
    error TransferFailed(address recipient, uint256 amount);
    error InvalidNFTContract();
    error InsufficientOwnership();
    error NotApproved();

    // ============================================
    //          STATE VARIABLES
    // ============================================

    /// @notice Address authorized to call this contract (MarketplaceCore)
    address public immutable marketplaceCore;

    /// @notice Fee distributor for platform fees
    FeeDistributor public immutable feeDistributor;

    /// @notice Platform fee in basis points (immutable for gas savings)
    uint256 public immutable platformFeeBps;

    // ============================================
    //                  EVENTS
    // ============================================

    event NFTTransferred(
        address indexed nftContract, uint256 indexed tokenId, address indexed from, address to, uint256 quantity
    );

    event PaymentDistributed(
        address indexed seller, uint256 sellerNet, uint256 platformFee, address royaltyReceiver, uint256 royaltyAmount
    );

    // ============================================
    //               MODIFIERS
    // ============================================

    modifier onlyMarketplaceCore() {
        if (msg.sender != marketplaceCore) revert OnlyMarketplaceCore();
        _;
    }

    /**
     * @notice Initialize NFT marketplace executor
     * @param _marketplaceCore Address of MarketplaceCore router
     * @param _feeDistributor Address of fee distributor
     * @param _platformFeeBps Platform fee in basis points
     */
    constructor(address _marketplaceCore, address _feeDistributor, uint256 _platformFeeBps) {
        if (_marketplaceCore == address(0)) {
            revert Errors.InvalidMarketplaceCore();
        }
        if (_feeDistributor == address(0)) {
            revert Errors.InvalidFeeDistributor();
        }
        PercentageMath.validateBps(_platformFeeBps, AssetTypes.MAX_FEE_BPS);

        marketplaceCore = _marketplaceCore;
        feeDistributor = FeeDistributor(payable(_feeDistributor));
        platformFeeBps = _platformFeeBps;
    }

    // ============================================
    //          EXTERNAL FUNCTION
    // ============================================

    /**
     * @notice Execute NFT purchase (called by MarketplaceCore only)
     * @param buyer Address receiving the NFT
     * @param seller Address selling the NFT
     * @param nftContract NFT contract address
     * @param tokenId Token ID
     * @param quantity Quantity (1 for ERC721, >1 for ERC1155)
     * @param standard Token standard (ERC721 or ERC1155)
     * @dev Payment must be sent as msg.value
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
        payable
        onlyMarketplaceCore
        nonReentrant
    {
        if (nftContract == address(0)) revert InvalidNFTContract();

        uint256 price = msg.value;

        // Validate ownership and approval
        NFTOperations.validateOwnership(nftContract, tokenId, seller, quantity, standard);
        NFTOperations.validateApprovalWithTokenId(nftContract, seller, address(this), tokenId, standard);

        // Calculate fees
        uint256 platformFee = price.percentOf(platformFeeBps);
        (address royaltyReceiver, uint256 royaltyAmount) = NFTOperations.getRoyaltyInfo(nftContract, tokenId, price);
        uint256 sellerNet = price - platformFee - royaltyAmount;

        // Transfer NFT (Checks-Effects-Interactions)
        NFTOperations.transferNFT(nftContract, seller, buyer, tokenId, quantity, standard);

        // Distribute payment
        PaymentUtils.safeTransferETH(seller, sellerNet);
        PaymentUtils.safeTransferETH(address(feeDistributor), platformFee);
        if (royaltyAmount > 0) {
            PaymentUtils.safeTransferETH(royaltyReceiver, royaltyAmount);
        }

        // Emit events
        emit NFTTransferred(nftContract, tokenId, seller, buyer, quantity);
        emit PaymentDistributed(seller, sellerNet, platformFee, royaltyReceiver, royaltyAmount);
    }

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
        returns (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet, address royaltyReceiver)
    {
        platformFee = salePrice.percentOf(platformFeeBps);
        (royaltyReceiver, royaltyFee) = NFTOperations.getRoyaltyInfo(nftContract, tokenId, salePrice);
        sellerNet = salePrice - platformFee - royaltyFee;

        return (platformFee, royaltyFee, sellerNet, royaltyReceiver);
    }
}

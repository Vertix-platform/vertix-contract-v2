// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AssetTypes} from "../libraries/AssetTypes.sol";
import {PercentageMath} from "../libraries/PercentageMath.sol";
import {Errors} from "../libraries/Errors.sol";
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
    // EVENTS
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

    // ============================================
    //              CONSTRUCTOR
    // ============================================

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
    //          CORE EXECUTION FUNCTION
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

        // Calculate fees
        uint256 platformFee = price.percentOf(platformFeeBps);
        (address royaltyReceiver, uint256 royaltyAmount) = _getRoyaltyInfo(nftContract, tokenId, price);
        uint256 sellerNet = price - platformFee - royaltyAmount;

        // Transfer NFT (Checks-Effects-Interactions)
        _transferNFT(nftContract, seller, buyer, tokenId, quantity, standard);

        // Distribute payment
        _sendPayment(seller, sellerNet);
        _sendPayment(address(feeDistributor), platformFee);
        if (royaltyAmount > 0) {
            _sendPayment(royaltyReceiver, royaltyAmount);
        }

        // Emit events
        emit NFTTransferred(nftContract, tokenId, seller, buyer, quantity);
        emit PaymentDistributed(seller, sellerNet, platformFee, royaltyReceiver, royaltyAmount);
    }

    // ============================================
    //        INTERNAL HELPER FUNCTIONS
    // ============================================

    /**
     * @notice Transfer NFT from seller to buyer
     * @dev Reverts if seller doesn't own NFT or hasn't approved marketplace
     */
    function _transferNFT(
        address nftContract,
        address from,
        address to,
        uint256 tokenId,
        uint256 quantity,
        AssetTypes.TokenStandard standard
    )
        internal
    {
        if (standard == AssetTypes.TokenStandard.ERC721) {
            // Verify ownership
            if (IERC721(nftContract).ownerOf(tokenId) != from) {
                revert InsufficientOwnership();
            }

            // Check approval (this contract needs approval to transfer)
            address approved = IERC721(nftContract).getApproved(tokenId);
            bool isApprovedForAll = IERC721(nftContract).isApprovedForAll(from, address(this));
            if (approved != address(this) && !isApprovedForAll) {
                revert NotApproved();
            }

            // Transfer
            IERC721(nftContract).safeTransferFrom(from, to, tokenId);
        } else {
            // ERC1155
            uint256 balance = IERC1155(nftContract).balanceOf(from, tokenId);
            if (balance < quantity) {
                revert InsufficientOwnership();
            }

            // Check approval (this contract needs approval to transfer)
            if (!IERC1155(nftContract).isApprovedForAll(from, address(this))) {
                revert NotApproved();
            }

            // Transfer
            IERC1155(nftContract).safeTransferFrom(from, to, tokenId, quantity, "");
        }
    }

    /**
     * @notice Get royalty info from ERC-2981 contract
     * @dev Returns (address(0), 0) if not supported or reverts
     */
    function _getRoyaltyInfo(
        address nftContract,
        uint256 tokenId,
        uint256 salePrice
    )
        internal
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        try IERC2981(nftContract).royaltyInfo(tokenId, salePrice) returns (address _receiver, uint256 _amount) {
            // Cap royalty at maximum allowed
            uint256 maxRoyalty = salePrice.percentOf(AssetTypes.MAX_ROYALTY_BPS);
            if (_amount > maxRoyalty) _amount = maxRoyalty;
            return (_receiver, _amount);
        } catch {
            return (address(0), 0);
        }
    }

    /**
     * @notice Send ETH payment safely
     * @dev Reverts if transfer fails
     */
    function _sendPayment(address recipient, uint256 amount) internal {
        if (amount == 0) return;

        (bool success,) = recipient.call{value: amount}("");
        if (!success) revert TransferFailed(recipient, amount);
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
        (royaltyReceiver, royaltyFee) = _getRoyaltyInfo(nftContract, tokenId, salePrice);
        sellerNet = salePrice - platformFee - royaltyFee;

        return (platformFee, royaltyFee, sellerNet, royaltyReceiver);
    }
}

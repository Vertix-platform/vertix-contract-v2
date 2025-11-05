// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {AssetTypes} from "../libraries/AssetTypes.sol";

/**
 * @title IAuctionManager
 * @notice Interface for auction management system
 * @dev Handles English auctions (ascending bid) for NFTs
 */
interface IAuctionManager {
    // ============================================
    //                STRUCTS
    // ============================================

    /**
     * @notice Auction data structure (storage optimized)
     * @dev Packed to minimize storage slots
     * @dev Supports both NFTs and off-chain assets
     */
    struct Auction {
        address seller; // 20 bytes
        uint96 reservePrice; // 12 bytes - Maximum ~79 billion ETH
        address nftContract; // 20 bytes - For NFTs only, address(0) for off-chain
        uint96 highestBid; // 12 bytes
        address highestBidder; // 20 bytes
        uint16 bidIncrementBps; // 2 bytes - Basis points (e.g., 500 = 5%)
        uint64 tokenId; // 8 bytes - For NFTs only
        uint32 startTime; // 4 bytes - Unix timestamp
        uint32 endTime; // 4 bytes - Unix timestamp
        AssetTypes.AssetType assetType; // 1 byte - Type of asset being auctioned
        AssetTypes.TokenStandard standard; // 1 byte - For NFTs only
        bool active; // 1 byte
        bool settled; // 1 byte
        uint16 quantity; // 2 bytes - For ERC1155
        bytes32 assetHash; // 32 bytes - Hash of asset details (for off-chain assets)
        string metadataURI; // IPFS link to asset metadata
    }

    // ============================================
    //                EVENTS
    // ============================================

    /**
     * @notice Emitted when a new auction is created
     */
    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed seller,
        AssetTypes.AssetType assetType,
        address nftContract,
        uint256 tokenId,
        uint256 reservePrice,
        uint256 startTime,
        uint256 endTime,
        uint256 bidIncrementBps
    );

    /**
     * @notice Emitted when a bid is placed
     */
    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 bidAmount,
        uint256 newEndTime
    );

    /**
     * @notice Emitted when previous bidder is refunded immediately
     */
    event BidRefunded(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount
    );

    /**
     * @notice Emitted when a bid refund is queued for manual withdrawal
     */
    event BidRefundQueued(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount
    );

    /**
     * @notice Emitted when a user withdraws their pending refunds
     */
    event Withdrawn(address indexed user, uint256 amount);

    /**
     * @notice Emitted when an auction ends successfully
     */
    event AuctionEnded(
        uint256 indexed auctionId,
        address indexed winner,
        address indexed seller,
        uint256 finalBid,
        uint256 platformFee,
        uint256 royaltyFee,
        uint256 sellerNet,
        address royaltyReceiver
    );

    /**
     * @notice Emitted when an auction is cancelled
     */
    event AuctionCancelled(
        uint256 indexed auctionId,
        address indexed seller,
        string reason
    );

    /**
     * @notice Emitted when reserve price is not met and auction fails
     */
    event AuctionFailedReserveNotMet(
        uint256 indexed auctionId,
        uint256 highestBid,
        uint256 reservePrice
    );

    // ============================================
    //                   ERRORS
    // ============================================

    error ERC721QuantityMustBe1();
    error QuantityMustBeGreaterThan0();
    error InsufficientBalance();
    error NFTContractShouldBeZeroForOffChain();
    error TokenIDShouldBeZeroForOffChain();
    error QuantityShouldBeZeroForOffChain();
    error AssetHashRequiredForOffChain();
    error MetadataURIRequiredForOffChain();
    error EmergencyWithdrawalTooEarly(
        uint256 auctionId,
        uint256 currentTime,
        uint256 availableAfter
    );
    error EmergencyWithdrawalNotAuthorized(
        address caller,
        address seller,
        address highestBidder
    );
    error EmergencyWithdrawalAlreadySettled(uint256 auctionId);
    error InvalidAuctionId(uint256 auctionId);
    error AuctionNotActive(uint256 auctionId);
    error AuctionAlreadySettled(uint256 auctionId);
    error UnauthorizedSeller(address caller, address seller);
    error InvalidNFTContract(address nftContract);
    error NFTNotApproved(address nftContract, uint256 tokenId);
    error NotNFTOwner(address caller, address owner);
    error BidTooLow(uint256 bidAmount, uint256 minimumBid);
    error CannotBidOwnAuction(address bidder);
    error AuctionHasNotEnded(uint256 auctionId, uint256 endTime);
    error CannotCancelWithBids(uint256 auctionId);
    error ReservePriceNotMet(uint256 highestBid, uint256 reservePrice);
    error TransferFailed(address recipient, uint256 amount);
    error InsufficientBidAmount();
    error NoPendingWithdrawal();
    error WithdrawalFailed(address recipient, uint256 amount);
    error BidBelowReserve(uint256 bidAmount, uint256 reservePrice);

    // ============================================
    //                FUNCTIONS
    // ============================================

    /**
     * @notice Create a new auction for any asset type
     * @param assetType Type of asset being auctioned
     * @param nftContract NFT contract address (only for NFTs, address(0) otherwise)
     * @param tokenId Token ID to auction (only for NFTs, 0 otherwise)
     * @param quantity Quantity (for ERC1155, must be 1 for ERC721, 0 for off-chain)
     * @param reservePrice Minimum winning bid (0 = no reserve)
     * @param duration Auction duration in seconds
     * @param bidIncrementBps Minimum bid increment in basis points
     * @param standard Token standard (ERC721 or ERC1155, only for NFTs)
     * @param assetHash Hash of asset details (for off-chain assets)
     * @param metadataURI IPFS link to asset metadata
     * @return auctionId Unique auction identifier
     */
    function createAuction(
        AssetTypes.AssetType assetType,
        address nftContract,
        uint256 tokenId,
        uint256 quantity,
        uint256 reservePrice,
        uint256 duration,
        uint256 bidIncrementBps,
        AssetTypes.TokenStandard standard,
        bytes32 assetHash,
        string calldata metadataURI
    ) external returns (uint256 auctionId);

    /**
     * @notice Place a bid on an auction
     * @param auctionId Auction identifier
     * @dev Bid amount is msg.value, must meet minimum bid requirement
     */
    function placeBid(uint256 auctionId) external payable;

    /**
     * @notice End auction and transfer NFT to winner
     * @param auctionId Auction identifier
     * @dev Can be called by anyone after auction ends
     */
    function endAuction(uint256 auctionId) external;

    /**
     * @notice Cancel auction (only if no bids placed)
     * @param auctionId Auction identifier
     * @dev Only seller can cancel, only before first bid
     */
    function cancelAuction(uint256 auctionId) external;

    /**
     * @notice Emergency withdrawal if auction ended but not settled
     * @param auctionId Auction identifier
     * @dev Allows seller to reclaim NFT or bidder to reclaim bid after extended period
     */
    function emergencyWithdraw(uint256 auctionId) external;

    // ============================================
    //             VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get auction details
     * @param auctionId Auction identifier
     * @return auction Auction struct
     */
    function getAuction(
        uint256 auctionId
    ) external view returns (Auction memory auction);

    /**
     * @notice Get minimum bid for an auction
     * @param auctionId Auction identifier
     * @return Minimum bid amount required
     */
    function getMinimumBid(uint256 auctionId) external view returns (uint256);

    /**
     * @notice Check if auction is active
     * @param auctionId Auction identifier
     * @return True if auction is accepting bids
     */
    function isAuctionActive(uint256 auctionId) external view returns (bool);

    /**
     * @notice Check if auction has ended
     * @param auctionId Auction identifier
     * @return True if auction time has expired
     */
    function hasAuctionEnded(uint256 auctionId) external view returns (bool);

    /**
     * @notice Get auctions created by a seller
     * @param seller Seller address
     * @return Array of auction IDs
     */
    function getSellerAuctions(
        address seller
    ) external view returns (uint256[] memory);

    /**
     * @notice Get auctions where address is highest bidder
     * @param bidder Bidder address
     * @return Array of auction IDs
     */
    function getBidderAuctions(
        address bidder
    ) external view returns (uint256[] memory);

    /**
     * @notice Calculate payment distribution for an auction
     * @param auctionId Auction identifier
     * @return platformFee Platform fee amount
     * @return royaltyFee Royalty fee amount
     * @return sellerNet Net amount to seller
     * @return royaltyReceiver Royalty recipient address
     */
    function calculatePaymentDistribution(
        uint256 auctionId
    )
        external
        view
        returns (
            uint256 platformFee,
            uint256 royaltyFee,
            uint256 sellerNet,
            address royaltyReceiver
        );
}

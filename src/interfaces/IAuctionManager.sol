// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetTypes} from "../libraries/AssetTypes.sol";

interface IAuctionManager {
    struct Auction {
        address seller; //
        uint96 reservePrice;
        // Maximum ~79 billion ETH
        address nftContract; // For NFTs only, address(0) for off-chain
        uint96 highestBid;
        address highestBidder; //
        uint16 bidIncrementBps;
        //Basis points (e.g., 500 = 5%)
        uint64 tokenId; // For NFTs only
        uint32 startTime; // Unix timestamp
        uint32 endTime; // Unix timestamp
        AssetTypes.AssetType assetType; // Type of asset being auctioned
        AssetTypes.TokenStandard standard; // For NFTs only
        bool active;
        bool settled;
        uint16 quantity; //For ERC1155
        bytes32 assetHash; // Hash of asset details (for off-chain assets)
        string metadataURI; // IPFS link to asset metadata
    }

    // ============================================
    //                EVENTS
    // ============================================

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

    event NFTEscrowed(
        uint256 indexed auctionId,
        address indexed nftContract,
        uint256 tokenId,
        uint256 quantity,
        AssetTypes.TokenStandard standard
    );

    event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 bidAmount, uint256 newEndTime);

    event BidRefunded(uint256 indexed auctionId, address indexed bidder, uint256 amount);

    event BidRefundQueued(uint256 indexed auctionId, address indexed bidder, uint256 amount);

    event Withdrawn(address indexed user, uint256 amount);

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

    event AuctionCancelled(uint256 indexed auctionId, address indexed seller, string reason);

    event AuctionFailedReserveNotMet(uint256 indexed auctionId, uint256 highestBid, uint256 reservePrice);

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
    error EmergencyWithdrawalTooEarly(uint256 auctionId, uint256 currentTime, uint256 availableAfter);
    error EmergencyWithdrawalNotAuthorized(address caller, address seller, address highestBidder);
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
    )
        external
        returns (uint256 auctionId);

    function placeBid(uint256 auctionId) external payable;

    function endAuction(uint256 auctionId) external;

    function cancelAuction(uint256 auctionId) external;

    function emergencyWithdraw(uint256 auctionId) external;

    // ============================================
    //             VIEW FUNCTIONS
    // ============================================

    function getAuction(uint256 auctionId) external view returns (Auction memory auction);

    function getMinimumBid(uint256 auctionId) external view returns (uint256);

    function isAuctionActive(uint256 auctionId) external view returns (bool);

    function hasAuctionEnded(uint256 auctionId) external view returns (bool);

    function getSellerAuctions(address seller) external view returns (uint256[] memory);

    function getBidderAuctions(address bidder) external view returns (uint256[] memory);

    function calculatePaymentDistribution(uint256 auctionId)
        external
        view
        returns (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet, address royaltyReceiver);
}

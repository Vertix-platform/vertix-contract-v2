// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./AssetTypes.sol";

/**
 * @title AuctionLogic
 * @notice Library containing helper functions for auction operations
 * @dev Provides validation, calculation, and state management logic for auctions
 */
library AuctionLogic {
    using AssetTypes for uint256;

    // ============================================
    //                ERRORS
    // ============================================

    error InvalidSeller();
    error InvalidAuctionDuration(uint256 duration);
    error InvalidBidIncrement(uint256 incrementBps);
    error InvalidReservePrice(uint256 reservePrice);
    error InvalidBidAmount(uint256 bidAmount, uint256 minimumBid);
    error AuctionNotStarted(uint256 auctionId, uint256 startTime);
    error AuctionEnded(uint256 auctionId, uint256 endTime);
    error AuctionNotEnded(uint256 auctionId, uint256 endTime);
    error BidderCannotBeSeller(address bidder);
    error ReservePriceNotMet(uint256 highestBid, uint256 reservePrice);

    // ============================================
    //          VALIDATION FUNCTIONS
    // ============================================

    /**
     * @notice Validate auction creation parameters
     * @param seller Seller address
     * @param reservePrice Minimum winning bid (0 = no reserve)
     * @param duration Auction duration in seconds
     * @param bidIncrementBps Minimum bid increment in basis points
     */
    function validateAuctionParams(address seller, uint256 reservePrice, uint256 duration, uint256 bidIncrementBps)
        internal
        pure
    {
        if (seller == address(0)) {
            revert InvalidSeller();
        }

        if (reservePrice > AssetTypes.MAX_LISTING_PRICE) {
            revert InvalidReservePrice(reservePrice);
        }

        if (!AssetTypes.isValidAuctionDuration(duration)) {
            revert InvalidAuctionDuration(duration);
        }

        if (!AssetTypes.isValidBidIncrement(bidIncrementBps)) {
            revert InvalidBidIncrement(bidIncrementBps);
        }
    }

    /**
     * @notice Validate bid parameters
     * @param bidder Bidder address
     * @param seller Seller address
     * @param bidAmount Bid amount
     * @param currentHighestBid Current highest bid
     * @param bidIncrementBps Minimum bid increment in basis points
     * @param startTime Auction start time
     * @param endTime Auction end time
     */
    function validateBid(
        address bidder,
        address seller,
        uint256 bidAmount,
        uint256 currentHighestBid,
        uint256 bidIncrementBps,
        uint256 startTime,
        uint256 endTime
    ) internal view {
        // Check bidder is not seller
        if (bidder == seller) {
            revert BidderCannotBeSeller(bidder);
        }

        // Check auction has started
        if (block.timestamp < startTime) {
            revert AuctionNotStarted(0, startTime);
        }

        // Check auction hasn't ended
        if (block.timestamp >= endTime) {
            revert AuctionEnded(0, endTime);
        }

        // Calculate minimum bid
        uint256 minimumBid = calculateMinimumBid(currentHighestBid, bidIncrementBps);

        // Check bid meets minimum
        if (bidAmount < minimumBid) {
            revert InvalidBidAmount(bidAmount, minimumBid);
        }
    }

    /**
     * @notice Validate auction can be ended
     * @param auctionId Auction identifier
     * @param endTime Auction end time
     */
    function validateCanEnd(uint256 auctionId, uint256 endTime) internal view {
        if (block.timestamp < endTime) {
            revert AuctionNotEnded(auctionId, endTime);
        }
    }

    /**
     * @notice Validate reserve price is met
     * @param highestBid Highest bid amount
     * @param reservePrice Reserve price
     */
    function validateReserveMet(uint256 highestBid, uint256 reservePrice) internal pure {
        if (reservePrice > 0 && highestBid < reservePrice) {
            revert ReservePriceNotMet(highestBid, reservePrice);
        }
    }

    // ============================================
    //        CALCULATION FUNCTIONS
    // ============================================

    /**
     * @notice Calculate minimum bid amount
     * @param currentBid Current highest bid
     * @param bidIncrementBps Bid increment in basis points
     * @return Minimum next bid
     */
    function calculateMinimumBid(uint256 currentBid, uint256 bidIncrementBps) internal pure returns (uint256) {
        return AssetTypes.calculateMinimumBid(currentBid, bidIncrementBps);
    }

    /**
     * @notice Calculate auction end time with potential extension
     * @param currentEndTime Current end time
     * @param bidTime Time of the bid
     * @return New end time (extended if within threshold)
     */
    function calculateExtendedEndTime(uint256 currentEndTime, uint256 bidTime) internal pure returns (uint256) {
        if (AssetTypes.shouldExtendAuction(currentEndTime, bidTime)) {
            return bidTime + AssetTypes.AUCTION_EXTENSION_TIME;
        }
        return currentEndTime;
    }

    /**
     * @notice Check if auction has bids
     * @param highestBid Current highest bid
     * @param highestBidder Current highest bidder
     * @return True if auction has received at least one bid
     */
    function hasBids(uint256 highestBid, address highestBidder) internal pure returns (bool) {
        return highestBid > 0 && highestBidder != address(0);
    }

    /**
     * @notice Check if auction is active
     * @param startTime Auction start time
     * @param endTime Auction end time
     * @return True if auction is currently accepting bids
     */
    function isActive(uint256 startTime, uint256 endTime) internal view returns (bool) {
        return block.timestamp >= startTime && block.timestamp < endTime;
    }

    /**
     * @notice Check if auction has ended
     * @param endTime Auction end time
     * @return True if auction has ended
     */
    function hasEnded(uint256 endTime) internal view returns (bool) {
        return block.timestamp >= endTime;
    }

    /**
     * @notice Check if auction can be cancelled
     * @param highestBid Current highest bid
     * @return True if auction can be cancelled (no bids placed)
     */
    function canCancel(uint256 highestBid) internal pure returns (bool) {
        return highestBid == 0;
    }

    /**
     * @notice Check if reserve price is met
     * @param highestBid Highest bid amount
     * @param reservePrice Reserve price (0 = no reserve)
     * @return True if reserve is met or no reserve set
     */
    function isReserveMet(uint256 highestBid, uint256 reservePrice) internal pure returns (bool) {
        if (reservePrice == 0) return true; // No reserve
        return highestBid >= reservePrice;
    }
}

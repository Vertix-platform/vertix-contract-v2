// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title AssetTypes
 * @notice Library containing type definitions and constants for Vertix marketplace
 * @dev Provides enums, structs, and helper functions for asset categorization
 */
library AssetTypes {
    // ============================================
    //                ENUMS
    // ============================================

    /**
     * @notice Asset categories supported by the marketplace
     */
    enum AssetType {
        NFT721, // ERC-721 NFT
        NFT1155, // ERC-1155 NFT
        SocialMediaYouTube, // YouTube channel/account
        SocialMediaTwitter, // Twitter/X account
        SocialMediaTwitch, // Twitch channel
        SocialMediaFacebook, // Facebook page/account
        SocialMediaInstagram, // Instagram account
        SocialMediaTikTok, // TikTok account
        Website, // Website/blog
        Domain, // Domain name (.com, .io, etc)
        MobileApp, // Mobile application
        GameAccount, // Gaming account
        Other // Other digital assets
    }

    /**
     * @notice Escrow state machine
     */
    enum EscrowState {
        None, // Default state (escrow doesn't exist)
        Active, // Funds locked, waiting for delivery
        Delivered, // Seller marked as delivered, buyer verifying
        Completed, // Funds released to seller
        Disputed, // Dispute opened, escrow frozen
        Cancelled, // Cancelled before delivery, refunded
        Refunded // Dispute resolved in favor of buyer
    }

    /**
     * @notice Listing status
     */
    enum ListingStatus {
        None, // Listing doesn't exist
        Active, // Listed and available for purchase
        Sold, // Successfully sold
        Cancelled, // Cancelled by seller
        Expired // Listing expired (if time-limited)
    }

    /**
     * @notice Token standards for NFTs
     */
    enum TokenStandard {
        ERC721, // Non-fungible token standard
        ERC1155 // Multi-token standard
    }

    /**
     * @notice Dispute status
     */
    enum DisputeStatus {
        None, // No dispute
        Open, // Dispute opened, evidence collection phase
        UnderReview, // Admin reviewing evidence
        Resolved, // Dispute resolved by admin
        Appealed // Decision appealed (future feature)
    }

    // ============================================
    //             CONSTANTS
    // ============================================

    /// @notice Maximum platform fee (10%)
    uint256 internal constant MAX_FEE_BPS = 1000;

    /// @notice Default platform fee (2.5%)
    uint256 internal constant DEFAULT_PLATFORM_FEE_BPS = 250;

    /// @notice Maximum royalty percentage (10%)
    uint256 internal constant MAX_ROYALTY_BPS = 1000;

    /// @notice Basis points denominator (100%)
    uint256 internal constant BPS_DENOMINATOR = 10000;

    /// @notice Minimum escrow duration (1 day)
    uint256 internal constant MIN_ESCROW_DURATION = 1 days;

    /// @notice Maximum escrow duration (1 year)
    uint256 internal constant MAX_ESCROW_DURATION = 365 days;

    // Escrow duration presets
    uint256 internal constant SHORT_ESCROW = 7 days;
    uint256 internal constant MEDIUM_ESCROW = 30 days;
    uint256 internal constant LONG_ESCROW = 90 days;
    uint256 internal constant EXTENDED_ESCROW = 180 days;

    /// @notice Cancellation compensation percentage (10% to seller if already delivered)
    uint256 internal constant CANCELLATION_PENALTY_BPS = 1000;

    /// @notice Minimum reputation score for good standing
    int256 internal constant MIN_GOOD_STANDING_SCORE = 50;

    /// @notice Maximum listing price (to prevent overflow issues)
    uint256 internal constant MAX_LISTING_PRICE = 1_000_000 ether;

    // ============================================
    //          HELPER FUNCTIONS
    // ============================================

    /**
     * @notice Check if asset type is an NFT
     * @param assetType The asset type to check
     * @return True if NFT (ERC721 or ERC1155)
     */
    function isNFTType(AssetType assetType) internal pure returns (bool) {
        return assetType == AssetType.NFT721 || assetType == AssetType.NFT1155;
    }

    /**
     * @notice Check if asset type is a social media account
     * @param assetType The asset type to check
     * @return True if social media platform
     */
    function isSocialMediaType(
        AssetType assetType
    ) internal pure returns (bool) {
        return
            assetType >= AssetType.SocialMediaYouTube &&
            assetType <= AssetType.SocialMediaTikTok;
    }

    /**
     * @notice Check if asset type requires escrow
     * @dev NFTs use atomic swaps, all other assets use escrow
     * @param assetType The asset type to check
     * @return True if escrow required
     */
    function requiresEscrow(AssetType assetType) internal pure returns (bool) {
        return !isNFTType(assetType);
    }

    /**
     * @notice Get recommended escrow duration for asset type
     * @param assetType The asset type
     * @return Recommended duration in seconds
     */
    function recommendedEscrowDuration(
        AssetType assetType
    ) internal pure returns (uint256) {
        if (isNFTType(assetType)) return 0; // No escrow for NFTs
        if (isSocialMediaType(assetType)) return MEDIUM_ESCROW; // 30 days for social media
        if (assetType == AssetType.Domain) return SHORT_ESCROW; // 7 days for domains
        if (assetType == AssetType.Website) return LONG_ESCROW; // 90 days for websites
        if (assetType == AssetType.MobileApp) return LONG_ESCROW; // 90 days for apps
        if (assetType == AssetType.GameAccount) return MEDIUM_ESCROW; // 30 days for game accounts
        return MEDIUM_ESCROW; // Default 30 days
    }

    /**
     * @notice Get asset type name as string
     * @param assetType The asset type
     * @return Human-readable name
     */
    function assetTypeName(
        AssetType assetType
    ) internal pure returns (string memory) {
        if (assetType == AssetType.NFT721) return "NFT (ERC-721)";
        if (assetType == AssetType.NFT1155) return "NFT (ERC-1155)";
        if (assetType == AssetType.SocialMediaYouTube) return "YouTube Channel";
        if (assetType == AssetType.SocialMediaTwitter) return "Twitter Account";
        if (assetType == AssetType.SocialMediaTwitch) return "Twitch Channel";
        if (assetType == AssetType.SocialMediaFacebook) return "Facebook Page";
        if (assetType == AssetType.SocialMediaInstagram)
            return "Instagram Account";
        if (assetType == AssetType.SocialMediaTikTok) return "TikTok Account";
        if (assetType == AssetType.Website) return "Website";
        if (assetType == AssetType.Domain) return "Domain Name";
        if (assetType == AssetType.MobileApp) return "Mobile App";
        if (assetType == AssetType.GameAccount) return "Game Account";
        return "Other";
    }

    /**
     * @notice Validate asset type is supported
     * @param assetType The asset type to validate
     */
    function validateAssetType(AssetType assetType) internal pure {
        require(
            uint8(assetType) <= uint8(AssetType.Other),
            "Invalid asset type"
        );
    }

    /**
     * @notice Validate escrow state transition
     * @param from Current state
     * @param to New state
     * @return True if transition is valid
     */
    function isValidStateTransition(
        EscrowState from,
        EscrowState to
    ) internal pure returns (bool) {
        // None -> Active (creation)
        if (from == EscrowState.None && to == EscrowState.Active) return true;

        // Active -> Delivered (seller marks delivered)
        if (from == EscrowState.Active && to == EscrowState.Delivered)
            return true;

        // Active -> Cancelled (buyer cancels before delivery)
        if (from == EscrowState.Active && to == EscrowState.Cancelled)
            return true;

        // Active -> Disputed (dispute opened before delivery)
        if (from == EscrowState.Active && to == EscrowState.Disputed)
            return true;

        // Delivered -> Completed (buyer confirms or deadline passes)
        if (from == EscrowState.Delivered && to == EscrowState.Completed)
            return true;

        // Delivered -> Disputed (buyer opens dispute)
        if (from == EscrowState.Delivered && to == EscrowState.Disputed)
            return true;

        // Disputed -> Completed (admin resolves in favor of seller)
        if (from == EscrowState.Disputed && to == EscrowState.Completed)
            return true;

        // Disputed -> Refunded (admin resolves in favor of buyer)
        if (from == EscrowState.Disputed && to == EscrowState.Refunded)
            return true;

        return false;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title Errors
 * @notice Centralized custom errors library for gas-efficient error handling
 * @dev Reusable errors across all Vertix marketplace contracts
 */
library Errors {
    // ============================================
    // CONSTRUCTOR & INITIALIZATION ERRORS
    // ============================================

    /// @notice Zero address provided where valid address required
    error ZeroAddress();

    /// @notice Invalid role manager address
    error InvalidRoleManager();

    /// @notice Invalid fee distributor address
    error InvalidFeeDistributor();

    /// @notice Invalid escrow manager address
    error InvalidEscrowManager();

    /// @notice Invalid NFT marketplace address
    error InvalidNFTMarketplace();

    /// @notice Invalid marketplace address
    error InvalidMarketplace();

    /// @notice Invalid marketplace core address
    error InvalidMarketplaceCore();

    /// @notice Invalid creator address
    error InvalidCreator();

    /// @notice Invalid verifier address
    error InvalidVerifier();

    /// @notice Invalid user address
    error InvalidUser();

    /// @notice Invalid royalty receiver address
    error InvalidRoyaltyReceiver();

    // ============================================
    //         AUTHORIZATION ERRORS
    // ============================================

    /// @notice Caller is not an admin
    /// @param caller Address that attempted the action
    error NotAdmin(address caller);

    /// @notice Caller is not a fee manager
    /// @param caller Address that attempted the action
    error NotFeeManager(address caller);

    /// @notice Caller is not a pauser
    /// @param caller Address that attempted the action
    error NotPauser(address caller);

    /// @notice Caller is not authorized for this action
    /// @param caller Address that attempted the action
    error NotAuthorized(address caller);

    // ============================================
    //            VALIDATION ERRORS
    // ============================================

    /// @notice Empty string provided where non-empty required
    /// @param fieldName Name of the field that was empty
    error EmptyString(string fieldName);

    /// @notice String exceeds maximum length
    /// @param length Actual length
    /// @param max Maximum allowed length
    error StringTooLong(uint256 length, uint256 max);

    /// @notice Invalid hash value
    error InvalidHash();

    /// @notice Asset hash is required but not provided
    error AssetHashRequired();

    /// @notice Metadata URI is required but not provided
    error MetadataURIRequired();

    /// @notice Use createNFTListing for NFT asset types
    error UseCreateNFTListing();

    // ============================================
    //          AMOUNT & VALUE ERRORS
    // ============================================

    /// @notice Insufficient payment provided
    /// @param provided Amount provided
    /// @param required Amount required
    error InsufficientPayment(uint256 provided, uint256 required);

    /// @notice Insufficient fees to withdraw
    error InsufficientFees();

    /// @notice No fees available to withdraw
    error NoFeesToWithdraw();

    /// @notice Royalty percentage exceeds maximum allowed
    /// @param royalty Royalty amount
    /// @param max Maximum allowed
    error RoyaltyTooHigh(uint256 royalty, uint256 max);

    /// @notice Maximum supply reached for token
    /// @param current Current supply
    /// @param max Maximum supply
    error MaxSupplyReached(uint256 current, uint256 max);

    // ============================================
    //           TRANSFER ERRORS
    // ============================================

    /// @notice Generic transfer failed
    /// @param recipient Intended recipient
    /// @param amount Amount that failed to transfer
    error TransferFailed(address recipient, uint256 amount);

    /// @notice Transfer to seller failed
    error SellerTransferFailed();

    /// @notice Fee transfer failed
    error FeeTransferFailed();

    /// @notice Transfer to winner failed
    error WinnerTransferFailed();

    /// @notice Seller compensation transfer failed
    error SellerCompensationFailed();

    /// @notice Buyer refund transfer failed
    error BuyerRefundFailed();

    /// @notice Transfer to other party failed
    error OtherPartyTransferFailed();

    // ============================================
    //            STATE ERRORS
    // ============================================

    /// @notice Token does not exist
    /// @param tokenId Token ID that doesn't exist
    error TokenDoesNotExist(uint256 tokenId);

    /// @notice User is already banned
    /// @param user User address
    error AlreadyBanned(address user);

    /// @notice User is not banned
    /// @param user User address
    error NotBanned(address user);

    /// @notice Cannot cancel escrow in current state
    error CannotCancelEscrow();

    /// @notice Asset type does not require escrow
    error AssetTypeDoesNotRequireEscrow();

    // ============================================
    //           ASSET TYPE ERRORS
    // ============================================

    /// @notice Invalid asset type provided
    /// @param assetType The invalid asset type value
    error InvalidAssetType(uint8 assetType);
}

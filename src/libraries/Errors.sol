// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Errors
 * @notice Centralized custom errors library for gas-efficient error handling
 * @dev Reusable errors across all Vertix marketplace contracts
 */
library Errors {
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

    /// @notice Caller is not an admin
    error NotAdmin(address caller);

    /// @notice Caller is not a fee manager
    error NotFeeManager(address caller);

    /// @notice Caller is not a pauser
    error NotPauser(address caller);

    /// @notice Caller is not a verifier
    error NotVerifier(address caller);

    /// @notice Caller is not authorized for this action
    error NotAuthorized(address caller);

    /// @notice Address is already authorized
    error AlreadyAuthorized(address addr);

    /// @notice Unauthorized escrow creation - caller cannot create escrow for this buyer
    error UnauthorizedEscrowCreation(address caller, address buyer);

    error BuyerCannotBeSeller();

    /// @notice Empty string provided where non-empty required
    error EmptyString(string fieldName);

    /// @notice String exceeds maximum length
    error StringTooLong(uint256 length, uint256 max);

    /// @notice Invalid hash value
    error InvalidHash();

    /// @notice Asset hash is required but not provided
    error AssetHashRequired();

    /// @notice Metadata URI is required but not provided
    error MetadataURIRequired();

    error UseCreateNFTListing();

    error InsufficientPayment(uint256 provided, uint256 required);

    /// @notice Insufficient fees to withdraw
    error InsufficientFees();

    /// @notice No fees available to withdraw
    error NoFeesToWithdraw();

    /// @notice Royalty percentage exceeds maximum allowed
    error RoyaltyTooHigh(uint256 royalty, uint256 max);

    /// @notice Maximum supply reached for token
    error MaxSupplyReached(uint256 current, uint256 max);

    /// @notice Generic transfer failed
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

    /// @notice Token does not exist
    error TokenDoesNotExist(uint256 tokenId);

    /// @notice User is already banned
    error AlreadyBanned(address user);

    /// @notice User is not banned
    error NotBanned(address user);

    /// @notice Cannot cancel escrow in current state
    error CannotCancelEscrow();

    /// @notice Asset type does not require escrow
    error AssetTypeDoesNotRequireEscrow();

    /// @notice Invalid asset type provided
    error InvalidAssetType(uint8 assetType);
}

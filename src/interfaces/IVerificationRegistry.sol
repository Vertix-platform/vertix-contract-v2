// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetTypes} from "../libraries/AssetTypes.sol";

/**
 * @title IVerificationRegistry
 * @notice Interface for storing off-chain asset verification proofs
 * @dev Hybrid system: Hash stored on-chain, full data on IPFS
 */
interface IVerificationRegistry {
    // ============================================
    //               STRUCTS
    // ============================================

    /**
     * @notice Verification proof data
     * @dev Optimized for storage (2 slots)
     */
    struct Verification {
        bytes32 proofHash; // SHA256 of verification data
        address verifier; // Who verified
        uint32 verifiedAt; // Timestamp
        uint32 expiresAt; // Expiration
        AssetTypes.AssetType assetType; // Type of asset
        bool isActive; // Can be revoked
        uint16 verificationCount; // Renewal counter
    }

    // ============================================
    //                 EVENTS
    // ============================================

    /**
     * @notice Emitted when a new verification is added
     * @param verificationId Unique verification ID
     * @param owner Asset owner
     * @param verifier Who performed verification
     * @param assetType Type of asset verified
     * @param proofHash Hash of verification data
     * @param expiresAt Expiration timestamp
     * @param metadataURI IPFS link to full verification details
     */
    event VerificationAdded(
        uint256 indexed verificationId,
        address indexed owner,
        address indexed verifier,
        AssetTypes.AssetType assetType,
        bytes32 proofHash,
        uint256 expiresAt,
        string metadataURI
    );

    /**
     * @notice Emitted when verification is revoked
     * @param verificationId Verification ID
     * @param owner Asset owner
     * @param revokedBy Who revoked (admin or verifier)
     * @param reason Revocation reason
     */
    event VerificationRevoked(uint256 indexed verificationId, address indexed owner, address revokedBy, string reason);

    /**
     * @notice Emitted when verification is renewed
     * @param verificationId Verification ID
     * @param owner Asset owner
     * @param newExpiresAt New expiration timestamp
     * @param renewalCount How many times renewed
     */
    event VerificationRenewed(
        uint256 indexed verificationId, address indexed owner, uint256 newExpiresAt, uint256 renewalCount
    );

    /**
     * @notice Emitted when verifier is added to whitelist
     * @param verifier Verifier address
     * @param addedBy Admin who added
     */
    event VerifierAdded(address indexed verifier, address addedBy);

    /**
     * @notice Emitted when verifier is removed from whitelist
     * @param verifier Verifier address
     * @param removedBy Admin who removed
     */
    event VerifierRemoved(address indexed verifier, address removedBy);

    // ============================================
    //                ERRORS
    // ============================================

    error UnauthorizedVerifier(address caller);
    error InvalidOwner(address owner);
    error InvalidProofHash();
    error InvalidExpiration(uint256 expiresAt);
    error VerificationNotFound(uint256 verificationId);
    error VerificationExpired(uint256 verificationId, uint256 expiredAt);
    error VerificationNotActive(uint256 verificationId);
    error AlreadyVerified(address owner, AssetTypes.AssetType assetType);
    error VerifierAlreadyWhitelisted(address verifier);
    error VerifierNotWhitelisted(address verifier);

    // ============================================
    //           CORE FUNCTIONS
    // ============================================

    /**
     * @notice Add a new verification proof
     * @param owner Address of asset owner
     * @param assetType Type of asset being verified
     * @param proofHash SHA256 hash of verification data
     * @param expiresAt Expiration timestamp
     * @param metadataURI IPFS link to full verification details
     * @return verificationId Unique identifier
     * @dev Only whitelisted verifiers can call
     */
    function addVerification(
        address owner,
        AssetTypes.AssetType assetType,
        bytes32 proofHash,
        uint256 expiresAt,
        string calldata metadataURI
    ) external returns (uint256 verificationId);

    /**
     * @notice Revoke a verification
     * @param verificationId Verification ID to revoke
     * @param reason Reason for revocation
     * @dev Can be called by verifier or admin
     */
    function revokeVerification(uint256 verificationId, string calldata reason) external;

    /**
     * @notice Renew an existing verification
     * @param verificationId Verification ID to renew
     * @param newExpiresAt New expiration timestamp
     * @param newProofHash Updated proof hash (if data changed)
     * @param newMetadataURI Updated IPFS URI (if data changed)
     * @dev Only original verifier can renew
     */
    function renewVerification(
        uint256 verificationId,
        uint256 newExpiresAt,
        bytes32 newProofHash,
        string calldata newMetadataURI
    ) external;

    /**
     * @notice Add verifier to whitelist (admin only)
     * @param verifier Address to whitelist
     */
    function addVerifier(address verifier) external;

    /**
     * @notice Remove verifier from whitelist (admin only)
     * @param verifier Address to remove
     */
    function removeVerifier(address verifier) external;

    // ============================================
    //        VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Check if address is verified for asset type
     * @param owner Asset owner
     * @param assetType Type of asset
     * @return True if has active, non-expired verification
     */
    function isVerified(address owner, AssetTypes.AssetType assetType) external view returns (bool);

    /**
     * @notice Get verification details
     * @param verificationId Verification ID
     * @return Verification struct
     */
    function getVerification(uint256 verificationId) external view returns (Verification memory);

    /**
     * @notice Get all verifications for an owner
     * @param owner Asset owner
     * @return Array of verification IDs
     */
    function getOwnerVerifications(address owner) external view returns (uint256[] memory);

    /**
     * @notice Get verification ID for owner + asset type
     * @param owner Asset owner
     * @param assetType Asset type
     * @return verificationId (0 if not found)
     */
    function getVerificationByOwnerAndType(address owner, AssetTypes.AssetType assetType)
        external
        view
        returns (uint256);

    /**
     * @notice Check if verification is expired
     * @param verificationId Verification ID
     * @return True if expired
     */
    function isExpired(uint256 verificationId) external view returns (bool);

    /**
     * @notice Get total verification count
     * @return Counter
     */
    function verificationCounter() external view returns (uint256);
}

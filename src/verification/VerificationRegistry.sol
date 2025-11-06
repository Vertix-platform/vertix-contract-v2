// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IVerificationRegistry.sol";
import "../libraries/AssetTypes.sol";
import "../libraries/Errors.sol";
import "../access/RoleManager.sol";

/**
 * @title VerificationRegistry
 * @notice Stores off-chain asset verification proofs on-chain
 * @dev Hybrid system: Hash stored on-chain (privacy), full data on IPFS
 *
 * Verification Flow:
 * 1. User initiates verification via frontend
 * 2. Backend service verifies asset (API calls, proof of ownership)
 * 3. Backend uploads full verification data to IPFS
 * 4. Backend calls addVerification() with proof hash + IPFS URI
 * 5. On-chain proof stored, user's asset is "verified"
 * 6. Verified assets get reputation boost
 * 7. Verifications expire and need renewal
 *
 * Supported Verifications:
 * - YouTube channels (subscriber count, ownership proof)
 * - Twitter accounts (follower count, tweet verification)
 * - Twitch channels (follower count, stream verification)
 * - Facebook pages (like count, ownership)
 * - Instagram accounts (follower count, post verification)
 * - TikTok accounts (follower count, video verification)
 * - Websites (domain ownership via DNS, traffic)
 * - Domains (WHOIS verification)
 */
contract VerificationRegistry is IVerificationRegistry, ReentrancyGuard {
    using AssetTypes for AssetTypes.AssetType;

    // ============================================
    //          STATE VARIABLES
    // ============================================

    /// @notice Verification counter
    uint256 public verificationCounter;

    /// @notice Mapping from verification ID to verification data
    mapping(uint256 => Verification) public verifications;

    /// @notice Mapping from verification ID to metadata URI
    mapping(uint256 => string) public verificationMetadata;

    /// @notice Owner address => array of verification IDs
    mapping(address => uint256[]) public ownerVerifications;

    /// @notice Owner => AssetType => verification ID (for quick lookup)
    mapping(address => mapping(AssetTypes.AssetType => uint256)) public ownerAssetVerification;

    /// @notice Verification ID => owner address (reverse mapping for efficient lookups)
    mapping(uint256 => address) public verificationOwner;

    /// @notice Whitelisted verifier addresses
    mapping(address => bool) public whitelistedVerifiers;

    /// @notice Reference to role manager
    RoleManager public immutable roleManager;

    // ============================================
    //              CONSTRUCTOR
    // ============================================

    /**
     * @notice Initialize verification registry
     * @param _roleManager Address of role manager contract
     */
    constructor(address _roleManager) {
        if (_roleManager == address(0)) revert Errors.InvalidRoleManager();
        roleManager = RoleManager(_roleManager);
    }

    // ============================================
    //            ETERNAL FUNCTIONS
    // ============================================

    /**
     * @notice Add a new verification proof
     * @param owner Address of asset owner
     * @param assetType Type of asset being verified
     * @param proofHash SHA256 hash of verification data
     * @param expiresAt Expiration timestamp
     * @param metadataURI IPFS link to full verification details
     * @return verificationId Unique identifier
     */
    function addVerification(
        address owner,
        AssetTypes.AssetType assetType,
        bytes32 proofHash,
        uint256 expiresAt,
        string calldata metadataURI
    )
        external
        nonReentrant
        returns (uint256 verificationId)
    {
        // Only whitelisted verifiers can add proofs
        if (!whitelistedVerifiers[msg.sender]) {
            revert UnauthorizedVerifier(msg.sender);
        }

        // Validate inputs
        if (owner == address(0)) revert InvalidOwner(owner);
        if (proofHash == bytes32(0)) revert InvalidProofHash();
        if (expiresAt <= block.timestamp) revert InvalidExpiration(expiresAt);
        assetType.validateAssetType();

        // Check if already verified for this asset type
        uint256 existingId = ownerAssetVerification[owner][assetType];
        if (existingId != 0 && verifications[existingId].isActive) {
            revert AlreadyVerified(owner, assetType);
        }

        // Increment counter
        verificationCounter++;
        verificationId = verificationCounter;

        // Create verification
        verifications[verificationId] = Verification({
            proofHash: proofHash,
            verifier: msg.sender,
            verifiedAt: uint32(block.timestamp),
            expiresAt: uint32(expiresAt),
            assetType: assetType,
            isActive: true,
            verificationCount: 1
        });

        // Store metadata
        verificationMetadata[verificationId] = metadataURI;

        // Track ownership
        ownerVerifications[owner].push(verificationId);
        ownerAssetVerification[owner][assetType] = verificationId;
        verificationOwner[verificationId] = owner;

        emit VerificationAdded(verificationId, owner, msg.sender, assetType, proofHash, expiresAt, metadataURI);

        return verificationId;
    }

    /**
     * @notice Revoke a verification
     * @param verificationId Verification ID to revoke
     * @param reason Reason for revocation
     */
    function revokeVerification(uint256 verificationId, string calldata reason) external nonReentrant {
        _validateVerificationExists(verificationId);

        Verification storage verification = verifications[verificationId];

        // Only verifier or admin can revoke
        bool isVerifier = msg.sender == verification.verifier;
        bool isAdmin = roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender);

        if (!isVerifier && !isAdmin) revert Errors.NotAuthorized(msg.sender);

        // Check if active
        if (!verification.isActive) {
            revert VerificationNotActive(verificationId);
        }

        // Revoke
        verification.isActive = false;

        // Find owner and clear mappings
        address owner = _findOwner(verificationId);
        if (owner != address(0)) {
            delete ownerAssetVerification[owner][verification.assetType];
            delete verificationOwner[verificationId];
        }

        emit VerificationRevoked(verificationId, owner, msg.sender, reason);
    }

    /**
     * @notice Renew an existing verification
     * @param verificationId Verification ID to renew
     * @param newExpiresAt New expiration timestamp
     * @param newProofHash Updated proof hash (if data changed)
     * @param newMetadataURI Updated IPFS URI (if data changed)
     */
    function renewVerification(
        uint256 verificationId,
        uint256 newExpiresAt,
        bytes32 newProofHash,
        string calldata newMetadataURI
    )
        external
        nonReentrant
    {
        _validateVerificationExists(verificationId);

        Verification storage verification = verifications[verificationId];

        // Only original verifier can renew
        if (msg.sender != verification.verifier) {
            revert UnauthorizedVerifier(msg.sender);
        }

        // Validate expiration
        if (newExpiresAt <= block.timestamp) {
            revert InvalidExpiration(newExpiresAt);
        }

        // Update verification
        verification.expiresAt = uint32(newExpiresAt);
        verification.verificationCount++;

        // Update proof hash if provided
        if (newProofHash != bytes32(0)) {
            verification.proofHash = newProofHash;
        }

        // Update metadata URI if provided
        if (bytes(newMetadataURI).length > 0) {
            verificationMetadata[verificationId] = newMetadataURI;
        }

        // Reactivate if was inactive and restore mappings
        address owner = _findOwner(verificationId);
        if (!verification.isActive) {
            verification.isActive = true;
            // Restore mappings if they were cleared during revocation
            if (owner != address(0)) {
                ownerAssetVerification[owner][verification.assetType] = verificationId;
                verificationOwner[verificationId] = owner;
            }
        }

        emit VerificationRenewed(verificationId, owner, newExpiresAt, verification.verificationCount);
    }

    // ============================================
    //           ADMIN FUNCTIONS
    // ============================================

    /**
     * @notice Add verifier to whitelist (admin only)
     * @param verifier Address to whitelist
     */
    function addVerifier(address verifier) external {
        if (!roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender)) {
            revert Errors.NotAdmin(msg.sender);
        }

        if (verifier == address(0)) revert Errors.InvalidVerifier();

        if (whitelistedVerifiers[verifier]) {
            revert VerifierAlreadyWhitelisted(verifier);
        }

        whitelistedVerifiers[verifier] = true;

        emit VerifierAdded(verifier, msg.sender);
    }

    /**
     * @notice Remove verifier from whitelist (admin only)
     * @param verifier Address to remove
     */
    function removeVerifier(address verifier) external {
        if (!roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender)) {
            revert Errors.NotAdmin(msg.sender);
        }

        if (!whitelistedVerifiers[verifier]) {
            revert VerifierNotWhitelisted(verifier);
        }

        whitelistedVerifiers[verifier] = false;

        emit VerifierRemoved(verifier, msg.sender);
    }

    // ============================================
    //          INTERNAL HELPERS
    // ============================================

    function _validateVerificationExists(uint256 verificationId) internal view {
        if (verificationId == 0 || verificationId > verificationCounter) {
            revert VerificationNotFound(verificationId);
        }
    }

    /**
     * @notice Find owner of a verification
     * @dev Uses reverse mapping for efficient O(1) lookup
     */
    function _findOwner(uint256 verificationId) internal view returns (address) {
        return verificationOwner[verificationId];
    }

    // ============================================
    //             VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Check if address is verified for asset type
     * @param owner Asset owner
     * @param assetType Type of asset
     * @return True if has active, non-expired verification
     */
    function isVerified(address owner, AssetTypes.AssetType assetType) external view returns (bool) {
        uint256 verificationId = ownerAssetVerification[owner][assetType];

        if (verificationId == 0) return false;

        Verification memory verification = verifications[verificationId];

        return verification.isActive && block.timestamp <= verification.expiresAt;
    }

    /**
     * @notice Get verification details
     */
    function getVerification(uint256 verificationId) external view returns (Verification memory) {
        _validateVerificationExists(verificationId);
        return verifications[verificationId];
    }

    /**
     * @notice Get all verifications for an owner
     */
    function getOwnerVerifications(address owner) external view returns (uint256[] memory) {
        return ownerVerifications[owner];
    }

    /**
     * @notice Get verification ID for owner + asset type
     */
    function getVerificationByOwnerAndType(
        address owner,
        AssetTypes.AssetType assetType
    )
        external
        view
        returns (uint256)
    {
        return ownerAssetVerification[owner][assetType];
    }

    /**
     * @notice Check if verification is expired
     */
    function isExpired(uint256 verificationId) external view returns (bool) {
        _validateVerificationExists(verificationId);
        return block.timestamp > verifications[verificationId].expiresAt;
    }
}

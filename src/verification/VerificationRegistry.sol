// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IVerificationRegistry.sol";
import "../libraries/AssetTypes.sol";
import "../libraries/Errors.sol";
import "../base/BaseMarketplaceContract.sol";

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
contract VerificationRegistry is IVerificationRegistry, BaseMarketplaceContract {
    using AssetTypes for AssetTypes.AssetType;

    // ============================================
    //          STATE VARIABLES
    // ============================================

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

    mapping(address => bool) public whitelistedVerifiers;

    /// @notice Challenge period for user-submitted verifications (7 days)
    uint256 public constant CHALLENGE_PERIOD = 7 days;

    /// @notice Minimum stake required to challenge a verification (0.01 ETH)
    uint256 public constant CHALLENGE_STAKE = 0.01 ether;

    /// @notice Mapping from verification ID to challenge data
    mapping(uint256 => Challenge) public challenges;

    /// @notice Pending user-submitted verifications (not yet approved)
    mapping(uint256 => bool) public pendingVerifications;

    uint256 public challengeCounter;

    struct Challenge {
        address challenger;
        uint256 stake;
        string evidence;
        uint32 challengedAt;
        ChallengeStatus status;
    }

    enum ChallengeStatus {
        None,
        Pending,
        Approved, // Challenge approved - verification invalid
        Rejected // Challenge rejected - verification valid

    }

    constructor(address _roleManager) BaseMarketplaceContract(_roleManager) {}

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
     * @notice Submit verification proof as a user (decentralized path)
     * @param assetType Type of asset being verified
     * @param proofHash SHA256 hash of verification data
     * @param expiresAt Expiration timestamp
     * @param metadataURI IPFS link to verification details and proof
     * @return verificationId Unique identifier
     * @dev User submits their own verification, enters challenge period
     *      If no valid challenge in 7 days, automatically approved
     */
    function submitUserVerification(
        AssetTypes.AssetType assetType,
        bytes32 proofHash,
        uint256 expiresAt,
        string calldata metadataURI
    )
        external
        nonReentrant
        returns (uint256 verificationId)
    {
        if (proofHash == bytes32(0)) revert InvalidProofHash();
        if (expiresAt <= block.timestamp + CHALLENGE_PERIOD) {
            revert InvalidExpiration(expiresAt);
        }
        assetType.validateAssetType();

        // Check if already verified for this asset type
        uint256 existingId = ownerAssetVerification[msg.sender][assetType];
        if (existingId != 0 && verifications[existingId].isActive) {
            revert AlreadyVerified(msg.sender, assetType);
        }

        verificationCounter++;
        verificationId = verificationCounter;

        // Create verification (starts as pending)
        verifications[verificationId] = Verification({
            proofHash: proofHash,
            verifier: msg.sender, // Self-verified
            verifiedAt: uint32(block.timestamp),
            expiresAt: uint32(expiresAt),
            assetType: assetType,
            isActive: false, // Not active until challenge period passes
            verificationCount: 1
        });

        pendingVerifications[verificationId] = true;

        verificationMetadata[verificationId] = metadataURI;

        ownerVerifications[msg.sender].push(verificationId);
        verificationOwner[verificationId] = msg.sender;

        emit UserVerificationSubmitted(verificationId, msg.sender, assetType, proofHash, expiresAt, metadataURI);

        return verificationId;
    }

    /**
     * @notice Finalize user-submitted verification after challenge period
     * @param verificationId Verification ID to finalize
     * @dev Can be called by anyone after challenge period if no active challenges
     */
    function finalizeUserVerification(uint256 verificationId) external nonReentrant {
        _validateVerificationExists(verificationId);

        Verification storage verification = verifications[verificationId];

        if (!pendingVerifications[verificationId]) {
            revert VerificationNotPending(verificationId);
        }

        if (block.timestamp < verification.verifiedAt + CHALLENGE_PERIOD) {
            revert ChallengePeriodNotEnded(verificationId);
        }

        // Check no active challenges
        Challenge storage challenge = challenges[verificationId];
        if (challenge.status == ChallengeStatus.Pending) {
            revert VerificationHasActiveChallenge(verificationId);
        }

        // Activate verification
        verification.isActive = true;
        pendingVerifications[verificationId] = false;

        address owner = _findOwner(verificationId);
        ownerAssetVerification[owner][verification.assetType] = verificationId;

        emit UserVerificationFinalized(verificationId, owner, verification.assetType);
    }

    /**
     * @notice Challenge a pending user-submitted verification
     * @param verificationId Verification ID to challenge
     * @param evidence IPFS link or description of why verification is invalid
     * @dev Requires CHALLENGE_STAKE to prevent spam
     */
    function challengeVerification(uint256 verificationId, string calldata evidence) external payable nonReentrant {
        _validateVerificationExists(verificationId);

        // Require stake
        if (msg.value < CHALLENGE_STAKE) {
            revert InsufficientChallengeStake(msg.value, CHALLENGE_STAKE);
        }

        Verification storage verification = verifications[verificationId];

        // Must be pending
        if (!pendingVerifications[verificationId]) {
            revert VerificationNotPending(verificationId);
        }

        // Must be within challenge period
        if (block.timestamp > verification.verifiedAt + CHALLENGE_PERIOD) {
            revert ChallengePeriodEnded(verificationId);
        }

        // Check no existing challenge
        if (challenges[verificationId].status == ChallengeStatus.Pending) {
            revert VerificationAlreadyChallenged(verificationId);
        }

        // Create challenge
        challenges[verificationId] = Challenge({
            challenger: msg.sender,
            stake: msg.value,
            evidence: evidence,
            challengedAt: uint32(block.timestamp),
            status: ChallengeStatus.Pending
        });

        emit VerificationChallenged(verificationId, msg.sender, evidence, msg.value);
    }

    /**
     * @notice Resolve a challenge (admin only)
     * @param verificationId Verification ID with challenge
     * @param approveChallenge True if challenge is valid, false if verification is legit
     * @dev If challenge approved: verification revoked, stake returned
     *      If challenge rejected: verification can be finalized, stake kept as penalty
     */
    function resolveChallenge(uint256 verificationId, bool approveChallenge) external onlyAdmin nonReentrant {
        _validateVerificationExists(verificationId);

        Challenge storage challenge = challenges[verificationId];
        Verification storage verification = verifications[verificationId];

        // Must have pending challenge
        if (challenge.status != ChallengeStatus.Pending) {
            revert NoActiveChallenge(verificationId);
        }

        if (approveChallenge) {
            // Challenge approved - verification is invalid
            challenge.status = ChallengeStatus.Approved;
            verification.isActive = false;
            pendingVerifications[verificationId] = false;

            // Return stake to challenger
            (bool success,) = challenge.challenger.call{value: challenge.stake}("");
            if (!success) {
                revert Errors.TransferFailed(challenge.challenger, challenge.stake);
            }

            emit ChallengeResolved(verificationId, true, challenge.challenger);
        } else {
            // Challenge rejected - verification is valid
            challenge.status = ChallengeStatus.Rejected;

            // Stake is kept (transferred to fee distributor or burned)
            // For now, keep in contract as protocol revenue

            emit ChallengeResolved(verificationId, false, challenge.challenger);
        }
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

        // Find owner and clear forward mapping (but keep reverse mapping for renewal)
        address owner = _findOwner(verificationId);
        if (owner != address(0)) {
            delete ownerAssetVerification[owner][verification.assetType];
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

    /**
     * @notice Add verifier to whitelist (admin only)
     * @param verifier Address to whitelist
     */
    function addVerifier(address verifier) external onlyAdmin {
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
    function removeVerifier(address verifier) external onlyAdmin {
        if (!whitelistedVerifiers[verifier]) {
            revert VerifierNotWhitelisted(verifier);
        }

        whitelistedVerifiers[verifier] = false;

        emit VerifierRemoved(verifier, msg.sender);
    }

    // ============================================
    //          INTERNAL FUNCTION
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

    function isVerified(address owner, AssetTypes.AssetType assetType) external view returns (bool) {
        uint256 verificationId = ownerAssetVerification[owner][assetType];

        if (verificationId == 0) return false;

        Verification memory verification = verifications[verificationId];

        return verification.isActive && block.timestamp <= verification.expiresAt;
    }

    function getVerification(uint256 verificationId) external view returns (Verification memory) {
        _validateVerificationExists(verificationId);
        return verifications[verificationId];
    }

    function getOwnerVerifications(address owner) external view returns (uint256[] memory) {
        return ownerVerifications[owner];
    }

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

    function isExpired(uint256 verificationId) external view returns (bool) {
        _validateVerificationExists(verificationId);
        return block.timestamp > verifications[verificationId].expiresAt;
    }
}

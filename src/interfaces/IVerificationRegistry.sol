// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetTypes} from "../libraries/AssetTypes.sol";

interface IVerificationRegistry {
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

    event VerificationAdded(
        uint256 indexed verificationId,
        address indexed owner,
        address indexed verifier,
        AssetTypes.AssetType assetType,
        bytes32 proofHash,
        uint256 expiresAt,
        string metadataURI
    );

    event VerificationRevoked(uint256 indexed verificationId, address indexed owner, address revokedBy, string reason);

    event VerificationRenewed(
        uint256 indexed verificationId, address indexed owner, uint256 newExpiresAt, uint256 renewalCount
    );

    event VerifierAdded(address indexed verifier, address addedBy);

    event VerifierRemoved(address indexed verifier, address removedBy);
    event UserVerificationSubmitted(
        uint256 indexed verificationId,
        address indexed owner,
        AssetTypes.AssetType assetType,
        bytes32 proofHash,
        uint256 expiresAt,
        string metadataURI
    );
    event UserVerificationFinalized(
        uint256 indexed verificationId, address indexed owner, AssetTypes.AssetType assetType
    );

    event VerificationChallenged(
        uint256 indexed verificationId, address indexed challenger, string evidence, uint256 stake
    );

    event ChallengeResolved(uint256 indexed verificationId, bool challengeApproved, address indexed challenger);

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

    error VerificationNotPending(uint256 verificationId);
    error ChallengePeriodNotEnded(uint256 verificationId);
    error ChallengePeriodEnded(uint256 verificationId);
    error VerificationHasActiveChallenge(uint256 verificationId);
    error VerificationAlreadyChallenged(uint256 verificationId);
    error InsufficientChallengeStake(uint256 provided, uint256 required);
    error NoActiveChallenge(uint256 verificationId);

    // ============================================
    //           CORE FUNCTIONS
    // ============================================
    function addVerification(
        address owner,
        AssetTypes.AssetType assetType,
        bytes32 proofHash,
        uint256 expiresAt,
        string calldata metadataURI
    )
        external
        returns (uint256 verificationId);

    function revokeVerification(uint256 verificationId, string calldata reason) external;

    function renewVerification(
        uint256 verificationId,
        uint256 newExpiresAt,
        bytes32 newProofHash,
        string calldata newMetadataURI
    )
        external;

    function addVerifier(address verifier) external;

    function removeVerifier(address verifier) external;

    // ============================================
    //        VIEW FUNCTIONS
    // ============================================

    function isVerified(address owner, AssetTypes.AssetType assetType) external view returns (bool);

    function getVerification(uint256 verificationId) external view returns (Verification memory);

    function getOwnerVerifications(address owner) external view returns (uint256[] memory);

    function getVerificationByOwnerAndType(
        address owner,
        AssetTypes.AssetType assetType
    )
        external
        view
        returns (uint256);

    function isExpired(uint256 verificationId) external view returns (bool);

    function verificationCounter() external view returns (uint256);
}

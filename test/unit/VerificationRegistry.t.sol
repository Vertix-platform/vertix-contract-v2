// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../../src/verification/VerificationRegistry.sol";
import "../../src/access/RoleManager.sol";
import "../../src/libraries/AssetTypes.sol";

contract VerificationRegistryTest is Test {
    VerificationRegistry public registry;
    RoleManager public roleManager;

    address public admin = address(0x1);
    address public verifier1 = address(0x2);
    address public verifier2 = address(0x3);
    address public user1 = address(0x4);
    address public user2 = address(0x5);
    address public unauthorized = address(0x6);

    // Test data
    bytes32 public constant PROOF_HASH_1 = keccak256("proof1");
    bytes32 public constant PROOF_HASH_2 = keccak256("proof2");
    string public constant METADATA_URI_1 = "ipfs://QmTest1";
    string public constant METADATA_URI_2 = "ipfs://QmTest2";

    uint256 public constant VERIFICATION_DURATION = 365 days;

    // Events
    event VerificationAdded(
        uint256 indexed verificationId,
        address indexed owner,
        address indexed verifier,
        AssetTypes.AssetType assetType,
        bytes32 proofHash,
        uint256 expiresAt,
        string metadataURI
    );

    event VerificationRevoked(
        uint256 indexed verificationId,
        address indexed owner,
        address indexed revoker,
        string reason
    );

    event VerificationRenewed(
        uint256 indexed verificationId,
        address indexed owner,
        uint256 newExpiresAt,
        uint256 verificationCount
    );

    event VerifierAdded(address indexed verifier, address indexed admin);
    event VerifierRemoved(address indexed verifier, address indexed admin);

    function setUp() public {
        vm.startPrank(admin);

        // Deploy RoleManager
        roleManager = new RoleManager(admin);

        // Deploy VerificationRegistry
        registry = new VerificationRegistry(address(roleManager));

        // Grant admin role and whitelist verifiers
        registry.addVerifier(verifier1);
        registry.addVerifier(verifier2);

        vm.stopPrank();
    }

    // ============================================
    // CONSTRUCTOR TESTS
    // ============================================

    function test_constructor_Success() public {
        VerificationRegistry newRegistry = new VerificationRegistry(
            address(roleManager)
        );
        assertEq(address(newRegistry.roleManager()), address(roleManager));
        assertEq(newRegistry.verificationCounter(), 0);
    }

    function test_constructor_RevertIf_InvalidRoleManager() public {
        vm.expectRevert("Invalid role manager");
        new VerificationRegistry(address(0));
    }

    // ============================================
    // ADD VERIFICATION TESTS
    // ============================================

    function test_addVerification_Success() public {
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.startPrank(verifier1);

        vm.expectEmit(true, true, true, true);
        emit VerificationAdded(
            1,
            user1,
            verifier1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        uint256 verificationId = registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        vm.stopPrank();

        assertEq(verificationId, 1);
        assertEq(registry.verificationCounter(), 1);

        // Check verification data
        IVerificationRegistry.Verification memory verification = registry
            .getVerification(verificationId);
        assertEq(verification.proofHash, PROOF_HASH_1);
        assertEq(verification.verifier, verifier1);
        assertEq(verification.verifiedAt, block.timestamp);
        assertEq(verification.expiresAt, expiresAt);
        assertEq(
            uint8(verification.assetType),
            uint8(AssetTypes.AssetType.SocialMediaYouTube)
        );
        assertTrue(verification.isActive);
        assertEq(verification.verificationCount, 1);

        // Check metadata
        assertEq(
            registry.getVerificationMetadata(verificationId),
            METADATA_URI_1
        );

        // Check owner mapping
        uint256[] memory ownerVerifs = registry.getOwnerVerifications(user1);
        assertEq(ownerVerifs.length, 1);
        assertEq(ownerVerifs[0], verificationId);

        // Check asset type mapping
        assertEq(
            registry.getVerificationByOwnerAndType(
                user1,
                AssetTypes.AssetType.SocialMediaYouTube
            ),
            verificationId
        );

        // Check isVerified
        assertTrue(
            registry.isVerified(user1, AssetTypes.AssetType.SocialMediaYouTube)
        );
    }

    function test_addVerification_MultipleAssetTypes() public {
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.startPrank(verifier1);

        // Add YouTube verification
        uint256 id1 = registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        // Add Twitter verification for same user
        uint256 id2 = registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaTwitter,
            PROOF_HASH_2,
            expiresAt,
            METADATA_URI_2
        );

        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);

        assertTrue(
            registry.isVerified(user1, AssetTypes.AssetType.SocialMediaYouTube)
        );
        assertTrue(
            registry.isVerified(user1, AssetTypes.AssetType.SocialMediaTwitter)
        );

        uint256[] memory ownerVerifs = registry.getOwnerVerifications(user1);
        assertEq(ownerVerifs.length, 2);
    }

    function test_addVerification_RevertIf_UnauthorizedVerifier() public {
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVerificationRegistry.UnauthorizedVerifier.selector,
                unauthorized
            )
        );
        registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );
    }

    function test_addVerification_RevertIf_InvalidOwner() public {
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.prank(verifier1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVerificationRegistry.InvalidOwner.selector,
                address(0)
            )
        );
        registry.addVerification(
            address(0),
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );
    }

    function test_addVerification_RevertIf_InvalidProofHash() public {
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.prank(verifier1);
        vm.expectRevert(IVerificationRegistry.InvalidProofHash.selector);
        registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            bytes32(0),
            expiresAt,
            METADATA_URI_1
        );
    }

    function test_addVerification_RevertIf_InvalidExpiration() public {
        uint256 pastTime = block.timestamp - 1;

        vm.prank(verifier1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVerificationRegistry.InvalidExpiration.selector,
                pastTime
            )
        );
        registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            pastTime,
            METADATA_URI_1
        );
    }

    function test_addVerification_RevertIf_AlreadyVerified() public {
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.startPrank(verifier1);

        // First verification succeeds
        registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        // Second verification for same asset type fails
        vm.expectRevert(
            abi.encodeWithSelector(
                IVerificationRegistry.AlreadyVerified.selector,
                user1,
                AssetTypes.AssetType.SocialMediaYouTube
            )
        );
        registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_2,
            expiresAt,
            METADATA_URI_2
        );

        vm.stopPrank();
    }

    // ============================================
    // REVOKE VERIFICATION TESTS
    // ============================================

    function test_revokeVerification_ByVerifier() public {
        // Add verification first
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.prank(verifier1);
        uint256 verificationId = registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        // Revoke by original verifier
        vm.prank(verifier1);
        vm.expectEmit(true, true, true, true);
        emit VerificationRevoked(
            verificationId,
            address(0),
            verifier1,
            "Test revocation"
        );

        registry.revokeVerification(verificationId, "Test revocation");

        // Check verification is inactive
        IVerificationRegistry.Verification memory verification = registry
            .getVerification(verificationId);
        assertFalse(verification.isActive);

        // Check isVerified returns false
        assertFalse(
            registry.isVerified(user1, AssetTypes.AssetType.SocialMediaYouTube)
        );
    }

    function test_revokeVerification_ByAdmin() public {
        // Add verification first
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.prank(verifier1);
        uint256 verificationId = registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        // Revoke by admin (not original verifier)
        vm.prank(admin);
        registry.revokeVerification(verificationId, "Admin revocation");

        // Check verification is inactive
        IVerificationRegistry.Verification memory verification = registry
            .getVerification(verificationId);
        assertFalse(verification.isActive);
    }

    function test_revokeVerification_RevertIf_NotFound() public {
        vm.prank(verifier1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVerificationRegistry.VerificationNotFound.selector,
                999
            )
        );
        registry.revokeVerification(999, "Not found");
    }

    function test_revokeVerification_RevertIf_NotAuthorized() public {
        // Add verification first
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.prank(verifier1);
        uint256 verificationId = registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        // Try to revoke by unauthorized user
        vm.prank(unauthorized);
        vm.expectRevert("Not authorized to revoke");
        registry.revokeVerification(verificationId, "Unauthorized attempt");
    }

    function test_revokeVerification_RevertIf_AlreadyInactive() public {
        // Add and revoke verification
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.startPrank(verifier1);
        uint256 verificationId = registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        registry.revokeVerification(verificationId, "First revocation");

        // Try to revoke again
        vm.expectRevert(
            abi.encodeWithSelector(
                IVerificationRegistry.VerificationNotActive.selector,
                verificationId
            )
        );
        registry.revokeVerification(verificationId, "Second revocation");

        vm.stopPrank();
    }

    // ============================================
    // RENEW VERIFICATION TESTS
    // ============================================

    function test_renewVerification_Success() public {
        // Add verification first
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.prank(verifier1);
        uint256 verificationId = registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        // Move time forward
        vm.warp(block.timestamp + 180 days);

        // Renew verification
        uint256 newExpiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.prank(verifier1);
        vm.expectEmit(true, true, true, true);
        emit VerificationRenewed(verificationId, address(0), newExpiresAt, 2);

        registry.renewVerification(
            verificationId,
            newExpiresAt,
            PROOF_HASH_2,
            METADATA_URI_2
        );

        // Check updated data
        IVerificationRegistry.Verification memory verification = registry
            .getVerification(verificationId);
        assertEq(verification.expiresAt, newExpiresAt);
        assertEq(verification.proofHash, PROOF_HASH_2);
        assertEq(verification.verificationCount, 2);
        assertTrue(verification.isActive);

        assertEq(
            registry.getVerificationMetadata(verificationId),
            METADATA_URI_2
        );
    }

    function test_renewVerification_WithoutUpdatingProof() public {
        // Add verification first
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.prank(verifier1);
        uint256 verificationId = registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        // Renew without changing proof hash
        uint256 newExpiresAt = block.timestamp + VERIFICATION_DURATION * 2;

        vm.prank(verifier1);
        registry.renewVerification(
            verificationId,
            newExpiresAt,
            bytes32(0), // Don't update proof
            "" // Don't update metadata
        );

        // Check proof hash unchanged
        IVerificationRegistry.Verification memory verification = registry
            .getVerification(verificationId);
        assertEq(verification.proofHash, PROOF_HASH_1);
        assertEq(
            registry.getVerificationMetadata(verificationId),
            METADATA_URI_1
        );
        assertEq(verification.expiresAt, newExpiresAt);
    }

    function test_renewVerification_ReactivatesInactive() public {
        // Add and revoke verification
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.startPrank(verifier1);
        uint256 verificationId = registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        registry.revokeVerification(verificationId, "Test revocation");

        // Verify it's inactive
        IVerificationRegistry.Verification memory verification = registry
            .getVerification(verificationId);
        assertFalse(verification.isActive);

        // Renew should reactivate
        uint256 newExpiresAt = block.timestamp + VERIFICATION_DURATION;
        registry.renewVerification(
            verificationId,
            newExpiresAt,
            bytes32(0),
            ""
        );

        verification = registry.getVerification(verificationId);
        assertTrue(verification.isActive);

        vm.stopPrank();
    }

    function test_renewVerification_RevertIf_NotOriginalVerifier() public {
        // Add verification with verifier1
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.prank(verifier1);
        uint256 verificationId = registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        // Try to renew with verifier2
        uint256 newExpiresAt = block.timestamp + VERIFICATION_DURATION * 2;

        vm.prank(verifier2);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVerificationRegistry.UnauthorizedVerifier.selector,
                verifier2
            )
        );
        registry.renewVerification(
            verificationId,
            newExpiresAt,
            bytes32(0),
            ""
        );
    }

    function test_renewVerification_RevertIf_InvalidExpiration() public {
        // Add verification first
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.prank(verifier1);
        uint256 verificationId = registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        // Try to renew with past expiration
        uint256 pastTime = block.timestamp - 1;

        vm.prank(verifier1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVerificationRegistry.InvalidExpiration.selector,
                pastTime
            )
        );
        registry.renewVerification(verificationId, pastTime, bytes32(0), "");
    }

    // ============================================
    // VERIFIER MANAGEMENT TESTS
    // ============================================

    function test_addVerifier_Success() public {
        address newVerifier = address(0x7);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit VerifierAdded(newVerifier, admin);

        registry.addVerifier(newVerifier);

        assertTrue(registry.isWhitelistedVerifier(newVerifier));
    }

    function test_addVerifier_RevertIf_NotAdmin() public {
        address newVerifier = address(0x7);

        vm.prank(unauthorized);
        vm.expectRevert("Not admin");
        registry.addVerifier(newVerifier);
    }

    function test_addVerifier_RevertIf_InvalidAddress() public {
        vm.prank(admin);
        vm.expectRevert("Invalid verifier");
        registry.addVerifier(address(0));
    }

    function test_addVerifier_RevertIf_AlreadyWhitelisted() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVerificationRegistry.VerifierAlreadyWhitelisted.selector,
                verifier1
            )
        );
        registry.addVerifier(verifier1);
    }

    function test_removeVerifier_Success() public {
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit VerifierRemoved(verifier1, admin);

        registry.removeVerifier(verifier1);

        assertFalse(registry.isWhitelistedVerifier(verifier1));
    }

    function test_removeVerifier_RevertIf_NotAdmin() public {
        vm.prank(unauthorized);
        vm.expectRevert("Not admin");
        registry.removeVerifier(verifier1);
    }

    function test_removeVerifier_RevertIf_NotWhitelisted() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVerificationRegistry.VerifierNotWhitelisted.selector,
                unauthorized
            )
        );
        registry.removeVerifier(unauthorized);
    }

    // ============================================
    // VIEW FUNCTION TESTS
    // ============================================

    function test_isVerified_ActiveAndNotExpired() public {
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.prank(verifier1);
        registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        assertTrue(
            registry.isVerified(user1, AssetTypes.AssetType.SocialMediaYouTube)
        );
    }

    function test_isVerified_ReturnsFalseIfExpired() public {
        uint256 expiresAt = block.timestamp + 1 days;

        vm.prank(verifier1);
        registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        // Move past expiration
        vm.warp(block.timestamp + 2 days);

        assertFalse(
            registry.isVerified(user1, AssetTypes.AssetType.SocialMediaYouTube)
        );
    }

    function test_isVerified_ReturnsFalseIfRevoked() public {
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.startPrank(verifier1);
        uint256 verificationId = registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        registry.revokeVerification(verificationId, "Test");
        vm.stopPrank();

        assertFalse(
            registry.isVerified(user1, AssetTypes.AssetType.SocialMediaYouTube)
        );
    }

    function test_isVerified_ReturnsFalseIfNeverVerified() public {
        assertFalse(
            registry.isVerified(user1, AssetTypes.AssetType.SocialMediaYouTube)
        );
    }

    function test_isExpired_True() public {
        uint256 expiresAt = block.timestamp + 1 days;

        vm.prank(verifier1);
        uint256 verificationId = registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        // Move past expiration
        vm.warp(block.timestamp + 2 days);

        assertTrue(registry.isExpired(verificationId));
    }

    function test_isExpired_False() public {
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.prank(verifier1);
        uint256 verificationId = registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        assertFalse(registry.isExpired(verificationId));
    }

    function test_timeUntilExpiration_ReturnsCorrectTime() public {
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.prank(verifier1);
        uint256 verificationId = registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        assertEq(
            registry.timeUntilExpiration(verificationId),
            VERIFICATION_DURATION
        );

        // Move forward 100 days
        vm.warp(block.timestamp + 100 days);

        assertEq(
            registry.timeUntilExpiration(verificationId),
            VERIFICATION_DURATION - 100 days
        );
    }

    function test_timeUntilExpiration_ReturnsZeroIfExpired() public {
        uint256 expiresAt = block.timestamp + 1 days;

        vm.prank(verifier1);
        uint256 verificationId = registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        // Move past expiration
        vm.warp(block.timestamp + 2 days);

        assertEq(registry.timeUntilExpiration(verificationId), 0);
    }

    function test_getOwnerVerifications_Multiple() public {
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.startPrank(verifier1);

        registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaTwitter,
            PROOF_HASH_2,
            expiresAt,
            METADATA_URI_2
        );

        vm.stopPrank();

        uint256[] memory ownerVerifs = registry.getOwnerVerifications(user1);
        assertEq(ownerVerifs.length, 2);
        assertEq(ownerVerifs[0], 1);
        assertEq(ownerVerifs[1], 2);
    }

    function test_getOwnerVerifications_Empty() public {
        uint256[] memory ownerVerifs = registry.getOwnerVerifications(user1);
        assertEq(ownerVerifs.length, 0);
    }

    // ============================================
    // FUZZ TESTS
    // ============================================

    function testFuzz_addVerification_ValidInputs(
        address owner,
        uint256 duration
    ) public {
        // Bound inputs
        vm.assume(owner != address(0));
        duration = bound(duration, 1 days, 730 days);

        uint256 expiresAt = block.timestamp + duration;

        vm.prank(verifier1);
        uint256 verificationId = registry.addVerification(
            owner,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        assertTrue(verificationId > 0);
        assertTrue(
            registry.isVerified(owner, AssetTypes.AssetType.SocialMediaYouTube)
        );
    }

    function testFuzz_renewVerification_ValidExpiration(
        uint256 newDuration
    ) public {
        // Add initial verification
        uint256 expiresAt = block.timestamp + VERIFICATION_DURATION;

        vm.prank(verifier1);
        uint256 verificationId = registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        // Bound new duration
        newDuration = bound(newDuration, 1 days, 730 days);
        uint256 newExpiresAt = block.timestamp + newDuration;

        vm.prank(verifier1);
        registry.renewVerification(
            verificationId,
            newExpiresAt,
            bytes32(0),
            ""
        );

        IVerificationRegistry.Verification memory verification = registry
            .getVerification(verificationId);
        assertEq(verification.expiresAt, newExpiresAt);
        assertEq(verification.verificationCount, 2);
    }

    function testFuzz_timeUntilExpiration(
        uint256 duration,
        uint256 timePassed
    ) public {
        duration = bound(duration, 1 days, 730 days);
        timePassed = bound(timePassed, 0, duration - 1);

        uint256 expiresAt = block.timestamp + duration;

        vm.prank(verifier1);
        uint256 verificationId = registry.addVerification(
            user1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            expiresAt,
            METADATA_URI_1
        );

        vm.warp(block.timestamp + timePassed);

        uint256 remaining = registry.timeUntilExpiration(verificationId);
        assertEq(remaining, duration - timePassed);
    }
}

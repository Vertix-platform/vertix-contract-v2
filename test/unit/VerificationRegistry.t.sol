// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {VerificationRegistry} from "../../src/verification/VerificationRegistry.sol";
import {RoleManager} from "../../src/access/RoleManager.sol";
import {IVerificationRegistry} from "../../src/interfaces/IVerificationRegistry.sol";
import {AssetTypes} from "../../src/libraries/AssetTypes.sol";
import {Errors} from "../../src/libraries/Errors.sol";

contract VerificationRegistryTest is Test {
    VerificationRegistry public verificationRegistry;
    RoleManager public roleManager;

    address public admin;
    address public verifier1;
    address public verifier2;
    address public assetOwner1;
    address public assetOwner2;
    address public unauthorized;

    bytes32 public constant PROOF_HASH_1 = keccak256("proof1");
    bytes32 public constant PROOF_HASH_2 = keccak256("proof2");
    string public constant METADATA_URI_1 = "ipfs://QmTest1";
    string public constant METADATA_URI_2 = "ipfs://QmTest2";

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
    event VerificationRevoked(uint256 indexed verificationId, address indexed owner, address revokedBy, string reason);
    event VerificationRenewed(
        uint256 indexed verificationId, address indexed owner, uint256 newExpiresAt, uint256 renewalCount
    );
    event VerifierAdded(address indexed verifier, address addedBy);
    event VerifierRemoved(address indexed verifier, address removedBy);

    function setUp() public {
        admin = makeAddr("admin");
        verifier1 = makeAddr("verifier1");
        verifier2 = makeAddr("verifier2");
        assetOwner1 = makeAddr("assetOwner1");
        assetOwner2 = makeAddr("assetOwner2");
        unauthorized = makeAddr("unauthorized");

        // Deploy role manager
        roleManager = new RoleManager(admin);

        // Deploy verification registry
        verificationRegistry = new VerificationRegistry(address(roleManager));

        // Add verifier1 to whitelist
        vm.prank(admin);
        verificationRegistry.addVerifier(verifier1);
    }

    // ============================================
    //          CONSTRUCTOR TESTS
    // ============================================

    function test_Constructor_SetsRoleManager() public view {
        assertEq(address(verificationRegistry.roleManager()), address(roleManager));
    }

    function test_Constructor_RevertsOnZeroAddress() public {
        vm.expectRevert(Errors.InvalidRoleManager.selector);
        new VerificationRegistry(address(0));
    }

    function test_Constructor_InitializesCounter() public view {
        assertEq(verificationRegistry.verificationCounter(), 0);
    }

    // ============================================
    //       ADD VERIFIER TESTS
    // ============================================

    function test_AddVerifier_AdminCanAdd() public {
        vm.startPrank(admin);

        vm.expectEmit(true, false, false, true);
        emit VerifierAdded(verifier2, admin);

        verificationRegistry.addVerifier(verifier2);

        assertTrue(verificationRegistry.whitelistedVerifiers(verifier2));

        vm.stopPrank();
    }

    function test_AddVerifier_RevertsOnZeroAddress() public {
        vm.startPrank(admin);

        vm.expectRevert(Errors.InvalidVerifier.selector);
        verificationRegistry.addVerifier(address(0));

        vm.stopPrank();
    }

    function test_AddVerifier_RevertsIfAlreadyWhitelisted() public {
        vm.startPrank(admin);

        vm.expectRevert(abi.encodeWithSelector(IVerificationRegistry.VerifierAlreadyWhitelisted.selector, verifier1));
        verificationRegistry.addVerifier(verifier1);

        vm.stopPrank();
    }

    function test_AddVerifier_RevertsIfNotAdmin() public {
        vm.startPrank(unauthorized);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotAdmin.selector, unauthorized));
        verificationRegistry.addVerifier(verifier2);

        vm.stopPrank();
    }

    // ============================================
    //       REMOVE VERIFIER TESTS
    // ============================================

    function test_RemoveVerifier_AdminCanRemove() public {
        vm.startPrank(admin);

        vm.expectEmit(true, false, false, true);
        emit VerifierRemoved(verifier1, admin);

        verificationRegistry.removeVerifier(verifier1);

        assertFalse(verificationRegistry.whitelistedVerifiers(verifier1));

        vm.stopPrank();
    }

    function test_RemoveVerifier_RevertsIfNotWhitelisted() public {
        vm.startPrank(admin);

        vm.expectRevert(abi.encodeWithSelector(IVerificationRegistry.VerifierNotWhitelisted.selector, verifier2));
        verificationRegistry.removeVerifier(verifier2);

        vm.stopPrank();
    }

    function test_RemoveVerifier_RevertsIfNotAdmin() public {
        vm.startPrank(unauthorized);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotAdmin.selector, unauthorized));
        verificationRegistry.removeVerifier(verifier1);

        vm.stopPrank();
    }

    // ============================================
    //       ADD VERIFICATION TESTS
    // ============================================

    function test_AddVerification_SuccessfullyAddsVerification() public {
        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + 365 days;

        vm.expectEmit(true, true, true, true);
        emit VerificationAdded(
            1, assetOwner1, verifier1, AssetTypes.AssetType.SocialMediaYouTube, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaYouTube, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        assertEq(verificationId, 1);
        assertEq(verificationRegistry.verificationCounter(), 1);

        vm.stopPrank();
    }

    function test_AddVerification_StoresCorrectData() public {
        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + 365 days;

        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaTwitter, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        IVerificationRegistry.Verification memory verification = verificationRegistry.getVerification(verificationId);

        assertEq(verification.proofHash, PROOF_HASH_1);
        assertEq(verification.verifier, verifier1);
        assertEq(verification.verifiedAt, block.timestamp);
        assertEq(verification.expiresAt, expiresAt);
        assertEq(uint8(verification.assetType), uint8(AssetTypes.AssetType.SocialMediaTwitter));
        assertTrue(verification.isActive);
        assertEq(verification.verificationCount, 1);

        vm.stopPrank();
    }

    function test_AddVerification_StoresMetadataURI() public {
        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + 365 days;

        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.Domain, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        string memory storedMetadata = verificationRegistry.verificationMetadata(verificationId);
        assertEq(storedMetadata, METADATA_URI_1);

        vm.stopPrank();
    }

    function test_AddVerification_TracksOwnership() public {
        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + 365 days;

        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.Website, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        uint256[] memory ownerVerifications = verificationRegistry.getOwnerVerifications(assetOwner1);
        assertEq(ownerVerifications.length, 1);
        assertEq(ownerVerifications[0], verificationId);

        uint256 assetVerificationId =
            verificationRegistry.ownerAssetVerification(assetOwner1, AssetTypes.AssetType.Website);
        assertEq(assetVerificationId, verificationId);

        address verificationOwner = verificationRegistry.verificationOwner(verificationId);
        assertEq(verificationOwner, assetOwner1);

        vm.stopPrank();
    }

    function test_AddVerification_RevertsIfNotWhitelisted() public {
        vm.startPrank(unauthorized);

        uint256 expiresAt = block.timestamp + 365 days;

        vm.expectRevert(abi.encodeWithSelector(IVerificationRegistry.UnauthorizedVerifier.selector, unauthorized));

        verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaYouTube, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        vm.stopPrank();
    }

    function test_AddVerification_RevertsOnZeroOwner() public {
        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + 365 days;

        vm.expectRevert(abi.encodeWithSelector(IVerificationRegistry.InvalidOwner.selector, address(0)));

        verificationRegistry.addVerification(
            address(0), AssetTypes.AssetType.SocialMediaYouTube, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        vm.stopPrank();
    }

    function test_AddVerification_RevertsOnZeroProofHash() public {
        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + 365 days;

        vm.expectRevert(IVerificationRegistry.InvalidProofHash.selector);

        verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaYouTube, bytes32(0), expiresAt, METADATA_URI_1
        );

        vm.stopPrank();
    }

    function test_AddVerification_RevertsOnPastExpiration() public {
        vm.startPrank(verifier1);

        // Move to a future time to avoid underflow
        vm.warp(100 days);
        uint256 expiresAt = block.timestamp - 1 days;

        vm.expectRevert(abi.encodeWithSelector(IVerificationRegistry.InvalidExpiration.selector, expiresAt));

        verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaYouTube, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        vm.stopPrank();
    }

    function test_AddVerification_RevertsIfAlreadyVerified() public {
        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + 365 days;

        // Add first verification
        verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaYouTube, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        // Try to add duplicate
        vm.expectRevert(
            abi.encodeWithSelector(
                IVerificationRegistry.AlreadyVerified.selector, assetOwner1, AssetTypes.AssetType.SocialMediaYouTube
            )
        );

        verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaYouTube, PROOF_HASH_2, expiresAt, METADATA_URI_2
        );

        vm.stopPrank();
    }

    function test_AddVerification_AllowsMultipleAssetTypes() public {
        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + 365 days;

        uint256 id1 = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaYouTube, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        uint256 id2 = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaTwitter, PROOF_HASH_2, expiresAt, METADATA_URI_2
        );

        assertEq(id1, 1);
        assertEq(id2, 2);

        uint256[] memory ownerVerifications = verificationRegistry.getOwnerVerifications(assetOwner1);
        assertEq(ownerVerifications.length, 2);

        vm.stopPrank();
    }

    // ============================================
    //       REVOKE VERIFICATION TESTS
    // ============================================

    function test_RevokeVerification_VerifierCanRevoke() public {
        // Add verification
        vm.prank(verifier1);
        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            block.timestamp + 365 days,
            METADATA_URI_1
        );

        // Revoke verification
        vm.startPrank(verifier1);

        vm.expectEmit(true, true, false, true);
        emit VerificationRevoked(verificationId, assetOwner1, verifier1, "Test revocation");

        verificationRegistry.revokeVerification(verificationId, "Test revocation");

        IVerificationRegistry.Verification memory verification = verificationRegistry.getVerification(verificationId);
        assertFalse(verification.isActive);

        vm.stopPrank();
    }

    function test_RevokeVerification_AdminCanRevoke() public {
        // Add verification
        vm.prank(verifier1);
        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1,
            AssetTypes.AssetType.SocialMediaTwitter,
            PROOF_HASH_1,
            block.timestamp + 365 days,
            METADATA_URI_1
        );

        // Admin revokes
        vm.startPrank(admin);

        verificationRegistry.revokeVerification(verificationId, "Admin revocation");

        IVerificationRegistry.Verification memory verification = verificationRegistry.getVerification(verificationId);
        assertFalse(verification.isActive);

        vm.stopPrank();
    }

    function test_RevokeVerification_ClearsMappings() public {
        // Add verification
        vm.prank(verifier1);
        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.Domain, PROOF_HASH_1, block.timestamp + 365 days, METADATA_URI_1
        );

        // Verify mappings exist
        assertEq(verificationRegistry.ownerAssetVerification(assetOwner1, AssetTypes.AssetType.Domain), verificationId);
        assertEq(verificationRegistry.verificationOwner(verificationId), assetOwner1);

        // Revoke
        vm.prank(verifier1);
        verificationRegistry.revokeVerification(verificationId, "test");

        // Check forward mapping cleared (but reverse mapping preserved for renewal)
        assertEq(verificationRegistry.ownerAssetVerification(assetOwner1, AssetTypes.AssetType.Domain), 0);
        // Reverse mapping preserved to allow renewal
        assertEq(verificationRegistry.verificationOwner(verificationId), assetOwner1);
    }

    function test_RevokeVerification_RevertsIfNotFound() public {
        vm.startPrank(verifier1);

        vm.expectRevert(abi.encodeWithSelector(IVerificationRegistry.VerificationNotFound.selector, 999));

        verificationRegistry.revokeVerification(999, "test");

        vm.stopPrank();
    }

    function test_RevokeVerification_RevertsIfNotActive() public {
        // Add and revoke verification
        vm.startPrank(verifier1);
        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            block.timestamp + 365 days,
            METADATA_URI_1
        );

        verificationRegistry.revokeVerification(verificationId, "first revoke");

        // Try to revoke again
        vm.expectRevert(abi.encodeWithSelector(IVerificationRegistry.VerificationNotActive.selector, verificationId));

        verificationRegistry.revokeVerification(verificationId, "second revoke");

        vm.stopPrank();
    }

    function test_RevokeVerification_RevertsIfUnauthorized() public {
        // Add verification
        vm.prank(verifier1);
        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            block.timestamp + 365 days,
            METADATA_URI_1
        );

        // Unauthorized user tries to revoke
        vm.startPrank(unauthorized);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthorized.selector, unauthorized));

        verificationRegistry.revokeVerification(verificationId, "unauthorized attempt");

        vm.stopPrank();
    }

    // ============================================
    //       RENEW VERIFICATION TESTS
    // ============================================

    function test_RenewVerification_SuccessfullyRenews() public {
        // Add verification
        vm.startPrank(verifier1);
        uint256 expiresAt = block.timestamp + 365 days;
        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaYouTube, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        // Renew verification
        uint256 newExpiresAt = block.timestamp + 730 days;

        vm.expectEmit(true, true, false, true);
        emit VerificationRenewed(verificationId, assetOwner1, newExpiresAt, 2);

        verificationRegistry.renewVerification(verificationId, newExpiresAt, bytes32(0), "");

        IVerificationRegistry.Verification memory verification = verificationRegistry.getVerification(verificationId);
        assertEq(verification.expiresAt, newExpiresAt);
        assertEq(verification.verificationCount, 2);

        vm.stopPrank();
    }

    function test_RenewVerification_UpdatesProofHash() public {
        // Add verification
        vm.startPrank(verifier1);
        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1,
            AssetTypes.AssetType.SocialMediaTwitter,
            PROOF_HASH_1,
            block.timestamp + 365 days,
            METADATA_URI_1
        );

        // Renew with new proof hash
        uint256 newExpiresAt = block.timestamp + 730 days;
        verificationRegistry.renewVerification(verificationId, newExpiresAt, PROOF_HASH_2, "");

        IVerificationRegistry.Verification memory verification = verificationRegistry.getVerification(verificationId);
        assertEq(verification.proofHash, PROOF_HASH_2);

        vm.stopPrank();
    }

    function test_RenewVerification_UpdatesMetadataURI() public {
        // Add verification
        vm.startPrank(verifier1);
        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.Domain, PROOF_HASH_1, block.timestamp + 365 days, METADATA_URI_1
        );

        // Renew with new metadata
        uint256 newExpiresAt = block.timestamp + 730 days;
        verificationRegistry.renewVerification(verificationId, newExpiresAt, bytes32(0), METADATA_URI_2);

        string memory metadata = verificationRegistry.verificationMetadata(verificationId);
        assertEq(metadata, METADATA_URI_2);

        vm.stopPrank();
    }

    function test_RenewVerification_ReactivatesIfInactive() public {
        // Add and revoke verification
        vm.startPrank(verifier1);
        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.Website, PROOF_HASH_1, block.timestamp + 365 days, METADATA_URI_1
        );

        verificationRegistry.revokeVerification(verificationId, "test");

        IVerificationRegistry.Verification memory verificationBefore =
            verificationRegistry.getVerification(verificationId);
        assertFalse(verificationBefore.isActive);

        // Renew verification
        uint256 newExpiresAt = block.timestamp + 730 days;
        verificationRegistry.renewVerification(verificationId, newExpiresAt, bytes32(0), "");

        IVerificationRegistry.Verification memory verificationAfter =
            verificationRegistry.getVerification(verificationId);
        assertTrue(verificationAfter.isActive);

        vm.stopPrank();
    }

    function test_RenewVerification_RestoresMappingsAfterRevocation() public {
        // Add and revoke verification
        vm.startPrank(verifier1);
        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            block.timestamp + 365 days,
            METADATA_URI_1
        );

        verificationRegistry.revokeVerification(verificationId, "test");

        // Check forward mapping cleared (but reverse mapping preserved)
        assertEq(verificationRegistry.ownerAssetVerification(assetOwner1, AssetTypes.AssetType.SocialMediaYouTube), 0);
        // Reverse mapping should still exist for renewal
        assertEq(verificationRegistry.verificationOwner(verificationId), assetOwner1);

        // Renew verification
        uint256 newExpiresAt = block.timestamp + 730 days;
        verificationRegistry.renewVerification(verificationId, newExpiresAt, bytes32(0), "");

        // Mappings should be restored after renewal
        assertEq(
            verificationRegistry.ownerAssetVerification(assetOwner1, AssetTypes.AssetType.SocialMediaYouTube),
            verificationId
        );
        assertEq(verificationRegistry.verificationOwner(verificationId), assetOwner1);

        // Verification is reactivated
        IVerificationRegistry.Verification memory verification = verificationRegistry.getVerification(verificationId);
        assertTrue(verification.isActive);

        vm.stopPrank();
    }

    function test_RenewVerification_RevertsIfNotFound() public {
        vm.startPrank(verifier1);

        vm.expectRevert(abi.encodeWithSelector(IVerificationRegistry.VerificationNotFound.selector, 999));

        verificationRegistry.renewVerification(999, block.timestamp + 365 days, bytes32(0), "");

        vm.stopPrank();
    }

    function test_RenewVerification_RevertsIfNotOriginalVerifier() public {
        // Add verification with verifier1
        vm.prank(verifier1);
        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            block.timestamp + 365 days,
            METADATA_URI_1
        );

        // Add verifier2 to whitelist
        vm.prank(admin);
        verificationRegistry.addVerifier(verifier2);

        // Try to renew with verifier2
        vm.startPrank(verifier2);

        vm.expectRevert(abi.encodeWithSelector(IVerificationRegistry.UnauthorizedVerifier.selector, verifier2));

        verificationRegistry.renewVerification(verificationId, block.timestamp + 730 days, bytes32(0), "");

        vm.stopPrank();
    }

    function test_RenewVerification_RevertsOnPastExpiration() public {
        // Move to a future time to avoid underflow
        vm.warp(100 days);

        // Add verification
        vm.startPrank(verifier1);
        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1,
            AssetTypes.AssetType.SocialMediaYouTube,
            PROOF_HASH_1,
            block.timestamp + 365 days,
            METADATA_URI_1
        );

        // Try to renew with past expiration
        uint256 pastExpiration = block.timestamp - 1 days;

        vm.expectRevert(abi.encodeWithSelector(IVerificationRegistry.InvalidExpiration.selector, pastExpiration));

        verificationRegistry.renewVerification(verificationId, pastExpiration, bytes32(0), "");

        vm.stopPrank();
    }

    // ============================================
    //          VIEW FUNCTION TESTS
    // ============================================

    function test_IsVerified_ReturnsTrueForActiveNonExpired() public {
        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + 365 days;
        verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaYouTube, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        bool verified = verificationRegistry.isVerified(assetOwner1, AssetTypes.AssetType.SocialMediaYouTube);
        assertTrue(verified);

        vm.stopPrank();
    }

    function test_IsVerified_ReturnsFalseForInactive() public {
        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + 365 days;
        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaTwitter, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        verificationRegistry.revokeVerification(verificationId, "test");

        bool verified = verificationRegistry.isVerified(assetOwner1, AssetTypes.AssetType.SocialMediaTwitter);
        assertFalse(verified);

        vm.stopPrank();
    }

    function test_IsVerified_ReturnsFalseForExpired() public {
        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + 1 days;
        verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.Domain, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        // Fast forward past expiration
        vm.warp(block.timestamp + 2 days);

        bool verified = verificationRegistry.isVerified(assetOwner1, AssetTypes.AssetType.Domain);
        assertFalse(verified);

        vm.stopPrank();
    }

    function test_IsVerified_ReturnsFalseForNonExistent() public view {
        bool verified = verificationRegistry.isVerified(assetOwner1, AssetTypes.AssetType.Website);
        assertFalse(verified);
    }

    function test_GetVerification_ReturnsCorrectData() public {
        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + 365 days;
        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaFacebook, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        IVerificationRegistry.Verification memory verification = verificationRegistry.getVerification(verificationId);

        assertEq(verification.proofHash, PROOF_HASH_1);
        assertEq(verification.verifier, verifier1);
        assertEq(verification.verifiedAt, block.timestamp);
        assertEq(verification.expiresAt, expiresAt);
        assertEq(uint8(verification.assetType), uint8(AssetTypes.AssetType.SocialMediaFacebook));
        assertTrue(verification.isActive);
        assertEq(verification.verificationCount, 1);

        vm.stopPrank();
    }

    function test_GetVerification_RevertsIfNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IVerificationRegistry.VerificationNotFound.selector, 999));

        verificationRegistry.getVerification(999);
    }

    function test_GetOwnerVerifications_ReturnsAllVerifications() public {
        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + 365 days;

        uint256 id1 = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaYouTube, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        uint256 id2 = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaTwitter, PROOF_HASH_2, expiresAt, METADATA_URI_2
        );

        uint256[] memory verifications = verificationRegistry.getOwnerVerifications(assetOwner1);

        assertEq(verifications.length, 2);
        assertEq(verifications[0], id1);
        assertEq(verifications[1], id2);

        vm.stopPrank();
    }

    function test_GetOwnerVerifications_ReturnsEmptyForNewOwner() public view {
        uint256[] memory verifications = verificationRegistry.getOwnerVerifications(assetOwner2);
        assertEq(verifications.length, 0);
    }

    function test_GetVerificationByOwnerAndType_ReturnsCorrectId() public {
        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + 365 days;
        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.GameAccount, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        uint256 retrievedId =
            verificationRegistry.getVerificationByOwnerAndType(assetOwner1, AssetTypes.AssetType.GameAccount);

        assertEq(retrievedId, verificationId);

        vm.stopPrank();
    }

    function test_GetVerificationByOwnerAndType_ReturnsZeroIfNotFound() public view {
        uint256 retrievedId =
            verificationRegistry.getVerificationByOwnerAndType(assetOwner1, AssetTypes.AssetType.MobileApp);

        assertEq(retrievedId, 0);
    }

    function test_IsExpired_ReturnsFalseForNonExpired() public {
        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + 365 days;
        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaInstagram, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        bool expired = verificationRegistry.isExpired(verificationId);
        assertFalse(expired);

        vm.stopPrank();
    }

    function test_IsExpired_ReturnsTrueForExpired() public {
        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + 1 days;
        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaTikTok, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        // Fast forward past expiration
        vm.warp(block.timestamp + 2 days);

        bool expired = verificationRegistry.isExpired(verificationId);
        assertTrue(expired);

        vm.stopPrank();
    }

    function test_IsExpired_RevertsIfNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IVerificationRegistry.VerificationNotFound.selector, 999));

        verificationRegistry.isExpired(999);
    }

    // ============================================
    //          EDGE CASE TESTS
    // ============================================

    function test_MultipleOwnersIndependentVerifications() public {
        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + 365 days;

        uint256 id1 = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaYouTube, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        uint256 id2 = verificationRegistry.addVerification(
            assetOwner2, AssetTypes.AssetType.SocialMediaYouTube, PROOF_HASH_2, expiresAt, METADATA_URI_2
        );

        assertEq(id1, 1);
        assertEq(id2, 2);

        assertTrue(verificationRegistry.isVerified(assetOwner1, AssetTypes.AssetType.SocialMediaYouTube));
        assertTrue(verificationRegistry.isVerified(assetOwner2, AssetTypes.AssetType.SocialMediaYouTube));

        vm.stopPrank();
    }

    function test_RevokeAndAddNew_AllowsNewVerification() public {
        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + 365 days;

        // Add verification
        uint256 id1 = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.Domain, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        // Revoke it
        verificationRegistry.revokeVerification(id1, "test");

        // Add new verification for same asset type
        uint256 id2 = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.Domain, PROOF_HASH_2, expiresAt, METADATA_URI_2
        );

        assertEq(id2, 2);
        assertTrue(verificationRegistry.isVerified(assetOwner1, AssetTypes.AssetType.Domain));

        vm.stopPrank();
    }

    function test_VerificationCounter_IncrementsCorrectly() public {
        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + 365 days;

        assertEq(verificationRegistry.verificationCounter(), 0);

        verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaYouTube, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        assertEq(verificationRegistry.verificationCounter(), 1);

        verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaTwitter, PROOF_HASH_2, expiresAt, METADATA_URI_2
        );

        assertEq(verificationRegistry.verificationCounter(), 2);

        vm.stopPrank();
    }

    function test_RenewVerification_IncrementsCount() public {
        vm.startPrank(verifier1);

        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.Website, PROOF_HASH_1, block.timestamp + 365 days, METADATA_URI_1
        );

        IVerificationRegistry.Verification memory v1 = verificationRegistry.getVerification(verificationId);
        assertEq(v1.verificationCount, 1);

        verificationRegistry.renewVerification(verificationId, block.timestamp + 730 days, bytes32(0), "");

        IVerificationRegistry.Verification memory v2 = verificationRegistry.getVerification(verificationId);
        assertEq(v2.verificationCount, 2);

        vm.stopPrank();
    }

    // ============================================
    //          FUZZ TESTS
    // ============================================

    function testFuzz_AddVerification_WithDifferentAssetTypes(uint8 assetTypeNum) public {
        vm.assume(assetTypeNum <= uint8(AssetTypes.AssetType.Other));

        vm.startPrank(verifier1);

        AssetTypes.AssetType assetType = AssetTypes.AssetType(assetTypeNum);
        uint256 expiresAt = block.timestamp + 365 days;

        uint256 verificationId =
            verificationRegistry.addVerification(assetOwner1, assetType, PROOF_HASH_1, expiresAt, METADATA_URI_1);

        assertTrue(verificationRegistry.isVerified(assetOwner1, assetType));
        assertEq(verificationId, 1);

        vm.stopPrank();
    }

    function testFuzz_AddVerification_WithDifferentExpirations(uint256 timeOffset) public {
        vm.assume(timeOffset > 0 && timeOffset <= 3650 days); // Max 10 years

        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + timeOffset;

        uint256 verificationId = verificationRegistry.addVerification(
            assetOwner1, AssetTypes.AssetType.SocialMediaYouTube, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        IVerificationRegistry.Verification memory verification = verificationRegistry.getVerification(verificationId);

        assertEq(verification.expiresAt, expiresAt);

        vm.stopPrank();
    }

    function testFuzz_AddVerification_WithDifferentOwners(address owner) public {
        vm.assume(owner != address(0));

        vm.startPrank(verifier1);

        uint256 expiresAt = block.timestamp + 365 days;

        uint256 verificationId = verificationRegistry.addVerification(
            owner, AssetTypes.AssetType.SocialMediaTwitter, PROOF_HASH_1, expiresAt, METADATA_URI_1
        );

        assertTrue(verificationRegistry.isVerified(owner, AssetTypes.AssetType.SocialMediaTwitter));
        assertEq(verificationRegistry.verificationOwner(verificationId), owner);

        vm.stopPrank();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../src/escrow/EscrowManager.sol";
import "../src/access/RoleManager.sol";
import "../src/core/FeeDistributor.sol";
import "../src/libraries/AssetTypes.sol";

/**
 * @title EscrowManagerTest
 * @notice Test suite for EscrowManager contract
 * @dev Example tests showing basic functionality
 */
contract EscrowManagerTest is Test {
    EscrowManager public escrowManager;
    RoleManager public roleManager;
    FeeDistributor public feeDistributor;

    address public admin = address(1);
    address public buyer = address(2);
    address public seller = address(3);
    address public feeCollector = address(4);

    uint256 public constant PLATFORM_FEE_BPS = 250; // 2.5%

    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed buyer,
        address indexed seller,
        uint256 amount,
        AssetTypes.AssetType assetType,
        uint256 releaseTime,
        string metadataURI
    );

    function setUp() public {
        // Deploy contracts
        vm.startPrank(admin);

        roleManager = new RoleManager(admin);
        feeDistributor = new FeeDistributor(
            address(roleManager),
            feeCollector,
            PLATFORM_FEE_BPS
        );
        escrowManager = new EscrowManager(
            address(roleManager),
            address(feeDistributor),
            PLATFORM_FEE_BPS
        );

        vm.stopPrank();

        // Fund test accounts
        vm.deal(buyer, 100 ether);
        vm.deal(seller, 10 ether);
    }

    // ============================================
    // CREATION TESTS
    // ============================================

    function test_createEscrow_Success() public {
        vm.startPrank(buyer);

        uint256 amount = 1 ether;
        bytes32 assetHash = keccak256("youtube-channel-proof");

        vm.expectEmit(true, true, true, false);
        emit EscrowCreated(
            1,
            buyer,
            seller,
            amount,
            AssetTypes.AssetType.SocialMediaYouTube,
            0, // Will be calculated
            "ipfs://QmTest123"
        );

        uint256 escrowId = escrowManager.createEscrow{value: amount}(
            seller,
            AssetTypes.AssetType.SocialMediaYouTube,
            30 days,
            assetHash,
            "ipfs://QmTest123"
        );

        assertEq(escrowId, 1);
        assertEq(address(escrowManager).balance, amount);

        vm.stopPrank();
    }

    function test_createEscrow_RevertIf_InvalidSeller() public {
        vm.startPrank(buyer);

        vm.expectRevert();
        escrowManager.createEscrow{value: 1 ether}(
            address(0), // Invalid seller
            AssetTypes.AssetType.SocialMediaYouTube,
            30 days,
            keccak256("proof"),
            "ipfs://test"
        );

        vm.stopPrank();
    }

    function test_createEscrow_RevertIf_BuyerIsSeller() public {
        vm.startPrank(buyer);

        vm.expectRevert();
        escrowManager.createEscrow{value: 1 ether}(
            buyer, // Same as buyer
            AssetTypes.AssetType.SocialMediaYouTube,
            30 days,
            keccak256("proof"),
            "ipfs://test"
        );

        vm.stopPrank();
    }

    // ============================================
    // DELIVERY TESTS
    // ============================================

    function test_markAssetDelivered_Success() public {
        // Create escrow
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            seller,
            AssetTypes.AssetType.SocialMediaYouTube,
            30 days,
            keccak256("proof"),
            "ipfs://test"
        );

        // Seller marks delivered
        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        // Check state
        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);
        assertTrue(escrow.sellerDelivered);
        assertEq(uint8(escrow.state), uint8(AssetTypes.EscrowState.Delivered));
    }

    function test_markAssetDelivered_RevertIf_NotSeller() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            seller,
            AssetTypes.AssetType.SocialMediaYouTube,
            30 days,
            keccak256("proof"),
            "ipfs://test"
        );

        // Someone else tries to mark delivered
        vm.prank(address(999));
        vm.expectRevert();
        escrowManager.markAssetDelivered(escrowId);
    }

    // ============================================
    // CONFIRMATION & RELEASE TESTS
    // ============================================

    function test_confirmAssetReceived_Success() public {
        // Create escrow
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            seller,
            AssetTypes.AssetType.SocialMediaYouTube,
            30 days,
            keccak256("proof"),
            "ipfs://test"
        );

        // Seller delivers
        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        // Track seller balance before
        uint256 sellerBalanceBefore = seller.balance;

        // Buyer confirms
        vm.prank(buyer);
        escrowManager.confirmAssetReceived(escrowId);

        // Check seller received payment (minus fee)
        uint256 expectedNet = 1 ether - ((1 ether * PLATFORM_FEE_BPS) / 10000);
        assertEq(seller.balance, sellerBalanceBefore + expectedNet);

        // Check escrow state
        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);
        assertEq(uint8(escrow.state), uint8(AssetTypes.EscrowState.Completed));
    }

    function test_releaseEscrow_AfterDeadline() public {
        // Create escrow with short duration
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            seller,
            AssetTypes.AssetType.SocialMediaYouTube,
            7 days,
            keccak256("proof"),
            "ipfs://test"
        );

        // Seller delivers
        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        // Fast forward past deadline
        vm.warp(block.timestamp + 8 days);

        // Anyone can release
        uint256 sellerBalanceBefore = seller.balance;
        escrowManager.releaseEscrow(escrowId);

        // Verify release
        uint256 expectedNet = 1 ether - ((1 ether * PLATFORM_FEE_BPS) / 10000);
        assertEq(seller.balance, sellerBalanceBefore + expectedNet);
    }

    // ============================================
    // CANCELLATION TESTS
    // ============================================

    function test_cancelEscrow_BeforeDelivery() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            seller,
            AssetTypes.AssetType.SocialMediaYouTube,
            30 days,
            keccak256("proof"),
            "ipfs://test"
        );

        uint256 buyerBalanceBefore = buyer.balance;

        // Buyer cancels
        vm.prank(buyer);
        escrowManager.cancelEscrow(escrowId);

        // Buyer gets full refund
        assertEq(buyer.balance, buyerBalanceBefore + 1 ether);
    }

    // ============================================
    // DISPUTE TESTS
    // ============================================

    function test_openDispute_Success() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            seller,
            AssetTypes.AssetType.SocialMediaYouTube,
            30 days,
            keccak256("proof"),
            "ipfs://test"
        );

        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        // Buyer opens dispute
        vm.prank(buyer);
        escrowManager.openDispute(escrowId, "Account not transferred");

        // Check state
        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);
        assertEq(uint8(escrow.state), uint8(AssetTypes.EscrowState.Disputed));
    }

    function test_resolveDispute_AdminOnly() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            seller,
            AssetTypes.AssetType.SocialMediaYouTube,
            30 days,
            keccak256("proof"),
            "ipfs://test"
        );

        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        vm.prank(buyer);
        escrowManager.openDispute(escrowId, "Issue");

        // Grant arbitrator role to admin
        vm.prank(admin);
        roleManager.scheduleRoleGrant(roleManager.ARBITRATOR_ROLE(), admin);

        // Admin resolves in favor of buyer (refund)
        vm.prank(admin);
        escrowManager.resolveDispute(escrowId, buyer, 1 ether);

        // Buyer should receive refund
        // Note: In actual test, would verify balance change
    }

    // ============================================
    // VIEW FUNCTION TESTS
    // ============================================

    function test_getBuyerEscrows() public {
        vm.startPrank(buyer);

        escrowManager.createEscrow{value: 1 ether}(
            seller,
            AssetTypes.AssetType.SocialMediaYouTube,
            30 days,
            keccak256("proof1"),
            "ipfs://test1"
        );

        escrowManager.createEscrow{value: 2 ether}(
            seller,
            AssetTypes.AssetType.Website,
            60 days,
            keccak256("proof2"),
            "ipfs://test2"
        );

        vm.stopPrank();

        uint256[] memory buyerEscrows = escrowManager.getBuyerEscrows(buyer);
        assertEq(buyerEscrows.length, 2);
        assertEq(buyerEscrows[0], 1);
        assertEq(buyerEscrows[1], 2);
    }
}

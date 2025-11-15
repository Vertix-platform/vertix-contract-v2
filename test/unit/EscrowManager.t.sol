// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {EscrowManager} from "../../src/escrow/EscrowManager.sol";
import {RoleManager} from "../../src/access/RoleManager.sol";
import {FeeDistributor} from "../../src/core/FeeDistributor.sol";
import {IEscrowManager} from "../../src/interfaces/IEscrowManager.sol";
import {AssetTypes} from "../../src/libraries/AssetTypes.sol";
import {Errors} from "../../src/libraries/Errors.sol";

contract EscrowManagerTest is Test {
    EscrowManager public escrowManager;
    RoleManager public roleManager;
    FeeDistributor public feeDistributor;

    address public admin;
    address public feeManager;
    address public arbitrator;
    address public feeCollector;
    address public buyer;
    address public seller;
    address public marketplace;

    uint256 public constant PLATFORM_FEE_BPS = 250; // 2.5%
    uint256 public constant ESCROW_DURATION = 7 days;
    bytes32 public constant ASSET_HASH = keccak256("test-asset-hash");
    string public constant METADATA_URI = "ipfs://QmTest123";

    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed buyer,
        address indexed seller,
        uint256 amount,
        AssetTypes.AssetType assetType,
        uint256 releaseTime,
        string metadataURI
    );
    event AssetDelivered(uint256 indexed escrowId, address indexed seller, uint256 deliveryTimestamp);
    event AssetReceiptConfirmed(uint256 indexed escrowId, address indexed buyer, uint256 confirmationTimestamp);
    event EscrowReleased(
        uint256 indexed escrowId, address indexed seller, uint256 amount, uint256 platformFee, uint256 sellerNet
    );
    event DisputeOpened(uint256 indexed escrowId, address indexed disputedBy, string reason, uint256 timestamp);
    event DisputeResolved(uint256 indexed escrowId, address indexed winner, uint256 amount, address resolver);
    event EscrowCancelled(
        uint256 indexed escrowId, address indexed buyer, uint256 refundAmount, uint256 sellerCompensation
    );
    event PlatformFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps, address updatedBy);
    event MarketplaceAuthorized(address indexed marketplace, address indexed authorizedBy);
    event MarketplaceDeauthorized(address indexed marketplace, address indexed deauthorizedBy);

    function setUp() public {
        admin = makeAddr("admin");
        feeManager = makeAddr("feeManager");
        arbitrator = makeAddr("arbitrator");
        feeCollector = makeAddr("feeCollector");
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        marketplace = makeAddr("marketplace");

        roleManager = new RoleManager(admin);

        vm.startPrank(admin);
        roleManager.scheduleRoleGrant(roleManager.FEE_MANAGER_ROLE(), feeManager);
        roleManager.scheduleRoleGrant(roleManager.ARBITRATOR_ROLE(), arbitrator);
        vm.stopPrank();

        feeDistributor = new FeeDistributor(address(roleManager), feeCollector, 250);

        escrowManager = new EscrowManager(address(roleManager), address(feeDistributor), PLATFORM_FEE_BPS);

        vm.deal(buyer, 100 ether);
        vm.deal(seller, 1 ether);
    }

    // ============================================
    //          CONSTRUCTOR TESTS
    // ============================================

    function test_Constructor_SetsStateCorrectly() public view {
        assertEq(address(escrowManager.roleManager()), address(roleManager));
        assertEq(address(escrowManager.feeDistributor()), address(feeDistributor));
        assertEq(escrowManager.platformFeeBps(), PLATFORM_FEE_BPS);
        assertEq(escrowManager.escrowCounter(), 0);
    }

    function test_Constructor_RevertsOnZeroFeeDistributor() public {
        vm.expectRevert(Errors.InvalidFeeDistributor.selector);
        new EscrowManager(address(roleManager), address(0), PLATFORM_FEE_BPS);
    }

    function test_Constructor_RevertsOnInvalidFeeBps() public {
        vm.expectRevert();
        new EscrowManager(address(roleManager), address(feeDistributor), 10_001); // > MAX_FEE_BPS
    }

    function test_Constructor_RevertsOnZeroRoleManager() public {
        vm.expectRevert(Errors.InvalidRoleManager.selector);
        new EscrowManager(address(0), address(feeDistributor), PLATFORM_FEE_BPS);
    }

    // ============================================
    //          CREATE ESCROW TESTS
    // ============================================

    function test_CreateEscrow_Success() public {
        uint256 amount = 1 ether;

        vm.expectEmit(true, true, true, true);
        emit EscrowCreated(
            1,
            buyer,
            seller,
            amount,
            AssetTypes.AssetType.SocialMediaInstagram,
            block.timestamp + ESCROW_DURATION,
            METADATA_URI
        );

        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: amount}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        assertEq(escrowId, 1);
        assertEq(escrowManager.escrowCounter(), 1);

        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);
        assertEq(escrow.buyer, buyer);
        assertEq(escrow.seller, seller);
        assertEq(escrow.amount, amount);
        assertEq(uint8(escrow.assetType), uint8(AssetTypes.AssetType.SocialMediaInstagram));
        assertEq(uint8(escrow.state), uint8(AssetTypes.EscrowState.Active));
        assertEq(escrow.assetHash, ASSET_HASH);
        assertFalse(escrow.buyerConfirmed);
        assertFalse(escrow.sellerDelivered);
    }

    function test_CreateEscrow_IncrementsCounter() public {
        vm.startPrank(buyer);
        escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );
        escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaTwitter, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );
        vm.stopPrank();

        assertEq(escrowManager.escrowCounter(), 2);
    }

    function test_CreateEscrow_TracksMultipleEscrows() public {
        vm.startPrank(buyer);
        escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );
        escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaTwitter, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );
        vm.stopPrank();

        uint256[] memory buyerEscrows = escrowManager.getBuyerEscrows(buyer);
        uint256[] memory sellerEscrows = escrowManager.getSellerEscrows(seller);

        assertEq(buyerEscrows.length, 2);
        assertEq(sellerEscrows.length, 2);
        assertEq(buyerEscrows[0], 1);
        assertEq(buyerEscrows[1], 2);
    }

    function test_CreateEscrow_RevertsOnBuyerEqualsSeller() public {
        vm.prank(buyer);
        vm.expectRevert(Errors.BuyerCannotBeSeller.selector);
        escrowManager.createEscrow{value: 1 ether}(
            buyer, buyer, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );
    }

    function test_CreateEscrow_RevertsOnZeroBuyer() public {
        vm.prank(buyer);
        vm.expectRevert();
        escrowManager.createEscrow{value: 1 ether}(
            address(0), seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );
    }

    function test_CreateEscrow_RevertsOnZeroSeller() public {
        vm.prank(buyer);
        vm.expectRevert();
        escrowManager.createEscrow{value: 1 ether}(
            buyer, address(0), AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );
    }

    function test_CreateEscrow_RevertsOnZeroAmount() public {
        vm.prank(buyer);
        vm.expectRevert();
        escrowManager.createEscrow{value: 0}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );
    }

    function test_CreateEscrow_RevertsOnInsufficientAmount() public {
        vm.prank(buyer);
        vm.expectRevert();
        escrowManager.createEscrow{value: 0.0001 ether}( // Less than 0.001 ether minimum
        buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI);
    }

    function test_CreateEscrow_RevertsOnDurationTooShort() public {
        vm.prank(buyer);
        vm.expectRevert();
        escrowManager.createEscrow{value: 1 ether}(
            buyer,
            seller,
            AssetTypes.AssetType.SocialMediaInstagram,
            1 hours, // Too short
            ASSET_HASH,
            METADATA_URI
        );
    }

    function test_CreateEscrow_RevertsOnDurationTooLong() public {
        vm.prank(buyer);
        vm.expectRevert();
        escrowManager.createEscrow{value: 1 ether}(
            buyer,
            seller,
            AssetTypes.AssetType.SocialMediaInstagram,
            365 days + 1, // Too long
            ASSET_HASH,
            METADATA_URI
        );
    }

    function test_CreateEscrow_RevertsOnEmptyHash() public {
        vm.prank(buyer);
        vm.expectRevert(Errors.InvalidHash.selector);
        escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, bytes32(0), METADATA_URI
        );
    }

    function test_CreateEscrow_RevertsOnEmptyMetadata() public {
        vm.prank(buyer);
        vm.expectRevert();
        escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, ""
        );
    }

    function test_CreateEscrow_RevertsOnNFTAssetType() public {
        vm.prank(buyer);
        vm.expectRevert(Errors.AssetTypeDoesNotRequireEscrow.selector);
        escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.NFT721, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );
    }

    function test_CreateEscrow_AuthorizedMarketplaceCanCreate() public {
        // Authorize marketplace
        vm.prank(admin);
        escrowManager.addAuthorizedMarketplace(marketplace);

        // Fund marketplace
        vm.deal(marketplace, 10 ether);

        // Marketplace creates escrow on behalf of buyer
        vm.prank(marketplace);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        assertEq(escrowId, 1);
        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);
        assertEq(escrow.buyer, buyer);
    }

    function test_CreateEscrow_RevertsOnUnauthorizedMarketplace() public {
        // Fund marketplace
        vm.deal(marketplace, 10 ether);

        vm.prank(marketplace);
        vm.expectRevert();
        escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );
    }

    function testFuzz_CreateEscrow_VariousAmounts(uint256 amount) public {
        amount = bound(amount, 0.001 ether, 10 ether);

        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: amount}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);
        assertEq(escrow.amount, amount);
    }

    function testFuzz_CreateEscrow_VariousDurations(uint256 duration) public {
        duration = bound(duration, AssetTypes.MIN_ESCROW_DURATION, AssetTypes.MAX_ESCROW_DURATION);

        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, duration, ASSET_HASH, METADATA_URI
        );

        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);
        assertEq(escrow.releaseTime, block.timestamp + duration);
    }

    // ============================================
    //       MARK ASSET DELIVERED TESTS
    // ============================================

    function test_MarkAssetDelivered_Success() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.expectEmit(true, true, true, true);
        emit AssetDelivered(escrowId, seller, block.timestamp);

        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);
        assertTrue(escrow.sellerDelivered);
        assertEq(uint8(escrow.state), uint8(AssetTypes.EscrowState.Delivered));
    }

    function test_MarkAssetDelivered_RevertsOnInvalidEscrowId() public {
        vm.prank(seller);
        vm.expectRevert();
        escrowManager.markAssetDelivered(999);
    }

    function test_MarkAssetDelivered_RevertsOnNotSeller() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(buyer);
        vm.expectRevert();
        escrowManager.markAssetDelivered(escrowId);
    }

    function test_MarkAssetDelivered_RevertsOnAlreadyDelivered() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        vm.prank(seller);
        vm.expectRevert();
        escrowManager.markAssetDelivered(escrowId);
    }

    function test_MarkAssetDelivered_RevertsWhenPaused() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(admin);
        escrowManager.pause();

        vm.prank(seller);
        vm.expectRevert();
        escrowManager.markAssetDelivered(escrowId);
    }

    // ============================================
    //       CONFIRM ASSET RECEIVED TESTS
    // ============================================

    function test_ConfirmAssetReceived_Success() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        uint256 sellerBalanceBefore = seller.balance;

        vm.expectEmit(true, true, true, true);
        emit AssetReceiptConfirmed(escrowId, buyer, block.timestamp);

        vm.prank(buyer);
        escrowManager.confirmAssetReceived(escrowId);

        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);
        assertTrue(escrow.buyerConfirmed);
        assertEq(uint8(escrow.state), uint8(AssetTypes.EscrowState.Completed));

        // Check seller received payment (minus platform fee)
        uint256 platformFee = (1 ether * PLATFORM_FEE_BPS) / 10_000;
        uint256 expectedSellerNet = 1 ether - platformFee;
        assertEq(seller.balance, sellerBalanceBefore + expectedSellerNet);
    }

    function test_ConfirmAssetReceived_RevertsOnNotBuyer() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        vm.prank(seller);
        vm.expectRevert();
        escrowManager.confirmAssetReceived(escrowId);
    }

    function test_ConfirmAssetReceived_RevertsOnNotDelivered() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(buyer);
        vm.expectRevert();
        escrowManager.confirmAssetReceived(escrowId);
    }

    function test_ConfirmAssetReceived_RevertsOnAlreadyConfirmed() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        vm.prank(buyer);
        escrowManager.confirmAssetReceived(escrowId);

        vm.prank(buyer);
        vm.expectRevert();
        escrowManager.confirmAssetReceived(escrowId);
    }

    // ============================================
    //          RELEASE ESCROW TESTS
    // ============================================

    function test_ReleaseEscrow_AfterDeadline() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        // Fast forward past release time
        vm.warp(block.timestamp + ESCROW_DURATION + 1);

        uint256 sellerBalanceBefore = seller.balance;

        vm.expectEmit(true, true, true, true);
        emit EscrowReleased(escrowId, seller, 1 ether, 0.025 ether, 0.975 ether);

        escrowManager.releaseEscrow(escrowId);

        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);
        assertEq(uint8(escrow.state), uint8(AssetTypes.EscrowState.Completed));

        uint256 expectedSellerNet = 1 ether - (1 ether * PLATFORM_FEE_BPS) / 10_000;
        assertEq(seller.balance, sellerBalanceBefore + expectedSellerNet);
    }

    function test_ReleaseEscrow_RevertsBeforeDeadline() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        vm.expectRevert();
        escrowManager.releaseEscrow(escrowId);
    }

    function test_ReleaseEscrow_RevertsOnNotDelivered() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.warp(block.timestamp + ESCROW_DURATION + 1);

        vm.expectRevert();
        escrowManager.releaseEscrow(escrowId);
    }

    function test_ReleaseEscrow_CanBeCalledByAnyone() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        vm.warp(block.timestamp + ESCROW_DURATION + 1);

        address randomUser = makeAddr("randomUser");
        vm.prank(randomUser);
        escrowManager.releaseEscrow(escrowId);

        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);
        assertEq(uint8(escrow.state), uint8(AssetTypes.EscrowState.Completed));
    }

    // ============================================
    //             DISPUTE TESTS
    // ============================================

    function test_OpenDispute_ByBuyer() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        vm.expectEmit(true, true, true, true);
        emit DisputeOpened(escrowId, buyer, "Account not as described", block.timestamp);

        vm.prank(buyer);
        escrowManager.openDispute(escrowId, "Account not as described");

        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);
        assertEq(uint8(escrow.state), uint8(AssetTypes.EscrowState.Disputed));
    }

    function test_OpenDispute_BySeller() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        vm.prank(seller);
        escrowManager.openDispute(escrowId, "Buyer not cooperating");

        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);
        assertEq(uint8(escrow.state), uint8(AssetTypes.EscrowState.Disputed));
    }

    function test_OpenDispute_RevertsOnUnauthorized() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        address randomUser = makeAddr("randomUser");
        vm.prank(randomUser);
        vm.expectRevert();
        escrowManager.openDispute(escrowId, "Some reason");
    }

    function test_OpenDispute_RevertsAfterDeadline() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        // Fast forward past dispute deadline (release time + 7 days)
        vm.warp(block.timestamp + ESCROW_DURATION + 8 days);

        vm.prank(buyer);
        vm.expectRevert();
        escrowManager.openDispute(escrowId, "Too late");
    }

    function test_ResolveDispute_TowardsBuyer() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        vm.prank(buyer);
        escrowManager.openDispute(escrowId, "Issue");

        uint256 buyerBalanceBefore = buyer.balance;

        vm.expectEmit(true, true, true, true);
        emit DisputeResolved(escrowId, buyer, 1 ether, arbitrator);

        vm.prank(arbitrator);
        escrowManager.resolveDispute(escrowId, buyer, 1 ether);

        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);
        assertEq(uint8(escrow.state), uint8(AssetTypes.EscrowState.Refunded));
        assertEq(buyer.balance, buyerBalanceBefore + 1 ether);
    }

    function test_ResolveDispute_TowardsSeller() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        vm.prank(buyer);
        escrowManager.openDispute(escrowId, "Issue");

        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(arbitrator);
        escrowManager.resolveDispute(escrowId, seller, 1 ether);

        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);
        assertEq(uint8(escrow.state), uint8(AssetTypes.EscrowState.Completed));
        assertEq(seller.balance, sellerBalanceBefore + 1 ether);
    }

    function test_ResolveDispute_PartialSplit() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        vm.prank(buyer);
        escrowManager.openDispute(escrowId, "Issue");

        uint256 buyerBalanceBefore = buyer.balance;
        uint256 sellerBalanceBefore = seller.balance;

        // Award 60% to buyer, 40% to seller
        vm.prank(arbitrator);
        escrowManager.resolveDispute(escrowId, buyer, 0.6 ether);

        assertEq(buyer.balance, buyerBalanceBefore + 0.6 ether);
        assertEq(seller.balance, sellerBalanceBefore + 0.4 ether);
    }

    function test_ResolveDispute_RevertsOnNotArbitrator() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(buyer);
        escrowManager.openDispute(escrowId, "Issue");

        vm.prank(buyer);
        vm.expectRevert();
        escrowManager.resolveDispute(escrowId, buyer, 1 ether);
    }

    function test_ResolveDispute_RevertsOnInvalidWinner() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(buyer);
        escrowManager.openDispute(escrowId, "Issue");

        address randomUser = makeAddr("randomUser");
        vm.prank(arbitrator);
        vm.expectRevert();
        escrowManager.resolveDispute(escrowId, randomUser, 1 ether);
    }

    function test_ResolveDispute_RevertsOnExcessiveAmount() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(buyer);
        escrowManager.openDispute(escrowId, "Issue");

        vm.prank(arbitrator);
        vm.expectRevert();
        escrowManager.resolveDispute(escrowId, buyer, 2 ether);
    }

    // ============================================
    //          CANCEL ESCROW TESTS
    // ============================================

    function test_CancelEscrow_BeforeDelivery() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        uint256 buyerBalanceBefore = buyer.balance;

        vm.expectEmit(true, true, true, true);
        emit EscrowCancelled(escrowId, buyer, 1 ether, 0);

        vm.prank(buyer);
        escrowManager.cancelEscrow(escrowId);

        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);
        assertEq(uint8(escrow.state), uint8(AssetTypes.EscrowState.Cancelled));
        assertEq(buyer.balance, buyerBalanceBefore + 1 ether);
    }

    function test_CancelEscrow_RevertsOnNotBuyer() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(seller);
        vm.expectRevert();
        escrowManager.cancelEscrow(escrowId);
    }

    function test_CancelEscrow_RevertsAfterDelivery() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        vm.prank(buyer);
        vm.expectRevert();
        escrowManager.cancelEscrow(escrowId);
    }

    // ============================================
    //       AUTHORIZATION TESTS
    // ============================================

    function test_AddAuthorizedMarketplace_Success() public {
        vm.expectEmit(true, true, true, true);
        emit MarketplaceAuthorized(marketplace, admin);

        vm.prank(admin);
        escrowManager.addAuthorizedMarketplace(marketplace);

        assertTrue(escrowManager.isAuthorizedMarketplace(marketplace));
    }

    function test_AddAuthorizedMarketplace_RevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(Errors.ZeroAddress.selector);
        escrowManager.addAuthorizedMarketplace(address(0));
    }

    function test_AddAuthorizedMarketplace_RevertsOnAlreadyAuthorized() public {
        vm.prank(admin);
        escrowManager.addAuthorizedMarketplace(marketplace);

        vm.prank(admin);
        vm.expectRevert();
        escrowManager.addAuthorizedMarketplace(marketplace);
    }

    function test_AddAuthorizedMarketplace_RevertsOnNotAdmin() public {
        vm.prank(buyer);
        vm.expectRevert();
        escrowManager.addAuthorizedMarketplace(marketplace);
    }

    function test_RemoveAuthorizedMarketplace_Success() public {
        vm.prank(admin);
        escrowManager.addAuthorizedMarketplace(marketplace);

        vm.expectEmit(true, true, true, true);
        emit MarketplaceDeauthorized(marketplace, admin);

        vm.prank(admin);
        escrowManager.removeAuthorizedMarketplace(marketplace);

        assertFalse(escrowManager.isAuthorizedMarketplace(marketplace));
    }

    function test_RemoveAuthorizedMarketplace_RevertsOnNotAuthorized() public {
        vm.prank(admin);
        vm.expectRevert();
        escrowManager.removeAuthorizedMarketplace(marketplace);
    }

    function test_RemoveAuthorizedMarketplace_RevertsOnNotAdmin() public {
        vm.prank(admin);
        escrowManager.addAuthorizedMarketplace(marketplace);

        vm.prank(buyer);
        vm.expectRevert();
        escrowManager.removeAuthorizedMarketplace(marketplace);
    }

    // ============================================
    //          PLATFORM FEE TESTS
    // ============================================

    function test_UpdatePlatformFee_Success() public {
        uint256 newFee = 500; // 5%

        vm.expectEmit(true, true, true, true);
        emit PlatformFeeUpdated(PLATFORM_FEE_BPS, newFee, feeManager);

        vm.prank(feeManager);
        escrowManager.updatePlatformFee(newFee);

        assertEq(escrowManager.platformFeeBps(), newFee);
    }

    function test_UpdatePlatformFee_RevertsOnNotFeeManager() public {
        vm.prank(buyer);
        vm.expectRevert();
        escrowManager.updatePlatformFee(500);
    }

    function test_UpdatePlatformFee_RevertsOnExcessiveFee() public {
        vm.prank(feeManager);
        vm.expectRevert();
        escrowManager.updatePlatformFee(10_001); // > MAX_FEE_BPS
    }

    // ============================================
    //          PAUSE/UNPAUSE TESTS
    // ============================================

    function test_Pause_Success() public {
        vm.prank(admin);
        escrowManager.pause();

        vm.prank(buyer);
        vm.expectRevert();
        escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );
    }

    function test_Unpause_Success() public {
        vm.prank(admin);
        escrowManager.pause();

        vm.prank(admin);
        escrowManager.unpause();

        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        assertEq(escrowId, 1);
    }

    // ============================================
    //          VIEW FUNCTION TESTS
    // ============================================

    function test_GetEscrow_ReturnsCorrectData() public {
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);

        assertEq(escrow.buyer, buyer);
        assertEq(escrow.seller, seller);
        assertEq(escrow.amount, 1 ether);
        assertEq(uint8(escrow.assetType), uint8(AssetTypes.AssetType.SocialMediaInstagram));
        assertEq(uint8(escrow.state), uint8(AssetTypes.EscrowState.Active));
    }

    function test_GetEscrow_RevertsOnInvalidId() public {
        vm.expectRevert();
        escrowManager.getEscrow(999);
    }

    function test_GetBuyerEscrows_ReturnsCorrectArray() public {
        vm.startPrank(buyer);
        escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );
        escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaTwitter, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );
        vm.stopPrank();

        uint256[] memory buyerEscrows = escrowManager.getBuyerEscrows(buyer);

        assertEq(buyerEscrows.length, 2);
        assertEq(buyerEscrows[0], 1);
        assertEq(buyerEscrows[1], 2);
    }

    function test_GetSellerEscrows_ReturnsCorrectArray() public {
        address buyer2 = makeAddr("buyer2");
        vm.deal(buyer2, 10 ether);

        vm.prank(buyer);
        escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        vm.prank(buyer2);
        escrowManager.createEscrow{value: 1 ether}(
            buyer2, seller, AssetTypes.AssetType.SocialMediaTwitter, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        uint256[] memory sellerEscrows = escrowManager.getSellerEscrows(seller);

        assertEq(sellerEscrows.length, 2);
        assertEq(sellerEscrows[0], 1);
        assertEq(sellerEscrows[1], 2);
    }

    function test_GetBuyerEscrows_ReturnsEmptyForNewUser() public {
        address newBuyer = makeAddr("newBuyer");
        uint256[] memory escrows = escrowManager.getBuyerEscrows(newBuyer);
        assertEq(escrows.length, 0);
    }

    function test_GetSellerEscrows_ReturnsEmptyForNewUser() public {
        address newSeller = makeAddr("newSeller");
        uint256[] memory escrows = escrowManager.getSellerEscrows(newSeller);
        assertEq(escrows.length, 0);
    }

    // ============================================
    //       COMPLETE FLOW TESTS
    // ============================================

    function test_CompleteFlow_HappyPath() public {
        // 1. Buyer creates escrow
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        // 2. Seller delivers asset
        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        // 3. Buyer confirms receipt
        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(buyer);
        escrowManager.confirmAssetReceived(escrowId);

        // 4. Verify completion
        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);
        assertEq(uint8(escrow.state), uint8(AssetTypes.EscrowState.Completed));

        uint256 expectedSellerNet = 1 ether - (1 ether * PLATFORM_FEE_BPS) / 10_000;
        assertEq(seller.balance, sellerBalanceBefore + expectedSellerNet);
    }

    function test_CompleteFlow_AutoRelease() public {
        // 1. Buyer creates escrow
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        // 2. Seller delivers asset
        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        // 3. Time passes, buyer doesn't respond
        vm.warp(block.timestamp + ESCROW_DURATION + 1);

        // 4. Anyone can trigger release
        uint256 sellerBalanceBefore = seller.balance;

        escrowManager.releaseEscrow(escrowId);

        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);
        assertEq(uint8(escrow.state), uint8(AssetTypes.EscrowState.Completed));

        uint256 expectedSellerNet = 1 ether - (1 ether * PLATFORM_FEE_BPS) / 10_000;
        assertEq(seller.balance, sellerBalanceBefore + expectedSellerNet);
    }

    function test_CompleteFlow_DisputeResolution() public {
        // 1. Buyer creates escrow
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        // 2. Seller delivers asset
        vm.prank(seller);
        escrowManager.markAssetDelivered(escrowId);

        // 3. Buyer opens dispute
        vm.prank(buyer);
        escrowManager.openDispute(escrowId, "Account credentials don't work");

        // 4. Arbitrator resolves in favor of buyer
        uint256 buyerBalanceBefore = buyer.balance;

        vm.prank(arbitrator);
        escrowManager.resolveDispute(escrowId, buyer, 1 ether);

        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);
        assertEq(uint8(escrow.state), uint8(AssetTypes.EscrowState.Refunded));
        assertEq(buyer.balance, buyerBalanceBefore + 1 ether);
    }

    function test_CompleteFlow_EarlyCancellation() public {
        // 1. Buyer creates escrow
        vm.prank(buyer);
        uint256 escrowId = escrowManager.createEscrow{value: 1 ether}(
            buyer, seller, AssetTypes.AssetType.SocialMediaInstagram, ESCROW_DURATION, ASSET_HASH, METADATA_URI
        );

        // 2. Buyer changes mind before seller delivers
        uint256 buyerBalanceBefore = buyer.balance;

        vm.prank(buyer);
        escrowManager.cancelEscrow(escrowId);

        IEscrowManager.Escrow memory escrow = escrowManager.getEscrow(escrowId);
        assertEq(uint8(escrow.state), uint8(AssetTypes.EscrowState.Cancelled));
        assertEq(buyer.balance, buyerBalanceBefore + 1 ether);
    }
}

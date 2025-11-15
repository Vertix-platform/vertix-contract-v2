// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {OfferManager} from "../../src/core/OfferManager.sol";
import {FeeDistributor} from "../../src/core/FeeDistributor.sol";
import {RoleManager} from "../../src/access/RoleManager.sol";
import {IOfferManager} from "../../src/interfaces/IOfferManager.sol";
import {AssetTypes} from "../../src/libraries/AssetTypes.sol";
import {PercentageMath} from "../../src/libraries/PercentageMath.sol";
import {Errors} from "../../src/libraries/Errors.sol";

// Mock contracts
import {MockMarketplace} from "../mocks/MockMarketplace.sol";
import {MockEscrowManager} from "../mocks/MockEscrowManager.sol";
import {MockERC721} from "../mocks/MockERC721.sol";
import {MockERC1155} from "../mocks/MockERC1155.sol";

contract OfferManagerTest is Test {
    OfferManager public offerManager;
    RoleManager public roleManager;
    FeeDistributor public feeDistributor;
    MockMarketplace public marketplace;
    MockEscrowManager public escrowManager;
    MockERC721 public mockNFT721;
    MockERC1155 public mockNFT1155;

    address public admin;
    address public feeManager;
    address public feeCollector;
    address public seller;
    address public buyer;
    address public buyer2;

    uint256 public constant PLATFORM_FEE_BPS = 250; // 2.5%

    // Events
    event OfferMade(
        uint256 indexed offerId,
        uint256 indexed listingId,
        address indexed buyer,
        address seller,
        uint256 amount,
        uint256 expiresAt,
        AssetTypes.AssetType assetType
    );
    event OfferAccepted(
        uint256 indexed offerId, uint256 indexed listingId, address indexed seller, address buyer, uint256 amount
    );
    event OfferRejected(
        uint256 indexed offerId, uint256 indexed listingId, address indexed seller, address buyer, string reason
    );
    event OfferCancelled(
        uint256 indexed offerId, uint256 indexed listingId, address indexed buyer, uint256 refundAmount
    );
    event OfferExpired(uint256 indexed offerId, uint256 indexed listingId, address indexed buyer);
    event OfferRefunded(uint256 indexed offerId, address indexed buyer, uint256 amount);
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);

    function setUp() public {
        admin = makeAddr("admin");
        feeManager = makeAddr("feeManager");
        feeCollector = makeAddr("feeCollector");
        seller = makeAddr("seller");
        buyer = makeAddr("buyer");
        buyer2 = makeAddr("buyer2");

        // Deploy core contracts
        roleManager = new RoleManager(admin);

        // Grant FEE_MANAGER_ROLE
        vm.startPrank(admin);
        roleManager.scheduleRoleGrant(roleManager.FEE_MANAGER_ROLE(), feeManager);
        vm.stopPrank();

        feeDistributor = new FeeDistributor(address(roleManager), feeCollector, PLATFORM_FEE_BPS);

        // Deploy mock contracts
        marketplace = new MockMarketplace();
        escrowManager = new MockEscrowManager();
        mockNFT721 = new MockERC721();
        mockNFT1155 = new MockERC1155();

        // Deploy OfferManager
        offerManager = new OfferManager(
            address(roleManager),
            address(feeDistributor),
            address(marketplace),
            address(escrowManager),
            PLATFORM_FEE_BPS
        );

        // Fund test accounts
        vm.deal(buyer, 100 ether);
        vm.deal(buyer2, 100 ether);
        vm.deal(seller, 1 ether);
    }

    // ============================================
    //          CONSTRUCTOR TESTS
    // ============================================

    function test_Constructor_SetsStateCorrectly() public view {
        assertEq(address(offerManager.roleManager()), address(roleManager));
        assertEq(address(offerManager.feeDistributor()), address(feeDistributor));
        assertEq(address(offerManager.marketplace()), address(marketplace));
        assertEq(address(offerManager.escrowManager()), address(escrowManager));
        assertEq(offerManager.platformFeeBps(), PLATFORM_FEE_BPS);
        assertEq(offerManager.offerCounter(), 0);
    }

    function test_Constructor_EmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit PlatformFeeUpdated(0, PLATFORM_FEE_BPS);

        new OfferManager(
            address(roleManager),
            address(feeDistributor),
            address(marketplace),
            address(escrowManager),
            PLATFORM_FEE_BPS
        );
    }

    function test_Constructor_RevertsOnZeroRoleManager() public {
        vm.expectRevert(Errors.InvalidRoleManager.selector);
        new OfferManager(
            address(0), address(feeDistributor), address(marketplace), address(escrowManager), PLATFORM_FEE_BPS
        );
    }

    function test_Constructor_RevertsOnZeroFeeDistributor() public {
        vm.expectRevert(Errors.InvalidFeeDistributor.selector);
        new OfferManager(
            address(roleManager), address(0), address(marketplace), address(escrowManager), PLATFORM_FEE_BPS
        );
    }

    function test_Constructor_RevertsOnZeroMarketplace() public {
        vm.expectRevert(Errors.InvalidMarketplace.selector);
        new OfferManager(
            address(roleManager), address(feeDistributor), address(0), address(escrowManager), PLATFORM_FEE_BPS
        );
    }

    function test_Constructor_RevertsOnZeroEscrowManager() public {
        vm.expectRevert(Errors.InvalidEscrowManager.selector);
        new OfferManager(
            address(roleManager), address(feeDistributor), address(marketplace), address(0), PLATFORM_FEE_BPS
        );
    }

    function test_Constructor_RevertsOnInvalidFeeBps() public {
        vm.expectRevert(abi.encodeWithSelector(PercentageMath.PercentageTooHigh.selector, 2000, AssetTypes.MAX_FEE_BPS));
        new OfferManager(
            address(roleManager), address(feeDistributor), address(marketplace), address(escrowManager), 2000
        );
    }

    // ============================================
    //          MAKE OFFER TESTS
    // ============================================

    function test_MakeOffer_OffChainAsset_Success() public {
        // Create a listing
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        uint256 offerAmount = 0.8 ether;
        uint256 duration = 7 days;
        uint256 expectedExpiry = block.timestamp + duration;

        vm.expectEmit(true, true, true, true);
        emit OfferMade(
            1, listingId, buyer, seller, offerAmount, expectedExpiry, AssetTypes.AssetType.SocialMediaYouTube
        );

        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: offerAmount}(listingId, duration);

        assertEq(offerId, 1);
        assertEq(offerManager.offerCounter(), 1);

        IOfferManager.Offer memory offer = offerManager.getOffer(offerId);
        assertEq(offer.buyer, buyer);
        assertEq(offer.amount, offerAmount);
        assertEq(offer.seller, seller);
        assertEq(offer.listingId, listingId);
        assertTrue(offer.active);
        assertFalse(offer.accepted);
        assertEq(offer.expiresAt, expectedExpiry);
    }

    function test_MakeOffer_NFT_Success() public {
        // Create NFT listing
        uint256 listingId = marketplace.createNFTListingMock(
            seller, address(mockNFT721), 1, 1, 1 ether, AssetTypes.TokenStandard.ERC721
        );

        uint256 offerAmount = 0.9 ether;
        uint256 duration = 3 days;

        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: offerAmount}(listingId, duration);

        assertEq(offerId, 1);
        IOfferManager.Offer memory offer = offerManager.getOffer(offerId);
        assertEq(uint8(offer.assetType), uint8(AssetTypes.AssetType.NFT721));
    }

    function test_MakeOffer_RevertsOnTooSmallAmount() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IOfferManager.InvalidOfferAmount.selector, 0.0001 ether));
        offerManager.makeOffer{value: 0.0001 ether}(listingId, 7 days);
    }

    function test_MakeOffer_RevertsOnTooLargeAmount() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        uint256 tooLarge = AssetTypes.MAX_LISTING_PRICE + 1 ether;
        vm.deal(buyer, tooLarge);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IOfferManager.InvalidOfferAmount.selector, tooLarge));
        offerManager.makeOffer{value: tooLarge}(listingId, 7 days);
    }

    function test_MakeOffer_RevertsOnInvalidDuration() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IOfferManager.InvalidOfferDuration.selector, 1 hours));
        offerManager.makeOffer{value: 1 ether}(listingId, 1 hours); // Too short

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IOfferManager.InvalidOfferDuration.selector, 100 days));
        offerManager.makeOffer{value: 1 ether}(listingId, 100 days); // Too long
    }

    function test_MakeOffer_RevertsOnInvalidListingId() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IOfferManager.InvalidListingId.selector, 999));
        offerManager.makeOffer{value: 1 ether}(999, 7 days);
    }

    function test_MakeOffer_RevertsOnInactiveListing() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        // Cancel listing
        marketplace.cancelListingMock(listingId);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IOfferManager.ListingNotActive.selector, listingId));
        offerManager.makeOffer{value: 1 ether}(listingId, 7 days);
    }

    function test_MakeOffer_RevertsOnOwnListing() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(IOfferManager.CannotOfferOwnListing.selector, seller));
        offerManager.makeOffer{value: 1 ether}(listingId, 7 days);
    }

    function test_MakeOffer_MultipleOffersOnSameListing() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        uint256 offerId1 = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        vm.prank(buyer2);
        uint256 offerId2 = offerManager.makeOffer{value: 0.9 ether}(listingId, 7 days);

        assertEq(offerId1, 1);
        assertEq(offerId2, 2);

        uint256[] memory listingOffers = offerManager.getListingOffers(listingId);
        assertEq(listingOffers.length, 2);
        assertEq(listingOffers[0], offerId1);
        assertEq(listingOffers[1], offerId2);
    }

    // ============================================
    //          ACCEPT OFFER TESTS - NFT
    // ============================================

    function test_AcceptOffer_NFT721_Success() public {
        // Mint NFT to seller
        mockNFT721.mint(seller, 1);

        // Create NFT listing
        uint256 listingId = marketplace.createNFTListingMock(
            seller, address(mockNFT721), 1, 1, 1 ether, AssetTypes.TokenStandard.ERC721
        );

        // Buyer makes offer
        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.9 ether}(listingId, 7 days);

        // Seller approves OfferManager
        vm.prank(seller);
        mockNFT721.approve(address(offerManager), 1);

        uint256 sellerBalanceBefore = seller.balance;
        // uint256 buyerBalanceBefore = buyer.balance;

        // Seller accepts offer
        vm.expectEmit(true, true, true, true);
        emit OfferAccepted(offerId, listingId, seller, buyer, 0.9 ether);

        vm.prank(seller);
        offerManager.acceptOffer(offerId);

        // Verify NFT transferred
        assertEq(mockNFT721.ownerOf(1), buyer);

        // Verify payments
        uint256 platformFee = (0.9 ether * PLATFORM_FEE_BPS) / 10_000;
        uint256 sellerNet = 0.9 ether - platformFee;

        assertEq(seller.balance, sellerBalanceBefore + sellerNet);
        assertEq(address(feeDistributor).balance, platformFee);

        // Verify offer state
        IOfferManager.Offer memory offer = offerManager.getOffer(offerId);
        assertFalse(offer.active);
        assertTrue(offer.accepted);
    }

    function test_AcceptOffer_NFT1155_Success() public {
        // Mint NFT to seller
        mockNFT1155.mint(seller, 1, 10);

        // Create NFT listing
        uint256 listingId = marketplace.createNFTListingMock(
            seller, address(mockNFT1155), 1, 5, 1 ether, AssetTypes.TokenStandard.ERC1155
        );

        // Buyer makes offer
        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        // Seller approves OfferManager
        vm.prank(seller);
        mockNFT1155.setApprovalForAll(address(offerManager), true);

        // Seller accepts offer
        vm.prank(seller);
        offerManager.acceptOffer(offerId);

        // Verify NFT transferred
        assertEq(mockNFT1155.balanceOf(buyer, 1), 5);
        assertEq(mockNFT1155.balanceOf(seller, 1), 5); // Remaining
    }

    function test_AcceptOffer_NFT_RevertsIfNotApproved() public {
        mockNFT721.mint(seller, 1);

        uint256 listingId = marketplace.createNFTListingMock(
            seller, address(mockNFT721), 1, 1, 1 ether, AssetTypes.TokenStandard.ERC721
        );

        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.9 ether}(listingId, 7 days);

        // Don't approve - should revert
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(IOfferManager.NFTNotApproved.selector, address(mockNFT721), 1));
        offerManager.acceptOffer(offerId);
    }

    // ============================================
    //          ACCEPT OFFER TESTS - OFF-CHAIN
    // ============================================

    function test_AcceptOffer_OffChain_CreatesEscrow() public {
        // Create off-chain listing
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        // Buyer makes offer
        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        uint256 escrowBalanceBefore = address(escrowManager).balance;

        // Seller accepts offer
        vm.prank(seller);
        offerManager.acceptOffer(offerId);

        // Verify escrow created
        assertEq(escrowManager.escrowCounter(), 1);
        assertEq(address(escrowManager).balance, escrowBalanceBefore + 0.8 ether);

        // Verify offer state
        IOfferManager.Offer memory offer = offerManager.getOffer(offerId);
        assertFalse(offer.active);
        assertTrue(offer.accepted);
    }

    function test_AcceptOffer_RevertsOnInvalidOffer() public {
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(IOfferManager.InvalidOfferId.selector, 999));
        offerManager.acceptOffer(999);
    }

    function test_AcceptOffer_RevertsOnInactiveOffer() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        // Cancel offer
        vm.prank(buyer);
        offerManager.cancelOffer(offerId);

        // Try to accept
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(IOfferManager.OfferNotActive.selector, offerId));
        offerManager.acceptOffer(offerId);
    }

    function test_AcceptOffer_RevertsOnExpiredOffer() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        // Get offer expiry before warping
        IOfferManager.Offer memory offer = offerManager.getOffer(offerId);

        // Warp past expiry
        vm.warp(block.timestamp + 8 days);

        vm.expectRevert(abi.encodeWithSelector(IOfferManager.OfferExpiredError.selector, offerId, offer.expiresAt));
        vm.prank(seller);
        offerManager.acceptOffer(offerId);
    }

    function test_AcceptOffer_RevertsOnUnauthorizedSeller() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        // Random address tries to accept
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(IOfferManager.UnauthorizedSeller.selector, attacker, seller));
        offerManager.acceptOffer(offerId);
    }

    function test_AcceptOffer_RevertsIfListingSold() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        // Mark listing as sold
        marketplace.markListingAsSold(listingId);

        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(IOfferManager.ListingAlreadySold.selector, listingId));
        offerManager.acceptOffer(offerId);
    }

    // ============================================
    //          REJECT OFFER TESTS
    // ============================================

    function test_RejectOffer_Success() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        uint256 buyerBalanceBefore = buyer.balance;

        vm.expectEmit(true, true, true, true);
        emit OfferRejected(offerId, listingId, seller, buyer, "Price too low");

        vm.expectEmit(true, true, true, true);
        emit OfferRefunded(offerId, buyer, 0.8 ether);

        vm.prank(seller);
        offerManager.rejectOffer(offerId, "Price too low");

        // Verify refund
        assertEq(buyer.balance, buyerBalanceBefore + 0.8 ether);

        // Verify offer state
        IOfferManager.Offer memory offer = offerManager.getOffer(offerId);
        assertFalse(offer.active);
        assertFalse(offer.accepted);
    }

    function test_RejectOffer_RevertsOnUnauthorizedSeller() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(IOfferManager.UnauthorizedSeller.selector, attacker, seller));
        offerManager.rejectOffer(offerId, "reason");
    }

    // ============================================
    //          CANCEL OFFER TESTS
    // ============================================

    function test_CancelOffer_Success() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        uint256 buyerBalanceBefore = buyer.balance;

        vm.expectEmit(true, true, true, true);
        emit OfferCancelled(offerId, listingId, buyer, 0.8 ether);

        vm.prank(buyer);
        offerManager.cancelOffer(offerId);

        // Verify refund
        assertEq(buyer.balance, buyerBalanceBefore + 0.8 ether);

        // Verify offer state
        IOfferManager.Offer memory offer = offerManager.getOffer(offerId);
        assertFalse(offer.active);
    }

    function test_CancelOffer_RevertsOnUnauthorizedBuyer() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(IOfferManager.UnauthorizedBuyer.selector, attacker, buyer));
        offerManager.cancelOffer(offerId);
    }

    // ============================================
    //          CLAIM EXPIRED OFFER TESTS
    // ============================================

    function test_ClaimExpiredOffer_Success() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        // Warp past expiry
        vm.warp(block.timestamp + 8 days);

        uint256 buyerBalanceBefore = buyer.balance;

        vm.expectEmit(true, true, true, true);
        emit OfferExpired(offerId, listingId, buyer);

        // Anyone can claim expired offer
        offerManager.claimExpiredOffer(offerId);

        // Verify refund
        assertEq(buyer.balance, buyerBalanceBefore + 0.8 ether);

        // Verify offer state
        IOfferManager.Offer memory offer = offerManager.getOffer(offerId);
        assertFalse(offer.active);
    }

    function test_ClaimExpiredOffer_RevertsIfNotExpired() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        vm.expectRevert(abi.encodeWithSelector(IOfferManager.OfferNotActive.selector, offerId));
        offerManager.claimExpiredOffer(offerId);
    }

    // ============================================
    //          BATCH CANCEL OFFERS TESTS
    // ============================================

    function test_BatchCancelOffers_Success() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        // Create multiple offers
        vm.startPrank(buyer);
        uint256 offerId1 = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);
        uint256 offerId2 = offerManager.makeOffer{value: 0.7 ether}(listingId, 7 days);
        uint256 offerId3 = offerManager.makeOffer{value: 0.6 ether}(listingId, 7 days);
        vm.stopPrank();

        uint256 buyerBalanceBefore = buyer.balance;

        // Batch cancel
        uint256[] memory offerIds = new uint256[](3);
        offerIds[0] = offerId1;
        offerIds[1] = offerId2;
        offerIds[2] = offerId3;

        vm.prank(buyer);
        offerManager.batchCancelOffers(offerIds);

        // Verify refunds
        assertEq(buyer.balance, buyerBalanceBefore + 2.1 ether);

        // Verify all offers inactive
        assertFalse(offerManager.getOffer(offerId1).active);
        assertFalse(offerManager.getOffer(offerId2).active);
        assertFalse(offerManager.getOffer(offerId3).active);
    }

    function test_BatchCancelOffers_SkipsInvalidOffers() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        uint256 offerId1 = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        uint256 buyerBalanceBefore = buyer.balance;

        // Batch cancel with invalid IDs
        uint256[] memory offerIds = new uint256[](3);
        offerIds[0] = offerId1;
        offerIds[1] = 999; // Invalid
        offerIds[2] = 0; // Invalid

        vm.prank(buyer);
        offerManager.batchCancelOffers(offerIds);

        // Only valid offer refunded
        assertEq(buyer.balance, buyerBalanceBefore + 0.8 ether);
    }

    function test_BatchCancelOffers_RevertsOnTooLargeBatch() public {
        uint256[] memory offerIds = new uint256[](51);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IOfferManager.BatchSizeTooLarge.selector, 51, 50));
        offerManager.batchCancelOffers(offerIds);
    }

    // ============================================
    //          CLAIM REFUND FOR INVALID OFFER TESTS
    // ============================================

    function test_ClaimRefundForInvalidOffer_Success() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        // Seller cancels listing
        marketplace.cancelListingMock(listingId);

        uint256 buyerBalanceBefore = buyer.balance;

        // Buyer claims refund
        vm.prank(buyer);
        offerManager.claimRefundForInvalidOffer(offerId);

        // Verify refund
        assertEq(buyer.balance, buyerBalanceBefore + 0.8 ether);
    }

    function test_ClaimRefundForInvalidOffer_RevertsIfListingStillActive() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IOfferManager.OfferNotActive.selector, offerId));
        offerManager.claimRefundForInvalidOffer(offerId);
    }

    // ============================================
    //          VIEW FUNCTION TESTS
    // ============================================

    function test_GetOffer() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        IOfferManager.Offer memory offer = offerManager.getOffer(offerId);
        assertEq(offer.buyer, buyer);
        assertEq(offer.seller, seller);
        assertEq(offer.amount, 0.8 ether);
        assertEq(offer.listingId, listingId);
    }

    function test_GetListingOffers() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        vm.prank(buyer2);
        offerManager.makeOffer{value: 0.9 ether}(listingId, 7 days);

        uint256[] memory offers = offerManager.getListingOffers(listingId);
        assertEq(offers.length, 2);
    }

    function test_GetBuyerOffers() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.startPrank(buyer);
        offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);
        offerManager.makeOffer{value: 0.7 ether}(listingId, 7 days);
        vm.stopPrank();

        uint256[] memory offers = offerManager.getBuyerOffers(buyer);
        assertEq(offers.length, 2);
    }

    function test_GetSellerOffers() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        vm.prank(buyer2);
        offerManager.makeOffer{value: 0.9 ether}(listingId, 7 days);

        uint256[] memory offers = offerManager.getSellerOffers(seller);
        assertEq(offers.length, 2);
    }

    function test_IsOfferActive() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        assertTrue(offerManager.isOfferActive(offerId));

        // Cancel offer
        vm.prank(buyer);
        offerManager.cancelOffer(offerId);

        assertFalse(offerManager.isOfferActive(offerId));
    }

    function test_HasOfferExpired() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        assertFalse(offerManager.hasOfferExpired(offerId));

        vm.warp(block.timestamp + 8 days);

        assertTrue(offerManager.hasOfferExpired(offerId));
    }

    function test_GetActiveListingOffers() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        uint256 offerId1 = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        vm.prank(buyer2);
        uint256 offerId2 = offerManager.makeOffer{value: 0.9 ether}(listingId, 7 days);

        // Cancel one offer
        vm.prank(buyer);
        offerManager.cancelOffer(offerId1);

        uint256[] memory activeOffers = offerManager.getActiveListingOffers(listingId);
        assertEq(activeOffers.length, 1);
        assertEq(activeOffers[0], offerId2);
    }

    // ============================================
    //          ADMIN FUNCTION TESTS
    // ============================================

    function test_UpdatePlatformFee_Success() public {
        vm.expectEmit(true, true, true, true);
        emit PlatformFeeUpdated(PLATFORM_FEE_BPS, 500);

        vm.prank(feeManager);
        offerManager.updatePlatformFee(500);

        assertEq(offerManager.platformFeeBps(), 500);
    }

    function test_UpdatePlatformFee_RevertsOnUnauthorized() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotFeeManager.selector, buyer));
        offerManager.updatePlatformFee(500);
    }

    function test_UpdatePlatformFee_RevertsOnInvalidBps() public {
        vm.prank(feeManager);
        vm.expectRevert(abi.encodeWithSelector(PercentageMath.PercentageTooHigh.selector, 2000, 1000));
        offerManager.updatePlatformFee(2000);
    }

    function test_Pause_Success() public {
        // Admin already has PAUSER_ROLE from constructor
        vm.prank(admin);
        offerManager.pause();

        // Try to make offer
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        vm.expectRevert(); // EnforcedPause or "Pausable: paused" depending on OZ version
        offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);
    }

    function test_Unpause_Success() public {
        // Admin already has PAUSER_ROLE and ADMIN_ROLE from constructor
        vm.prank(admin);
        offerManager.pause();

        vm.prank(admin);
        offerManager.unpause();

        // Should work now
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);
    }

    // ============================================
    //          INTEGRATION TESTS
    // ============================================

    function test_CompleteOfferFlow_NFT() public {
        // Setup: mint NFT and create listing
        mockNFT721.mint(seller, 1);
        uint256 listingId = marketplace.createNFTListingMock(
            seller, address(mockNFT721), 1, 1, 1 ether, AssetTypes.TokenStandard.ERC721
        );

        // Buyer makes offer
        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.9 ether}(listingId, 7 days);

        // Seller approves and accepts
        vm.startPrank(seller);
        mockNFT721.approve(address(offerManager), 1);
        offerManager.acceptOffer(offerId);
        vm.stopPrank();

        // Verify complete flow
        assertEq(mockNFT721.ownerOf(1), buyer);
        IOfferManager.Offer memory offer = offerManager.getOffer(offerId);
        assertTrue(offer.accepted);
        assertFalse(offer.active);
    }

    function test_CompleteOfferFlow_OffChain() public {
        // Create off-chain listing
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        // Buyer makes offer
        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        // Seller accepts
        vm.prank(seller);
        offerManager.acceptOffer(offerId);

        // Verify escrow created
        assertEq(escrowManager.escrowCounter(), 1);
        IOfferManager.Offer memory offer = offerManager.getOffer(offerId);
        assertTrue(offer.accepted);
    }

    function test_MultipleOffersOneAccepted() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        // Multiple buyers make offers
        vm.prank(buyer);
        uint256 offerId1 = offerManager.makeOffer{value: 0.7 ether}(listingId, 7 days);

        vm.prank(buyer2);
        uint256 offerId2 = offerManager.makeOffer{value: 0.9 ether}(listingId, 7 days);

        // Track buyer balance before acceptance
        uint256 buyerBalanceBefore = buyer.balance;

        // Seller accepts higher offer
        // This automatically refunds all other offers on the listing
        vm.prank(seller);
        offerManager.acceptOffer(offerId2);

        // Verify first offer was automatically refunded when second offer was accepted
        assertEq(buyer.balance, buyerBalanceBefore + 0.7 ether);

        // Verify states
        assertFalse(offerManager.getOffer(offerId1).active);
        assertTrue(offerManager.getOffer(offerId2).accepted);
    }

    // ============================================
    //       FAILED REFUND CLAIM TESTS
    // ============================================

    function test_ClaimFailedRefund_Success() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        // Buyer makes offer
        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        // Manually simulate failed refund scenario
        // In production, this happens when _refundOtherOffersOnListing transfer fails
        vm.store(
            address(offerManager),
            keccak256(abi.encode(offerId, 5)), // slot for offerRefundAvailable mapping
            bytes32(uint256(1))
        );

        // Manually mark offer as inactive (as would happen in failed refund)
        // Note: We can't directly modify the offer struct, so we'll accept another offer to trigger this

        // Actually, let's create a proper scenario:
        // Create second offer and accept it to trigger automatic refund
        vm.prank(buyer2);
        uint256 offerId2 = offerManager.makeOffer{value: 0.9 ether}(listingId, 7 days);

        // Deploy a reverting contract as buyer
        RevertingReceiver revertingBuyer = new RevertingReceiver();
        vm.deal(address(revertingBuyer), 10 ether);

        // Make offer from reverting contract
        vm.prank(address(revertingBuyer));
        uint256 offerId3 = offerManager.makeOffer{value: 0.75 ether}(listingId, 7 days);

        uint256 revertingBuyerBalanceBefore = address(revertingBuyer).balance;

        // Accept offer 2, which should try to refund offer 1 and offer 3
        vm.prank(seller);
        offerManager.acceptOffer(offerId2);

        // Offer 3 refund should have failed, so it should be claimable
        assertTrue(offerManager.offerRefundAvailable(offerId3));

        // Now allow the reverting buyer to accept transfers
        revertingBuyer.setAcceptPayments(true);

        // Claim the failed refund
        vm.prank(address(revertingBuyer));
        offerManager.claimFailedRefund(offerId3);

        // Verify refund was successful
        assertEq(address(revertingBuyer).balance, revertingBuyerBalanceBefore + 0.75 ether);
        assertFalse(offerManager.offerRefundAvailable(offerId3));
    }

    function test_ClaimFailedRefund_RevertsOnNoRefundAvailable() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IOfferManager.NoRefundAvailable.selector, offerId));
        offerManager.claimFailedRefund(offerId);
    }

    function test_ClaimFailedRefund_RevertsOnUnauthorizedBuyer() public {
        uint256 listingId = marketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        uint256 offerId = offerManager.makeOffer{value: 0.8 ether}(listingId, 7 days);

        // Simulate failed refund
        vm.store(address(offerManager), keccak256(abi.encode(offerId, 5)), bytes32(uint256(1)));

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(IOfferManager.UnauthorizedBuyer.selector, attacker, buyer));
        offerManager.claimFailedRefund(offerId);
    }
}

// Helper contract for testing failed refunds
contract RevertingReceiver {
    bool public acceptPayments = false;

    function setAcceptPayments(bool _accept) external {
        acceptPayments = _accept;
    }

    receive() external payable {
        if (!acceptPayments) {
            revert("Payment rejected");
        }
    }
}

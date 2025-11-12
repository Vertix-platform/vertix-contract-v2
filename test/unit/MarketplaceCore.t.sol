// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MarketplaceCore} from "../../src/core/MarketplaceCore.sol";
import {RoleManager} from "../../src/access/RoleManager.sol";
import {IMarketplace} from "../../src/interfaces/IMarketplace.sol";
import {AssetTypes} from "../../src/libraries/AssetTypes.sol";
import {Errors} from "../../src/libraries/Errors.sol";

// Mock contracts
import {MockEscrowManager} from "../mocks/MockEscrowManager.sol";
import {MockNFTMarketplace} from "../mocks/MockNFTMarketplace.sol";
import {MockERC721} from "../mocks/MockERC721.sol";
import {MockERC1155} from "../mocks/MockERC1155.sol";

contract MarketplaceCoreTest is Test {
    MarketplaceCore public marketplace;
    RoleManager public roleManager;
    MockEscrowManager public escrowManager;
    MockNFTMarketplace public nftMarketplace;
    MockERC721 public mockNFT721;
    MockERC1155 public mockNFT1155;

    address public admin;
    address public seller;
    address public buyer;
    address public offerManager;

    // Events
    event ListingCreated(
        uint256 indexed listingId, address indexed seller, AssetTypes.AssetType assetType, uint256 price
    );
    event NFTListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 quantity,
        uint256 price
    );
    event ListingSold(uint256 indexed listingId, address indexed buyer, address indexed seller, uint256 price);
    event ListingCancelled(uint256 indexed listingId, address indexed seller);
    event PriceUpdated(uint256 indexed listingId, uint256 oldPrice, uint256 newPrice);
    event AuthorizedCallerAdded(address indexed caller);
    event AuthorizedCallerRemoved(address indexed caller);

    function setUp() public {
        admin = makeAddr("admin");
        seller = makeAddr("seller");
        buyer = makeAddr("buyer");
        offerManager = makeAddr("offerManager");

        // Deploy contracts
        roleManager = new RoleManager(admin);
        escrowManager = new MockEscrowManager();
        nftMarketplace = new MockNFTMarketplace();

        marketplace = new MarketplaceCore(address(roleManager), address(escrowManager), address(nftMarketplace));

        // Deploy NFT mocks
        mockNFT721 = new MockERC721();
        mockNFT1155 = new MockERC1155();

        // Fund accounts
        vm.deal(buyer, 100 ether);
        vm.deal(seller, 1 ether);
    }

    // ============================================
    //          CONSTRUCTOR TESTS
    // ============================================

    function test_Constructor_SetsStateCorrectly() public view {
        assertEq(address(marketplace.roleManager()), address(roleManager));
        assertEq(address(marketplace.escrowManager()), address(escrowManager));
        assertEq(address(marketplace.nftMarketplace()), address(nftMarketplace));
        assertEq(marketplace.listingCounter(), 0);
    }

    function test_Constructor_RevertsOnZeroRoleManager() public {
        vm.expectRevert(Errors.InvalidRoleManager.selector);
        new MarketplaceCore(address(0), address(escrowManager), address(nftMarketplace));
    }

    function test_Constructor_RevertsOnZeroEscrowManager() public {
        vm.expectRevert(Errors.InvalidEscrowManager.selector);
        new MarketplaceCore(address(roleManager), address(0), address(nftMarketplace));
    }

    function test_Constructor_RevertsOnZeroNFTMarketplace() public {
        vm.expectRevert(Errors.InvalidNFTMarketplace.selector);
        new MarketplaceCore(address(roleManager), address(escrowManager), address(0));
    }

    // ============================================
    //          CREATE NFT LISTING TESTS
    // ============================================

    function test_CreateNFTListing_ERC721_Success() public {
        // Mint NFT to seller
        mockNFT721.mint(seller, 1);

        // Approve marketplace
        vm.startPrank(seller);
        mockNFT721.approve(address(marketplace), 1);

        vm.expectEmit(true, true, true, true);
        emit NFTListingCreated(1, seller, address(mockNFT721), 1, 1, 1 ether);

        uint256 listingId =
            marketplace.createNFTListing(address(mockNFT721), 1, 1, 1 ether, AssetTypes.TokenStandard.ERC721);
        vm.stopPrank();

        assertEq(listingId, 1);
        assertEq(marketplace.listingCounter(), 1);

        IMarketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(listing.seller, seller);
        assertEq(listing.price, 1 ether);
        assertEq(uint8(listing.status), uint8(AssetTypes.ListingStatus.Active));
        assertEq(uint8(listing.assetType), uint8(AssetTypes.AssetType.NFT721));

        IMarketplace.NFTDetails memory nft = marketplace.getNFTDetails(listingId);
        assertEq(nft.nftContract, address(mockNFT721));
        assertEq(nft.tokenId, 1);
        assertEq(nft.quantity, 1);
    }

    function test_CreateNFTListing_ERC1155_Success() public {
        // Mint NFT to seller
        mockNFT1155.mint(seller, 1, 10);

        // Approve marketplace
        vm.startPrank(seller);
        mockNFT1155.setApprovalForAll(address(marketplace), true);

        uint256 listingId =
            marketplace.createNFTListing(address(mockNFT1155), 1, 5, 1 ether, AssetTypes.TokenStandard.ERC1155);
        vm.stopPrank();

        assertEq(listingId, 1);

        IMarketplace.NFTDetails memory nft = marketplace.getNFTDetails(listingId);
        assertEq(nft.quantity, 5);
        assertEq(uint8(nft.standard), uint8(AssetTypes.TokenStandard.ERC1155));
    }

    function test_CreateNFTListing_RevertsOnZeroPrice() public {
        mockNFT721.mint(seller, 1);

        vm.startPrank(seller);
        mockNFT721.approve(address(marketplace), 1);

        vm.expectRevert(MarketplaceCore.InvalidPrice.selector);
        marketplace.createNFTListing(address(mockNFT721), 1, 1, 0, AssetTypes.TokenStandard.ERC721);
        vm.stopPrank();
    }

    function test_CreateNFTListing_RevertsOnExcessivePrice() public {
        mockNFT721.mint(seller, 1);

        vm.startPrank(seller);
        mockNFT721.approve(address(marketplace), 1);

        uint256 tooHigh = AssetTypes.MAX_LISTING_PRICE + 1 ether;
        vm.expectRevert(MarketplaceCore.InvalidPrice.selector);
        marketplace.createNFTListing(address(mockNFT721), 1, 1, tooHigh, AssetTypes.TokenStandard.ERC721);
        vm.stopPrank();
    }

    function test_CreateNFTListing_RevertsOnZeroAddress() public {
        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.InvalidNFTParameters.selector);
        marketplace.createNFTListing(address(0), 1, 1, 1 ether, AssetTypes.TokenStandard.ERC721);
    }

    function test_CreateNFTListing_RevertsIfNotOwner() public {
        mockNFT721.mint(seller, 1);

        vm.prank(buyer); // Different address
        vm.expectRevert(MarketplaceCore.NotOwner.selector);
        marketplace.createNFTListing(address(mockNFT721), 1, 1, 1 ether, AssetTypes.TokenStandard.ERC721);
    }

    function test_CreateNFTListing_RevertsIfNotApproved() public {
        mockNFT721.mint(seller, 1);

        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.NotApproved.selector);
        marketplace.createNFTListing(address(mockNFT721), 1, 1, 1 ether, AssetTypes.TokenStandard.ERC721);
    }

    function test_CreateNFTListing_ERC721_RevertsOnInvalidQuantity() public {
        mockNFT721.mint(seller, 1);

        vm.startPrank(seller);
        mockNFT721.approve(address(marketplace), 1);

        vm.expectRevert(MarketplaceCore.InvalidNFTParameters.selector);
        marketplace.createNFTListing(address(mockNFT721), 1, 5, 1 ether, AssetTypes.TokenStandard.ERC721);
        vm.stopPrank();
    }

    function test_CreateNFTListing_ERC1155_RevertsOnZeroQuantity() public {
        mockNFT1155.mint(seller, 1, 10);

        vm.startPrank(seller);
        mockNFT1155.setApprovalForAll(address(marketplace), true);

        vm.expectRevert(MarketplaceCore.InvalidNFTParameters.selector);
        marketplace.createNFTListing(address(mockNFT1155), 1, 0, 1 ether, AssetTypes.TokenStandard.ERC1155);
        vm.stopPrank();
    }

    function test_CreateNFTListing_ERC1155_RevertsOnInsufficientBalance() public {
        mockNFT1155.mint(seller, 1, 5);

        vm.startPrank(seller);
        mockNFT1155.setApprovalForAll(address(marketplace), true);

        vm.expectRevert(MarketplaceCore.InsufficientBalance.selector);
        marketplace.createNFTListing(address(mockNFT1155), 1, 10, 1 ether, AssetTypes.TokenStandard.ERC1155);
        vm.stopPrank();
    }

    // ============================================
    //          CREATE OFF-CHAIN LISTING TESTS
    // ============================================

    function test_CreateOffChainListing_Success() public {
        vm.expectEmit(true, true, true, true);
        emit ListingCreated(1, seller, AssetTypes.AssetType.SocialMediaYouTube, 1 ether);

        vm.prank(seller);
        uint256 listingId = marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        assertEq(listingId, 1);

        IMarketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(listing.seller, seller);
        assertEq(listing.price, 1 ether);
        assertEq(listing.assetHash, bytes32("hash"));
        assertEq(listing.metadataURI, "ipfs://metadata");
        assertEq(uint8(listing.assetType), uint8(AssetTypes.AssetType.SocialMediaYouTube));
    }

    function test_CreateOffChainListing_RevertsOnZeroPrice() public {
        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.InvalidPrice.selector);
        marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 0, bytes32("hash"), "ipfs://metadata"
        );
    }

    function test_CreateOffChainListing_RevertsOnExcessivePrice() public {
        uint256 tooHigh = AssetTypes.MAX_LISTING_PRICE + 1 ether;

        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.InvalidPrice.selector);
        marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, tooHigh, bytes32("hash"), "ipfs://metadata"
        );
    }

    function test_CreateOffChainListing_RevertsOnNFTType() public {
        vm.prank(seller);
        vm.expectRevert(Errors.UseCreateNFTListing.selector);
        marketplace.createOffChainListing(AssetTypes.AssetType.NFT721, 1 ether, bytes32("hash"), "ipfs://metadata");
    }

    function test_CreateOffChainListing_RevertsOnEmptyHash() public {
        vm.prank(seller);
        vm.expectRevert(Errors.AssetHashRequired.selector);
        marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32(0), "ipfs://metadata"
        );
    }

    function test_CreateOffChainListing_RevertsOnEmptyMetadata() public {
        vm.prank(seller);
        vm.expectRevert(Errors.MetadataURIRequired.selector);
        marketplace.createOffChainListing(AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "");
    }

    // ============================================
    //          PURCHASE ASSET TESTS - NFT
    // ============================================

    function test_PurchaseAsset_NFT721_Success() public {
        // Create listing
        mockNFT721.mint(seller, 1);
        vm.startPrank(seller);
        mockNFT721.approve(address(marketplace), 1);
        uint256 listingId =
            marketplace.createNFTListing(address(mockNFT721), 1, 1, 1 ether, AssetTypes.TokenStandard.ERC721);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit ListingSold(listingId, buyer, seller, 1 ether);

        vm.prank(buyer);
        marketplace.purchaseAsset{value: 1 ether}(listingId);

        // Verify listing marked as sold
        IMarketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(uint8(listing.status), uint8(AssetTypes.ListingStatus.Sold));

        // Verify NFT marketplace called
        assertTrue(nftMarketplace.executePurchaseCalled());
    }

    // ============================================
    //          PURCHASE ASSET TESTS - OFF-CHAIN
    // ============================================

    function test_PurchaseAsset_OffChain_CreatesEscrow() public {
        // Create off-chain listing
        vm.prank(seller);
        uint256 listingId = marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        marketplace.purchaseAsset{value: 1 ether}(listingId);

        // Verify escrow created
        assertEq(escrowManager.escrowCounter(), 1);

        // Verify listing marked as sold
        IMarketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(uint8(listing.status), uint8(AssetTypes.ListingStatus.Sold));
    }

    function test_PurchaseAsset_RevertsOnInactiveListing() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        // Cancel listing
        vm.prank(seller);
        marketplace.cancelListing(listingId);

        // Try to purchase
        vm.prank(buyer);
        vm.expectRevert(MarketplaceCore.ListingNotActive.selector);
        marketplace.purchaseAsset{value: 1 ether}(listingId);
    }

    function test_PurchaseAsset_RevertsOnIncorrectPayment() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        vm.expectRevert(MarketplaceCore.IncorrectPayment.selector);
        marketplace.purchaseAsset{value: 0.5 ether}(listingId);
    }

    function test_PurchaseAsset_RevertsOnSelfPurchase() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.CannotBuyOwnListing.selector);
        marketplace.purchaseAsset{value: 1 ether}(listingId);
    }

    // ============================================
    //          CANCEL LISTING TESTS
    // ============================================

    function test_CancelListing_Success() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.expectEmit(true, true, true, true);
        emit ListingCancelled(listingId, seller);

        vm.prank(seller);
        marketplace.cancelListing(listingId);

        IMarketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(uint8(listing.status), uint8(AssetTypes.ListingStatus.Cancelled));
    }

    function test_CancelListing_RevertsOnNotSeller() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        vm.expectRevert(MarketplaceCore.NotSeller.selector);
        marketplace.cancelListing(listingId);
    }

    function test_CancelListing_RevertsOnAlreadyCancelled() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(seller);
        marketplace.cancelListing(listingId);

        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.ListingNotActive.selector);
        marketplace.cancelListing(listingId);
    }

    // ============================================
    //          UPDATE PRICE TESTS
    // ============================================

    function test_UpdatePrice_Success() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.expectEmit(true, true, true, true);
        emit PriceUpdated(listingId, 1 ether, 2 ether);

        vm.prank(seller);
        marketplace.updatePrice(listingId, 2 ether);

        IMarketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(listing.price, 2 ether);
    }

    function test_UpdatePrice_RevertsOnNotSeller() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        vm.expectRevert(MarketplaceCore.NotSeller.selector);
        marketplace.updatePrice(listingId, 2 ether);
    }

    function test_UpdatePrice_RevertsOnInactiveListing() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(seller);
        marketplace.cancelListing(listingId);

        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.ListingNotActive.selector);
        marketplace.updatePrice(listingId, 2 ether);
    }

    function test_UpdatePrice_RevertsOnZeroPrice() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.InvalidPrice.selector);
        marketplace.updatePrice(listingId, 0);
    }

    function test_UpdatePrice_RevertsOnExcessivePrice() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        uint256 tooHigh = AssetTypes.MAX_LISTING_PRICE + 1 ether;

        vm.prank(seller);
        vm.expectRevert(MarketplaceCore.InvalidPrice.selector);
        marketplace.updatePrice(listingId, tooHigh);
    }

    // ============================================
    //          MARK LISTING AS SOLD TESTS
    // ============================================

    function test_MarkListingAsSold_Success() public {
        // First authorize the caller
        vm.prank(admin);
        marketplace.addAuthorizedCaller(offerManager);

        // Create listing
        vm.prank(seller);
        uint256 listingId = marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        // Mark as sold
        vm.prank(offerManager);
        marketplace.markListingAsSold(listingId);

        IMarketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(uint8(listing.status), uint8(AssetTypes.ListingStatus.Sold));
    }

    function test_MarkListingAsSold_RevertsOnUnauthorizedCaller() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthorized.selector, buyer));
        marketplace.markListingAsSold(listingId);
    }

    function test_MarkListingAsSold_RevertsOnInvalidListing() public {
        vm.prank(admin);
        marketplace.addAuthorizedCaller(offerManager);

        vm.prank(offerManager);
        vm.expectRevert(MarketplaceCore.ListingNotActive.selector);
        marketplace.markListingAsSold(999);
    }

    // ============================================
    //          AUTHORIZED CALLER TESTS
    // ============================================

    function test_AddAuthorizedCaller_Success() public {
        vm.expectEmit(true, true, true, true);
        emit AuthorizedCallerAdded(offerManager);

        vm.prank(admin);
        marketplace.addAuthorizedCaller(offerManager);

        assertTrue(marketplace.authorizedCallers(offerManager));
    }

    function test_AddAuthorizedCaller_RevertsOnUnauthorized() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotAdmin.selector, buyer));
        marketplace.addAuthorizedCaller(offerManager);
    }

    function test_AddAuthorizedCaller_RevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(Errors.ZeroAddress.selector);
        marketplace.addAuthorizedCaller(address(0));
    }

    function test_RemoveAuthorizedCaller_Success() public {
        vm.startPrank(admin);
        marketplace.addAuthorizedCaller(offerManager);

        vm.expectEmit(true, true, true, true);
        emit AuthorizedCallerRemoved(offerManager);

        marketplace.removeAuthorizedCaller(offerManager);
        vm.stopPrank();

        assertFalse(marketplace.authorizedCallers(offerManager));
    }

    function test_RemoveAuthorizedCaller_RevertsOnUnauthorized() public {
        vm.prank(admin);
        marketplace.addAuthorizedCaller(offerManager);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotAdmin.selector, buyer));
        marketplace.removeAuthorizedCaller(offerManager);
    }

    // ============================================
    //          VIEW FUNCTION TESTS
    // ============================================

    function test_GetSellerListings() public {
        vm.startPrank(seller);
        marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash1"), "ipfs://1"
        );
        marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaTwitter, 2 ether, bytes32("hash2"), "ipfs://2"
        );
        vm.stopPrank();

        uint256[] memory listings = marketplace.getSellerListings(seller);
        assertEq(listings.length, 2);
        assertEq(listings[0], 1);
        assertEq(listings[1], 2);
    }

    function test_IsNFTListing() public {
        // Create NFT listing
        mockNFT721.mint(seller, 1);
        vm.startPrank(seller);
        mockNFT721.approve(address(marketplace), 1);
        uint256 nftListingId =
            marketplace.createNFTListing(address(mockNFT721), 1, 1, 1 ether, AssetTypes.TokenStandard.ERC721);

        // Create off-chain listing
        uint256 offChainListingId = marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );
        vm.stopPrank();

        assertTrue(marketplace.isNFTListing(nftListingId));
        assertFalse(marketplace.isNFTListing(offChainListingId));
    }

    // ============================================
    //          PAUSE/UNPAUSE TESTS
    // ============================================

    function test_Pause_Success() public {
        vm.prank(admin);
        marketplace.pause();

        vm.prank(seller);
        vm.expectRevert();
        marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );
    }

    function test_Unpause_Success() public {
        vm.prank(admin);
        marketplace.pause();

        vm.prank(admin);
        marketplace.unpause();

        vm.prank(seller);
        marketplace.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, 1 ether, bytes32("hash"), "ipfs://metadata"
        );
    }
}

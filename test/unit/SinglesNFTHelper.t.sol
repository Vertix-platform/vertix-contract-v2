// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SinglesNFTHelper} from "../../src/nft/SinglesNFTHelper.sol";
import {VertixSinglesNFT721} from "../../src/nft/VertixSinglesNFT721.sol";
import {VertixSinglesNFT1155} from "../../src/nft/VertixSinglesNFT1155.sol";
import {MarketplaceCore} from "../../src/core/MarketplaceCore.sol";
import {NFTMarketplace} from "../../src/nft/NFTMarketplace.sol";
import {RoleManager} from "../../src/access/RoleManager.sol";
import {FeeDistributor} from "../../src/core/FeeDistributor.sol";
import {EscrowManager} from "../../src/escrow/EscrowManager.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {AssetTypes} from "../../src/libraries/AssetTypes.sol";

contract SinglesNFTHelperTest is Test {
    SinglesNFTHelper public helper;
    VertixSinglesNFT721 public singlesNFT721;
    VertixSinglesNFT1155 public singlesNFT1155;
    MarketplaceCore public marketplaceCore;
    NFTMarketplace public nftMarketplace;
    RoleManager public roleManager;
    FeeDistributor public feeDistributor;
    EscrowManager public escrowManager;

    address public owner;
    address public creator1;
    address public creator2;
    address public buyer;
    address public feeCollector;

    uint256 constant PLATFORM_FEE_BPS = 250; // 2.5%
    uint256 constant LISTING_PRICE = 1 ether;

    event SingleNFTMintedAndListed(
        address indexed creator, uint256 indexed tokenId, uint256 indexed listingId, uint256 price, address nftContract
    );

    function setUp() public {
        owner = makeAddr("owner");
        creator1 = makeAddr("creator1");
        creator2 = makeAddr("creator2");
        buyer = makeAddr("buyer");
        feeCollector = makeAddr("feeCollector");

        vm.deal(buyer, 100 ether);

        // Deploy core contracts
        roleManager = new RoleManager(owner);
        feeDistributor = new FeeDistributor(address(roleManager), feeCollector, PLATFORM_FEE_BPS);
        escrowManager = new EscrowManager(address(roleManager), address(feeDistributor), PLATFORM_FEE_BPS);

        // Deploy shared NFT collections
        singlesNFT721 = new VertixSinglesNFT721();
        singlesNFT721.initialize("Vertix Singles", "VSINGLE", owner);

        singlesNFT1155 = new VertixSinglesNFT1155();
        singlesNFT1155.initialize("Vertix Editions", "VEDITION", "", owner);

        // Compute future marketplace address
        address futureMarketplace = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);

        // Deploy NFT marketplace
        nftMarketplace = new NFTMarketplace(futureMarketplace, address(feeDistributor), PLATFORM_FEE_BPS);

        // Deploy marketplace core
        marketplaceCore = new MarketplaceCore(address(roleManager), address(escrowManager), address(nftMarketplace));

        // Deploy helper
        helper = new SinglesNFTHelper(address(singlesNFT721), address(singlesNFT1155), address(marketplaceCore));

        // Pre-approve helper for creators (required for mint-and-list functionality)
        vm.prank(creator1);
        singlesNFT721.setApprovalForAll(address(helper), true);
        vm.prank(creator1);
        singlesNFT1155.setApprovalForAll(address(helper), true);
        // Pre-approve NFTMarketplace for ERC-1155 (required since helper can't approve on behalf of user)
        vm.prank(creator1);
        singlesNFT1155.setApprovalForAll(address(nftMarketplace), true);

        vm.prank(creator2);
        singlesNFT721.setApprovalForAll(address(helper), true);
        vm.prank(creator2);
        singlesNFT1155.setApprovalForAll(address(helper), true);
        // Pre-approve NFTMarketplace for ERC-1155 (required since helper can't approve on behalf of user)
        vm.prank(creator2);
        singlesNFT1155.setApprovalForAll(address(nftMarketplace), true);
    }

    // ============================================
    //         CONSTRUCTOR TESTS
    // ============================================

    function test_Constructor_SetsContracts() public view {
        assertEq(address(helper.singlesNFT721()), address(singlesNFT721));
        assertEq(address(helper.singlesNFT1155()), address(singlesNFT1155));
        assertEq(address(helper.marketplaceCore()), address(marketplaceCore));
    }

    function test_Constructor_RevertsOnZeroSinglesNFT721() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new SinglesNFTHelper(address(0), address(singlesNFT1155), address(marketplaceCore));
    }

    function test_Constructor_RevertsOnZeroSinglesNFT1155() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new SinglesNFTHelper(address(singlesNFT721), address(0), address(marketplaceCore));
    }

    function test_Constructor_RevertsOnZeroMarketplaceCore() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        new SinglesNFTHelper(address(singlesNFT721), address(singlesNFT1155), address(0));
    }

    // ============================================
    //         MINT AND LIST 721 TESTS
    // ============================================

    function test_MintAndList721_MintsNFT() public {
        vm.prank(creator1);
        (uint256 tokenId,) = helper.mintAndList721("ipfs://test1", LISTING_PRICE);

        assertEq(tokenId, 1);
        assertEq(singlesNFT721.ownerOf(tokenId), creator1);
    }

    function test_MintAndList721_CreatesListing() public {
        vm.prank(creator1);
        (uint256 tokenId, uint256 listingId) = helper.mintAndList721("ipfs://test1", LISTING_PRICE);

        MarketplaceCore.Listing memory listing = marketplaceCore.getListing(listingId);
        MarketplaceCore.NFTDetails memory nftDetails = marketplaceCore.getNFTDetails(listingId);

        assertEq(listing.seller, creator1);
        assertEq(listing.price, LISTING_PRICE);
        assertEq(uint8(listing.status), uint8(AssetTypes.ListingStatus.Active));
        assertEq(nftDetails.nftContract, address(singlesNFT721));
        assertEq(nftDetails.tokenId, tokenId);
    }

    function test_MintAndList721_EmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit SingleNFTMintedAndListed(creator1, 1, 1, LISTING_PRICE, address(singlesNFT721));

        vm.prank(creator1);
        helper.mintAndList721("ipfs://test1", LISTING_PRICE);
    }

    function test_MintAndList721_SetsTokenURI() public {
        vm.prank(creator1);
        (uint256 tokenId,) = helper.mintAndList721("ipfs://QmTest123", LISTING_PRICE);

        assertEq(singlesNFT721.tokenURI(tokenId), "ipfs://QmTest123");
    }

    function test_MintAndList721_AllowsMultipleCreators() public {
        vm.prank(creator1);
        (uint256 token1, uint256 listing1) = helper.mintAndList721("ipfs://creator1", 1 ether);

        vm.prank(creator2);
        (uint256 token2, uint256 listing2) = helper.mintAndList721("ipfs://creator2", 2 ether);

        assertEq(singlesNFT721.ownerOf(token1), creator1);
        assertEq(singlesNFT721.ownerOf(token2), creator2);
        assertEq(marketplaceCore.getListing(listing1).price, 1 ether);
        assertEq(marketplaceCore.getListing(listing2).price, 2 ether);
    }

    function test_MintAndList721_WorksWithVariousPrices() public {
        vm.prank(creator1);
        (, uint256 listingId) = helper.mintAndList721("ipfs://test", 0.5 ether);

        assertEq(marketplaceCore.getListing(listingId).price, 0.5 ether);
    }

    // ============================================
    //         MINT AND LIST 1155 TESTS
    // ============================================

    function test_MintAndList1155_MintsNFT() public {
        vm.prank(creator1);
        (uint256 tokenId,) = helper.mintAndList1155(100, 200, "ipfs://test1", LISTING_PRICE, 50);

        assertEq(tokenId, 1);
        assertEq(singlesNFT1155.balanceOf(creator1, tokenId), 100);
    }

    function test_MintAndList1155_CreatesListing() public {
        vm.prank(creator1);
        (uint256 tokenId, uint256 listingId) = helper.mintAndList1155(100, 200, "ipfs://test1", LISTING_PRICE, 50);

        MarketplaceCore.Listing memory listing = marketplaceCore.getListing(listingId);
        MarketplaceCore.NFTDetails memory nftDetails = marketplaceCore.getNFTDetails(listingId);

        assertEq(listing.seller, creator1);
        assertEq(listing.price, LISTING_PRICE);
        assertEq(uint8(listing.status), uint8(AssetTypes.ListingStatus.Active));
        assertEq(nftDetails.nftContract, address(singlesNFT1155));
        assertEq(nftDetails.tokenId, tokenId);
        assertEq(nftDetails.quantity, 50);
    }

    function test_MintAndList1155_EmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit SingleNFTMintedAndListed(creator1, 1, 1, LISTING_PRICE, address(singlesNFT1155));

        vm.prank(creator1);
        helper.mintAndList1155(100, 200, "ipfs://test1", LISTING_PRICE, 50);
    }

    function test_MintAndList1155_SetsTokenURI() public {
        vm.prank(creator1);
        (uint256 tokenId,) = helper.mintAndList1155(100, 200, "ipfs://QmTest123", LISTING_PRICE, 50);

        assertEq(singlesNFT1155.uri(tokenId), "ipfs://QmTest123");
    }

    function test_MintAndList1155_RevertsOnZeroQuantityToList() public {
        vm.prank(creator1);
        vm.expectRevert(Errors.InvalidAmount.selector);
        helper.mintAndList1155(100, 200, "ipfs://test1", LISTING_PRICE, 0);
    }

    function test_MintAndList1155_RevertsOnQuantityExceedingAmount() public {
        vm.prank(creator1);
        vm.expectRevert(Errors.InvalidAmount.selector);
        helper.mintAndList1155(100, 200, "ipfs://test1", LISTING_PRICE, 101);
    }

    function test_MintAndList1155_AllowsListingAllMinted() public {
        vm.prank(creator1);
        (uint256 tokenId, uint256 listingId) = helper.mintAndList1155(100, 200, "ipfs://test1", LISTING_PRICE, 100);

        assertEq(singlesNFT1155.balanceOf(creator1, tokenId), 100);
        assertEq(marketplaceCore.getNFTDetails(listingId).quantity, 100);
    }

    function test_MintAndList1155_AllowsListingPartial() public {
        vm.prank(creator1);
        (uint256 tokenId, uint256 listingId) = helper.mintAndList1155(100, 200, "ipfs://test1", LISTING_PRICE, 25);

        assertEq(singlesNFT1155.balanceOf(creator1, tokenId), 100);
        assertEq(marketplaceCore.getNFTDetails(listingId).quantity, 25);
    }

    function test_MintAndList1155_WorksWithUnlimitedSupply() public {
        vm.prank(creator1);
        (uint256 tokenId,) = helper.mintAndList1155(100, 0, "ipfs://test1", LISTING_PRICE, 50);

        assertEq(singlesNFT1155.tokenMaxSupply(tokenId), 0);
    }

    function test_MintAndList1155_AllowsMultipleCreators() public {
        vm.prank(creator1);
        (uint256 token1, uint256 listing1) = helper.mintAndList1155(100, 0, "ipfs://creator1", 1 ether, 50);

        vm.prank(creator2);
        (uint256 token2, uint256 listing2) = helper.mintAndList1155(200, 500, "ipfs://creator2", 2 ether, 100);

        assertEq(singlesNFT1155.balanceOf(creator1, token1), 100);
        assertEq(singlesNFT1155.balanceOf(creator2, token2), 200);
        assertEq(marketplaceCore.getNFTDetails(listing1).quantity, 50);
        assertEq(marketplaceCore.getNFTDetails(listing2).quantity, 100);
    }

    // ============================================
    //         VIEW FUNCTION TESTS
    // ============================================

    function test_IsApproved_ReturnsTrueAfterSetup() public view {
        // Creators are pre-approved in setUp for convenience
        (bool approved721, bool approved1155) = helper.isApproved(creator1);
        assertTrue(approved721);
        assertTrue(approved1155);
    }

    function test_IsApproved_ReturnsFalseForUnapprovedUser() public {
        address randomUser = makeAddr("randomUser");
        (bool approved721, bool approved1155) = helper.isApproved(randomUser);
        assertFalse(approved721);
        assertFalse(approved1155);
    }

    function test_IsApproved_ReturnsTrueAfterApproval721() public {
        vm.prank(creator1);
        singlesNFT721.setApprovalForAll(address(helper), true);

        (bool approved721,) = helper.isApproved(creator1);
        assertTrue(approved721);
    }

    function test_IsApproved_ReturnsTrueAfterApproval1155() public {
        vm.prank(creator1);
        singlesNFT1155.setApprovalForAll(address(helper), true);

        (, bool approved1155) = helper.isApproved(creator1);
        assertTrue(approved1155);
    }

    function test_GetSharedCollections_ReturnsCorrectAddresses() public view {
        (address nft721, address nft1155) = helper.getSharedCollections();
        assertEq(nft721, address(singlesNFT721));
        assertEq(nft1155, address(singlesNFT1155));
    }

    // ============================================
    //         INTEGRATION TESTS
    // ============================================

    function test_Integration_MintList721AndPurchase() public {
        // Creator mints and lists
        vm.prank(creator1);
        (uint256 tokenId, uint256 listingId) = helper.mintAndList721("ipfs://test1", LISTING_PRICE);

        // Verify listing
        MarketplaceCore.Listing memory listing = marketplaceCore.getListing(listingId);
        MarketplaceCore.NFTDetails memory nftDetails = marketplaceCore.getNFTDetails(listingId);
        assertEq(listing.seller, creator1);
        assertEq(nftDetails.nftContract, address(singlesNFT721));

        // Buyer purchases
        vm.prank(buyer);
        marketplaceCore.purchaseAsset{value: LISTING_PRICE}(listingId);

        // Verify ownership transfer
        assertEq(singlesNFT721.ownerOf(tokenId), buyer);
    }

    function test_Integration_MintList1155AndPurchase() public {
        // Creator mints and lists
        vm.prank(creator1);
        (uint256 tokenId, uint256 listingId) = helper.mintAndList1155(100, 0, "ipfs://test1", LISTING_PRICE, 50);

        // Verify listing
        MarketplaceCore.Listing memory listing = marketplaceCore.getListing(listingId);
        MarketplaceCore.NFTDetails memory nftDetails = marketplaceCore.getNFTDetails(listingId);
        assertEq(listing.seller, creator1);
        assertEq(nftDetails.nftContract, address(singlesNFT1155));

        // Buyer purchases
        vm.prank(buyer);
        marketplaceCore.purchaseAsset{value: LISTING_PRICE}(listingId);

        // Verify balances
        assertEq(singlesNFT1155.balanceOf(creator1, tokenId), 50); // 50 left
        assertEq(singlesNFT1155.balanceOf(buyer, tokenId), 50); // 50 purchased
    }

    function test_Integration_MultipleCreatorsMintAndList() public {
        // Creator1 mints and lists 721
        vm.prank(creator1);
        (uint256 token1, uint256 listing1) = helper.mintAndList721("ipfs://creator1-721", 1 ether);

        // Creator2 mints and lists 1155
        vm.prank(creator2);
        (uint256 token2, uint256 listing2) = helper.mintAndList1155(200, 0, "ipfs://creator2-1155", 0.5 ether, 100);

        // Creator1 mints and lists another 1155
        vm.prank(creator1);
        (uint256 token3, uint256 listing3) = helper.mintAndList1155(50, 100, "ipfs://creator1-1155", 2 ether, 25);

        // Verify all listings
        assertEq(marketplaceCore.getListing(listing1).seller, creator1);
        assertEq(marketplaceCore.getListing(listing2).seller, creator2);
        assertEq(marketplaceCore.getListing(listing3).seller, creator1);

        // Verify ownership
        assertEq(singlesNFT721.ownerOf(token1), creator1);
        assertEq(singlesNFT1155.balanceOf(creator2, token2), 200);
        assertEq(singlesNFT1155.balanceOf(creator1, token3), 50);
    }

    function test_Integration_CreatorRetainsUnlistedTokens() public {
        // Creator mints 100, lists only 30
        vm.prank(creator1);
        (uint256 tokenId, uint256 listingId) = helper.mintAndList1155(100, 0, "ipfs://test1", LISTING_PRICE, 30);

        // Creator still has all 100
        assertEq(singlesNFT1155.balanceOf(creator1, tokenId), 100);

        // Listing shows only 30
        assertEq(marketplaceCore.getNFTDetails(listingId).quantity, 30);

        // Buyer purchases the 30
        vm.prank(buyer);
        marketplaceCore.purchaseAsset{value: LISTING_PRICE}(listingId);

        // Creator has 70 left, buyer has 30
        assertEq(singlesNFT1155.balanceOf(creator1, tokenId), 70);
        assertEq(singlesNFT1155.balanceOf(buyer, tokenId), 30);
    }

    // ============================================
    //         FUZZ TESTS
    // ============================================

    function testFuzz_MintAndList721_VariousPrices(uint96 price) public {
        vm.assume(price > 0 && price < 1000 ether);

        vm.prank(creator1);
        (, uint256 listingId) = helper.mintAndList721("ipfs://test", price);

        assertEq(marketplaceCore.getListing(listingId).price, price);
    }

    function testFuzz_MintAndList1155_VariousAmounts(uint16 amount, uint16 listAmount) public {
        vm.assume(amount > 0 && amount <= 10_000);
        vm.assume(listAmount > 0 && listAmount <= amount);

        vm.prank(creator1);
        (uint256 tokenId, uint256 listingId) =
            helper.mintAndList1155(amount, 0, "ipfs://test", LISTING_PRICE, listAmount);

        assertEq(singlesNFT1155.balanceOf(creator1, tokenId), amount);
        assertEq(marketplaceCore.getNFTDetails(listingId).quantity, listAmount);
    }

    function testFuzz_MintAndList721_VariousURIs(string memory uri) public {
        vm.assume(bytes(uri).length > 0 && bytes(uri).length < 1000);

        vm.prank(creator1);
        (uint256 tokenId,) = helper.mintAndList721(uri, LISTING_PRICE);

        assertEq(singlesNFT721.tokenURI(tokenId), uri);
    }

    function testFuzz_MintAndList1155_VariousURIs(string memory uri) public {
        vm.assume(bytes(uri).length > 0 && bytes(uri).length < 1000);

        vm.prank(creator1);
        (uint256 tokenId,) = helper.mintAndList1155(100, 0, uri, LISTING_PRICE, 50);

        assertEq(singlesNFT1155.uri(tokenId), uri);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockNFTMarketplace} from "../mocks/MockNFTMarketplace.sol";
import {MockNFTRevert} from "../mocks/MockNFTRevert.sol";
import {MockEscrowManager} from "../mocks/MockEscrowManager.sol";
import {MockMarketplace} from "../mocks/MockMarketplace.sol";
import {AssetTypes} from "../../src/libraries/AssetTypes.sol";
import {IEscrowManager} from "../../src/interfaces/IEscrowManager.sol";
import {IMarketplace} from "../../src/interfaces/IMarketplace.sol";

/**
 * @title MockContracts Test Suite
 * @notice Tests for mock contracts to improve coverage
 * @dev These tests ensure all mock contract functions are covered
 */
contract MockContractsTest is Test {
    MockNFTMarketplace public mockNFTMarketplace;
    MockNFTRevert public mockNFTRevert;
    MockEscrowManager public mockEscrowManager;
    MockMarketplace public mockMarketplace;

    address public buyer;
    address public seller;
    address public nftContract;

    event EscrowCreatedMock(
        uint256 escrowId, address buyer, address seller, uint256 amount, AssetTypes.AssetType assetType
    );
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
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        nftContract = makeAddr("nftContract");

        mockNFTMarketplace = new MockNFTMarketplace();
        mockNFTRevert = new MockNFTRevert();
        mockEscrowManager = new MockEscrowManager();
        mockMarketplace = new MockMarketplace();

        vm.deal(buyer, 10 ether);
        vm.deal(seller, 10 ether);
    }

    // ============ MockNFTMarketplace Tests ============

    function test_MockNFTMarketplace_ExecutePurchase() public {
        uint256 tokenId = 1;
        uint256 quantity = 1;

        assertFalse(mockNFTMarketplace.executePurchaseCalled());
        assertEq(mockNFTMarketplace.lastBuyer(), address(0));
        assertEq(mockNFTMarketplace.lastSeller(), address(0));

        vm.prank(buyer);
        mockNFTMarketplace.executePurchase{value: 1 ether}(
            buyer, seller, nftContract, tokenId, quantity, AssetTypes.TokenStandard.ERC721
        );

        assertTrue(mockNFTMarketplace.executePurchaseCalled());
        assertEq(mockNFTMarketplace.lastBuyer(), buyer);
        assertEq(mockNFTMarketplace.lastSeller(), seller);
    }

    function test_MockNFTMarketplace_CalculatePaymentDistribution() public view {
        uint256 salePrice = 1 ether;

        (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet, address royaltyReceiver) =
            mockNFTMarketplace.calculatePaymentDistribution(nftContract, 1, salePrice);

        assertEq(platformFee, 0);
        assertEq(royaltyFee, 0);
        assertEq(sellerNet, salePrice);
        assertEq(royaltyReceiver, address(0));
    }

    function test_MockNFTMarketplace_MarketplaceCore() public view {
        assertEq(mockNFTMarketplace.marketplaceCore(), address(0));
    }

    function test_MockNFTMarketplace_PlatformFeeBps() public view {
        assertEq(mockNFTMarketplace.platformFeeBps(), 250);
    }

    // ============ MockNFTRevert Tests ============

    function test_MockNFTRevert_RoyaltyInfoReverts() public {
        vm.expectRevert("Royalty error");
        mockNFTRevert.royaltyInfo(1, 1 ether);
    }

    function test_MockNFTRevert_SupportsInterface_ERC2981() public view {
        // ERC2981 interface ID
        bytes4 erc2981InterfaceId = 0x2a55205a;
        assertTrue(mockNFTRevert.supportsInterface(erc2981InterfaceId));
    }

    function test_MockNFTRevert_SupportsInterface_ERC165() public view {
        // ERC165 interface ID
        bytes4 erc165InterfaceId = 0x01ffc9a7;
        assertTrue(mockNFTRevert.supportsInterface(erc165InterfaceId));
    }

    function test_MockNFTRevert_SupportsInterface_UnsupportedInterface() public view {
        // Random interface ID
        bytes4 randomInterfaceId = 0xffffffff;
        assertFalse(mockNFTRevert.supportsInterface(randomInterfaceId));
    }

    // ============ MockEscrowManager Tests ============

    function test_MockEscrowManager_CreateEscrow() public {
        uint256 amount = 1 ether;
        uint256 duration = 7 days;
        bytes32 assetHash = keccak256("asset1");
        string memory metadataURI = "ipfs://QmTest";

        assertEq(mockEscrowManager.escrowCounter(), 0);

        vm.expectEmit(true, true, true, true);
        emit EscrowCreatedMock(1, buyer, seller, amount, AssetTypes.AssetType.SocialMediaTwitter);

        vm.prank(buyer);
        uint256 escrowId = mockEscrowManager.createEscrow{value: amount}(
            buyer, seller, AssetTypes.AssetType.SocialMediaTwitter, duration, assetHash, metadataURI
        );

        assertEq(escrowId, 1);
        assertEq(mockEscrowManager.escrowCounter(), 1);

        // Verify escrow data
        IEscrowManager.Escrow memory escrow = mockEscrowManager.getEscrow(escrowId);
        assertEq(escrow.buyer, buyer);
        assertEq(escrow.seller, seller);
        assertEq(escrow.amount, amount);
        assertEq(escrow.paymentToken, address(0));
        assertEq(uint8(escrow.assetType), uint8(AssetTypes.AssetType.SocialMediaTwitter));
        assertEq(uint8(escrow.state), uint8(AssetTypes.EscrowState.Active));
        assertEq(escrow.createdAt, block.timestamp);
        assertEq(escrow.releaseTime, block.timestamp + duration);
        assertEq(escrow.verificationDeadline, block.timestamp + duration);
        assertEq(escrow.disputeDeadline, block.timestamp + duration + 7 days);
        assertFalse(escrow.buyerConfirmed);
        assertFalse(escrow.sellerDelivered);
        assertEq(escrow.assetHash, assetHash);
    }

    function test_MockEscrowManager_GetEscrow() public {
        uint256 amount = 0.5 ether;

        vm.prank(buyer);
        uint256 escrowId = mockEscrowManager.createEscrow{value: amount}(
            buyer, seller, AssetTypes.AssetType.SocialMediaYouTube, 3 days, keccak256("test"), "ipfs://QmTest2"
        );

        IEscrowManager.Escrow memory escrow = mockEscrowManager.getEscrow(escrowId);
        assertEq(escrow.buyer, buyer);
        assertEq(escrow.amount, amount);
    }

    function test_MockEscrowManager_MarkAssetDelivered_Reverts() public {
        vm.expectRevert("Not implemented");
        mockEscrowManager.markAssetDelivered(1);
    }

    function test_MockEscrowManager_ConfirmAssetReceived_Reverts() public {
        vm.expectRevert("Not implemented");
        mockEscrowManager.confirmAssetReceived(1);
    }

    function test_MockEscrowManager_ReleaseEscrow_Reverts() public {
        vm.expectRevert("Not implemented");
        mockEscrowManager.releaseEscrow(1);
    }

    function test_MockEscrowManager_CancelEscrow_Reverts() public {
        vm.expectRevert("Not implemented");
        mockEscrowManager.cancelEscrow(1);
    }

    function test_MockEscrowManager_OpenDispute_Reverts() public {
        vm.expectRevert("Not implemented");
        mockEscrowManager.openDispute(1, "Test dispute");
    }

    function test_MockEscrowManager_ResolveDispute_Reverts() public {
        vm.expectRevert("Not implemented");
        mockEscrowManager.resolveDispute(1, buyer, 1 ether);
    }

    function test_MockEscrowManager_GetBuyerEscrows_Reverts() public {
        vm.expectRevert("Not implemented");
        mockEscrowManager.getBuyerEscrows(buyer);
    }

    function test_MockEscrowManager_GetSellerEscrows_Reverts() public {
        vm.expectRevert("Not implemented");
        mockEscrowManager.getSellerEscrows(seller);
    }

    function test_MockEscrowManager_PlatformFeeBps_Reverts() public {
        vm.expectRevert("Not implemented");
        mockEscrowManager.platformFeeBps();
    }

    // ============ MockMarketplace Tests ============

    function test_MockMarketplace_CreateListing() public {
        uint256 price = 1 ether;
        bytes32 assetHash = keccak256("listing1");
        string memory metadataURI = "ipfs://QmListing1";

        assertEq(mockMarketplace.listingCounter(), 0);

        vm.prank(seller);
        uint256 listingId = mockMarketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaTwitter, price, assetHash, metadataURI
        );

        assertEq(listingId, 1);
        assertEq(mockMarketplace.listingCounter(), 1);

        // Verify listing data
        IMarketplace.Listing memory listing = mockMarketplace.getListing(listingId);
        assertEq(listing.listingId, listingId);
        assertEq(listing.seller, seller);
        assertEq(uint8(listing.assetType), uint8(AssetTypes.AssetType.SocialMediaTwitter));
        assertEq(listing.price, price);
        assertEq(uint8(listing.status), uint8(AssetTypes.ListingStatus.Active));
        assertEq(listing.createdAt, block.timestamp);
        assertEq(listing.assetHash, assetHash);
        assertEq(listing.metadataURI, metadataURI);
    }

    function test_MockMarketplace_CreateNFTListingMock() public {
        uint256 tokenId = 123;
        uint256 quantity = 5;
        uint256 price = 2 ether;

        vm.prank(seller);
        uint256 listingId = mockMarketplace.createNFTListingMock(
            seller, nftContract, tokenId, quantity, price, AssetTypes.TokenStandard.ERC1155
        );

        assertEq(listingId, 1);

        // Verify listing
        IMarketplace.Listing memory listing = mockMarketplace.getListing(listingId);
        assertEq(listing.seller, seller);
        assertEq(listing.price, price);
        assertEq(uint8(listing.assetType), uint8(AssetTypes.AssetType.NFT1155));

        // Verify NFT details
        IMarketplace.NFTDetails memory nftDetails = mockMarketplace.getNFTDetails(listingId);
        assertEq(nftDetails.nftContract, nftContract);
        assertEq(nftDetails.tokenId, tokenId);
        assertEq(nftDetails.quantity, quantity);
        assertEq(uint8(nftDetails.standard), uint8(AssetTypes.TokenStandard.ERC1155));
    }

    function test_MockMarketplace_CreateNFTListingMock_ERC721() public {
        uint256 tokenId = 456;
        uint256 price = 3 ether;

        vm.prank(seller);
        uint256 listingId = mockMarketplace.createNFTListingMock(
            seller, nftContract, tokenId, 1, price, AssetTypes.TokenStandard.ERC721
        );

        IMarketplace.Listing memory listing = mockMarketplace.getListing(listingId);
        assertEq(uint8(listing.assetType), uint8(AssetTypes.AssetType.NFT721));
    }

    function test_MockMarketplace_GetListing() public {
        vm.prank(seller);
        uint256 listingId = mockMarketplace.createListing(
            seller, AssetTypes.AssetType.Domain, 0.5 ether, keccak256("domain"), "ipfs://QmDomain"
        );

        IMarketplace.Listing memory listing = mockMarketplace.getListing(listingId);
        assertEq(listing.listingId, listingId);
        assertEq(listing.price, 0.5 ether);
    }

    function test_MockMarketplace_GetNFTDetails() public {
        vm.prank(seller);
        uint256 listingId = mockMarketplace.createNFTListingMock(
            seller, nftContract, 789, 10, 1 ether, AssetTypes.TokenStandard.ERC1155
        );

        IMarketplace.NFTDetails memory details = mockMarketplace.getNFTDetails(listingId);
        assertEq(details.tokenId, 789);
        assertEq(details.quantity, 10);
    }

    function test_MockMarketplace_MarkListingAsSold() public {
        vm.prank(seller);
        uint256 listingId = mockMarketplace.createListing(
            seller, AssetTypes.AssetType.Website, 1 ether, keccak256("website"), "ipfs://QmWebsite"
        );

        IMarketplace.Listing memory listingBefore = mockMarketplace.getListing(listingId);
        assertEq(uint8(listingBefore.status), uint8(AssetTypes.ListingStatus.Active));

        mockMarketplace.markListingAsSold(listingId);

        IMarketplace.Listing memory listingAfter = mockMarketplace.getListing(listingId);
        assertEq(uint8(listingAfter.status), uint8(AssetTypes.ListingStatus.Sold));
    }

    function test_MockMarketplace_CancelListingMock() public {
        vm.prank(seller);
        uint256 listingId = mockMarketplace.createListing(
            seller, AssetTypes.AssetType.SocialMediaInstagram, 2 ether, keccak256("instagram"), "ipfs://QmInsta"
        );

        IMarketplace.Listing memory listingBefore = mockMarketplace.getListing(listingId);
        assertEq(uint8(listingBefore.status), uint8(AssetTypes.ListingStatus.Active));

        mockMarketplace.cancelListingMock(listingId);

        IMarketplace.Listing memory listingAfter = mockMarketplace.getListing(listingId);
        assertEq(uint8(listingAfter.status), uint8(AssetTypes.ListingStatus.Cancelled));
    }

    function test_MockMarketplace_CreateNFTListing_Reverts() public {
        vm.expectRevert("Not implemented");
        mockMarketplace.createNFTListing(address(0), 1, 1, 1 ether, AssetTypes.TokenStandard.ERC721);
    }

    function test_MockMarketplace_CreateOffChainListing_Reverts() public {
        vm.expectRevert("Not implemented");
        mockMarketplace.createOffChainListing(AssetTypes.AssetType.SocialMediaTwitter, 1 ether, bytes32(0), "");
    }

    function test_MockMarketplace_PurchaseAsset_Reverts() public {
        vm.expectRevert("Not implemented");
        mockMarketplace.purchaseAsset{value: 1 ether}(1);
    }

    function test_MockMarketplace_CancelListing_Reverts() public {
        vm.expectRevert("Not implemented");
        mockMarketplace.cancelListing(1);
    }

    function test_MockMarketplace_UpdatePrice_Reverts() public {
        vm.expectRevert("Not implemented");
        mockMarketplace.updatePrice(1, 1 ether);
    }

    function test_MockMarketplace_GetSellerListings_Reverts() public {
        vm.expectRevert("Not implemented");
        mockMarketplace.getSellerListings(seller);
    }

    function test_MockMarketplace_IsNFTListing_Reverts() public {
        vm.expectRevert("Not implemented");
        mockMarketplace.isNFTListing(1);
    }
}

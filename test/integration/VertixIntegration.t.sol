// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployVertix} from "../../script/DeployVertix.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {AssetTypes} from "../../src/libraries/AssetTypes.sol";
import {VertixNFT721} from "../../src/nft/VertixNFT721.sol";
import {VertixNFT1155} from "../../src/nft/VertixNFT1155.sol";
import {IReputationManager} from "../../src/interfaces/IReputationManager.sol";

contract VertixIntegrationTest is Test {
    DeployVertix.DeployedContracts public contracts;

    address public admin;
    address public feeCollector;
    address public seller;
    address public buyer;
    address public bidder1;
    address public bidder2;
    address public verifier;

    uint256 constant LISTING_PRICE = 1 ether;
    uint256 constant OFFER_AMOUNT = 0.8 ether;
    uint256 constant AUCTION_RESERVE = 0.5 ether;

    event ListingSold(uint256 indexed listingId, address indexed buyer, address indexed seller, uint256 price);
    event OfferAccepted(
        uint256 indexed offerId, uint256 indexed listingId, address indexed seller, address buyer, uint256 amount
    );

    function setUp() public {
        DeployVertix deployer = new DeployVertix();
        contracts = deployer.run();

        HelperConfig helperConfig = new HelperConfig();
        (admin, feeCollector,,) = helperConfig.activeNetworkConfig();

        seller = makeAddr("seller");
        buyer = makeAddr("buyer");
        bidder1 = makeAddr("bidder1");
        bidder2 = makeAddr("bidder2");
        verifier = makeAddr("verifier");

        vm.deal(seller, 100 ether);
        vm.deal(buyer, 100 ether);
        vm.deal(bidder1, 100 ether);
        vm.deal(bidder2, 100 ether);

        _setupAuthorizations();
    }

    function _setupAuthorizations() internal {
        vm.startPrank(admin);

        contracts.roleManager.grantRole(contracts.roleManager.DEFAULT_ADMIN_ROLE(), admin);
        contracts.roleManager.grantRole(contracts.roleManager.ARBITRATOR_ROLE(), admin);

        contracts.escrowManager.addAuthorizedMarketplace(address(contracts.marketplaceCore));
        contracts.escrowManager.addAuthorizedMarketplace(address(contracts.offerManager));
        contracts.escrowManager.addAuthorizedMarketplace(address(contracts.auctionManager));

        contracts.marketplaceCore.addAuthorizedCaller(address(contracts.offerManager));

        contracts.verificationRegistry.addVerifier(admin);
        contracts.verificationRegistry.addVerifier(verifier);

        contracts.reputationManager.addAuthorizedContract(admin);
        contracts.reputationManager.addAuthorizedContract(address(contracts.escrowManager));
        contracts.reputationManager.addAuthorizedContract(address(contracts.marketplaceCore));

        vm.stopPrank();
    }

    function test_Integration_CompleteNFTPurchaseFlow() public {
        vm.startPrank(seller);

        VertixNFT721 collection = VertixNFT721(
            contracts.nftFactory.createCollection721("Integration Test Collection", "ITC", seller, 1000, 500, "")
        );

        uint256 tokenId = collection.mint(seller, "ipfs://token1");

        collection.setApprovalForAll(address(contracts.marketplaceCore), true);
        collection.setApprovalForAll(address(contracts.nftMarketplace), true);

        uint256 listingId = contracts.marketplaceCore.createNFTListing(
            address(collection), tokenId, 1, LISTING_PRICE, AssetTypes.TokenStandard.ERC721
        );

        vm.stopPrank();

        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(buyer);
        vm.expectEmit(true, true, true, true);
        emit ListingSold(listingId, buyer, seller, LISTING_PRICE);
        contracts.marketplaceCore.purchaseAsset{value: LISTING_PRICE}(listingId);

        assertEq(collection.ownerOf(tokenId), buyer);
        assertGt(seller.balance, sellerBalanceBefore);

        assertGt(address(contracts.feeDistributor).balance, 0);

        (,,,, AssetTypes.ListingStatus status,,,) = contracts.marketplaceCore.listings(listingId);
        assertEq(uint8(status), uint8(AssetTypes.ListingStatus.Sold));
    }

    function test_Integration_OfferAcceptanceFlow() public {
        vm.startPrank(seller);

        VertixNFT721 collection =
            VertixNFT721(contracts.nftFactory.createCollection721("Offer Test", "OFR", seller, 1000, 500, ""));

        uint256 tokenId = collection.mint(seller, "ipfs://offer-token");
        collection.setApprovalForAll(address(contracts.marketplaceCore), true);
        collection.setApprovalForAll(address(contracts.nftMarketplace), true);
        collection.setApprovalForAll(address(contracts.offerManager), true);

        uint256 listingId = contracts.marketplaceCore.createNFTListing(
            address(collection), tokenId, 1, LISTING_PRICE, AssetTypes.TokenStandard.ERC721
        );

        vm.stopPrank();

        uint256 buyerBalanceBefore = buyer.balance;

        vm.prank(buyer);
        uint256 offerId = contracts.offerManager.makeOffer{value: OFFER_AMOUNT}(listingId, 7 days);

        assertEq(offerId, 1);
        assertTrue(contracts.offerManager.isOfferActive(offerId));

        vm.prank(seller);
        vm.expectEmit(true, true, true, true);
        emit OfferAccepted(offerId, listingId, seller, buyer, OFFER_AMOUNT);
        contracts.offerManager.acceptOffer(offerId);

        assertEq(collection.ownerOf(tokenId), buyer);
        assertTrue(contracts.offerManager.getOffer(offerId).accepted);
        assertLt(buyer.balance, buyerBalanceBefore);
    }

    function test_Integration_EscrowCompleteFlow() public {
        bytes32 assetHash = keccak256("youtube-channel-verified");
        string memory metadataURI = "ipfs://QmYouTubeChannel";

        vm.prank(seller);
        uint256 listingId = contracts.marketplaceCore.createOffChainListing(
            AssetTypes.AssetType.SocialMediaYouTube, LISTING_PRICE, assetHash, metadataURI
        );

        uint256 buyerBalanceBefore = buyer.balance;

        vm.prank(buyer);
        contracts.marketplaceCore.purchaseAsset{value: LISTING_PRICE}(listingId);

        uint256 escrowId = 1;

        vm.prank(seller);
        contracts.escrowManager.markAssetDelivered(escrowId);

        (,,,,,,,,,,, bool sellerDelivered,) = contracts.escrowManager.escrows(escrowId);
        assertTrue(sellerDelivered);

        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(buyer);
        contracts.escrowManager.confirmAssetReceived(escrowId);

        // confirmAssetReceived automatically releases the escrow
        (,,,,, AssetTypes.EscrowState state,,,,,,,) = contracts.escrowManager.escrows(escrowId);
        assertEq(uint8(state), uint8(AssetTypes.EscrowState.Completed));

        assertGt(seller.balance, sellerBalanceBefore);
        assertLt(buyer.balance, buyerBalanceBefore);
    }

    function test_Integration_DisputeResolutionFlow() public {
        bytes32 assetHash = keccak256("disputed-website");

        vm.prank(seller);
        uint256 listingId = contracts.marketplaceCore.createOffChainListing(
            AssetTypes.AssetType.Website, LISTING_PRICE, assetHash, "ipfs://QmWebsite"
        );

        vm.prank(buyer);
        contracts.marketplaceCore.purchaseAsset{value: LISTING_PRICE}(listingId);

        uint256 escrowId = 1;

        vm.prank(seller);
        contracts.escrowManager.markAssetDelivered(escrowId);

        vm.prank(buyer);
        contracts.escrowManager.openDispute(escrowId, "Asset not as described");

        (,,,,, AssetTypes.EscrowState state,,,,,,,) = contracts.escrowManager.escrows(escrowId);
        assertEq(uint8(state), uint8(AssetTypes.EscrowState.Disputed));

        uint256 buyerBalanceBefore = buyer.balance;

        vm.prank(admin);
        contracts.escrowManager.resolveDispute(escrowId, buyer, LISTING_PRICE);

        assertGt(buyer.balance, buyerBalanceBefore);
    }

    function test_Integration_AuctionCompleteFlow() public {
        vm.startPrank(seller);

        VertixNFT721 collection =
            VertixNFT721(contracts.nftFactory.createCollection721("Auction NFT", "AUCT", seller, 1000, 500, ""));

        uint256 tokenId = collection.mint(seller, "ipfs://auction-nft");
        collection.setApprovalForAll(address(contracts.auctionManager), true);

        uint256 auctionId = contracts.auctionManager.createAuction(
            AssetTypes.AssetType.NFT721,
            address(collection),
            tokenId,
            1,
            AUCTION_RESERVE,
            1 days,
            500,
            AssetTypes.TokenStandard.ERC721,
            bytes32(0),
            ""
        );

        vm.stopPrank();

        vm.prank(bidder1);
        contracts.auctionManager.placeBid{value: 0.6 ether}(auctionId);

        vm.prank(bidder2);
        contracts.auctionManager.placeBid{value: 0.8 ether}(auctionId);

        vm.prank(bidder1);
        contracts.auctionManager.placeBid{value: 1.0 ether}(auctionId);

        assertTrue(contracts.auctionManager.isAuctionActive(auctionId));

        vm.warp(block.timestamp + 1 days + 1);

        assertTrue(contracts.auctionManager.hasAuctionEnded(auctionId));

        uint256 sellerBalanceBefore = seller.balance;

        contracts.auctionManager.endAuction(auctionId);

        assertEq(collection.ownerOf(tokenId), bidder1);
        assertGt(seller.balance, sellerBalanceBefore);
    }

    function test_Integration_VerificationAndReputationFlow() public {
        vm.prank(admin);
        contracts.verificationRegistry.addVerification(
            seller,
            AssetTypes.AssetType.SocialMediaTwitter,
            keccak256("twitter-verified"),
            block.timestamp + 365 days,
            "ipfs://QmTwitter"
        );

        assertTrue(contracts.verificationRegistry.isVerified(seller, AssetTypes.AssetType.SocialMediaTwitter));

        vm.prank(admin);
        contracts.reputationManager.updateReputation(seller, IReputationManager.ReputationAction.VerifiedAsset);

        int256 score = contracts.reputationManager.getReputationScore(seller);
        assertEq(score, 120);
        assertTrue(contracts.reputationManager.isGoodStanding(seller));
    }

    function test_Integration_UserVerificationChallengeFlow() public {
        vm.prank(seller);
        uint256 verificationId = contracts.verificationRegistry.submitUserVerification(
            AssetTypes.AssetType.SocialMediaInstagram,
            keccak256("instagram-proof"),
            block.timestamp + 365 days,
            "ipfs://QmInstagram"
        );

        assertTrue(contracts.verificationRegistry.pendingVerifications(verificationId));

        address challenger = makeAddr("challenger");
        vm.deal(challenger, 1 ether);

        vm.prank(challenger);
        contracts.verificationRegistry.challengeVerification{value: contracts.verificationRegistry.CHALLENGE_STAKE()}(
            verificationId, "Fake account"
        );

        vm.prank(admin);
        contracts.verificationRegistry.resolveChallenge(verificationId, false);

        vm.warp(block.timestamp + 8 days);

        contracts.verificationRegistry.finalizeUserVerification(verificationId);

        assertTrue(contracts.verificationRegistry.isVerified(seller, AssetTypes.AssetType.SocialMediaInstagram));
    }

    function test_Integration_MultipleOffersCompetition() public {
        vm.prank(seller);
        uint256 listingId = contracts.marketplaceCore.createOffChainListing(
            AssetTypes.AssetType.Domain, 2 ether, keccak256("premium.eth"), "ipfs://QmDomain"
        );

        address buyer2 = makeAddr("buyer2");
        address buyer3 = makeAddr("buyer3");
        vm.deal(buyer2, 10 ether);
        vm.deal(buyer3, 10 ether);

        vm.prank(buyer);
        uint256 offer1 = contracts.offerManager.makeOffer{value: 1.5 ether}(listingId, 7 days);

        vm.prank(buyer2);
        uint256 offer2 = contracts.offerManager.makeOffer{value: 1.8 ether}(listingId, 7 days);

        vm.prank(buyer3);
        uint256 offer3 = contracts.offerManager.makeOffer{value: 2.2 ether}(listingId, 7 days);

        assertTrue(contracts.offerManager.isOfferActive(offer1));
        assertTrue(contracts.offerManager.isOfferActive(offer2));
        assertTrue(contracts.offerManager.isOfferActive(offer3));

        vm.prank(seller);
        contracts.offerManager.acceptOffer(offer3);

        assertTrue(contracts.offerManager.getOffer(offer3).accepted);
        assertFalse(contracts.offerManager.isOfferActive(offer1));
        assertFalse(contracts.offerManager.isOfferActive(offer2));
    }

    function test_Integration_NFTCollectionWithRoyalties() public {
        vm.startPrank(seller);

        address royaltyReceiver = seller;

        VertixNFT721 collection =
            VertixNFT721(contracts.nftFactory.createCollection721("Royalty NFT", "RYL", royaltyReceiver, 1000, 100, ""));

        uint256 tokenId = collection.mint(seller, "ipfs://royalty-nft");
        collection.setApprovalForAll(address(contracts.marketplaceCore), true);
        collection.setApprovalForAll(address(contracts.nftMarketplace), true);

        uint256 listingId = contracts.marketplaceCore.createNFTListing(
            address(collection), tokenId, 1, 10 ether, AssetTypes.TokenStandard.ERC721
        );

        vm.stopPrank();

        uint256 royaltyReceiverBalanceBefore = royaltyReceiver.balance;

        vm.prank(buyer);
        contracts.marketplaceCore.purchaseAsset{value: 10 ether}(listingId);

        assertGt(royaltyReceiver.balance, royaltyReceiverBalanceBefore);
        assertEq(collection.ownerOf(tokenId), buyer);
    }

    function test_Integration_CancelEscrowBeforeDelivery() public {
        vm.prank(seller);
        uint256 listingId = contracts.marketplaceCore.createOffChainListing(
            AssetTypes.AssetType.MobileApp, LISTING_PRICE, keccak256("mobile-app"), "ipfs://QmApp"
        );

        vm.prank(buyer);
        contracts.marketplaceCore.purchaseAsset{value: LISTING_PRICE}(listingId);

        uint256 escrowId = 1;
        uint256 buyerBalanceBefore = buyer.balance;

        vm.prank(buyer);
        contracts.escrowManager.cancelEscrow(escrowId);

        assertGt(buyer.balance, buyerBalanceBefore);

        (,,,,, AssetTypes.EscrowState state,,,,,,,) = contracts.escrowManager.escrows(escrowId);
        assertEq(uint8(state), uint8(AssetTypes.EscrowState.Cancelled));
    }

    function test_Integration_MultipleNFTsInSameCollection() public {
        vm.startPrank(seller);

        VertixNFT721 collection =
            VertixNFT721(contracts.nftFactory.createCollection721("Multi NFT", "MULTI", seller, 1000, 500, ""));

        uint256 tokenId1 = collection.mint(seller, "ipfs://token1");
        uint256 tokenId2 = collection.mint(seller, "ipfs://token2");
        uint256 tokenId3 = collection.mint(seller, "ipfs://token3");

        collection.setApprovalForAll(address(contracts.marketplaceCore), true);
        collection.setApprovalForAll(address(contracts.nftMarketplace), true);

        uint256 listing1 = contracts.marketplaceCore.createNFTListing(
            address(collection), tokenId1, 1, 1 ether, AssetTypes.TokenStandard.ERC721
        );

        uint256 listing2 = contracts.marketplaceCore.createNFTListing(
            address(collection), tokenId2, 1, 2 ether, AssetTypes.TokenStandard.ERC721
        );

        uint256 listing3 = contracts.marketplaceCore.createNFTListing(
            address(collection), tokenId3, 1, 3 ether, AssetTypes.TokenStandard.ERC721
        );

        vm.stopPrank();

        vm.prank(buyer);
        contracts.marketplaceCore.purchaseAsset{value: 2 ether}(listing2);

        assertEq(collection.ownerOf(tokenId1), seller);
        assertEq(collection.ownerOf(tokenId2), buyer);
        assertEq(collection.ownerOf(tokenId3), seller);
    }

    function test_Integration_ERC1155_CompleteFlow() public {
        vm.startPrank(seller);

        // Create ERC1155 collection
        address collection1155 = contracts.nftFactory.createCollection1155(
            "Integration Test 1155", "IT1155", "ipfs://base-uri/", seller, 1000
        );

        // Create a new token type with 10 copies
        uint256 quantity = 10;
        uint256 tokenId = VertixNFT1155(collection1155).create(
            quantity,
            "ipfs://token1",
            100 // max supply
        );

        // Approve marketplace contracts
        VertixNFT1155(collection1155).setApprovalForAll(address(contracts.marketplaceCore), true);
        VertixNFT1155(collection1155).setApprovalForAll(address(contracts.nftMarketplace), true);

        // Create listing for 5 copies
        uint256 listingId = contracts.marketplaceCore.createNFTListing(
            collection1155, tokenId, 5, 2 ether, AssetTypes.TokenStandard.ERC1155
        );

        vm.stopPrank();

        // Verify seller has 10 tokens
        assertEq(VertixNFT1155(collection1155).balanceOf(seller, tokenId), 10);
        assertEq(VertixNFT1155(collection1155).balanceOf(buyer, tokenId), 0);

        uint256 sellerBalanceBefore = seller.balance;

        // Buyer purchases 5 copies
        vm.prank(buyer);
        contracts.marketplaceCore.purchaseAsset{value: 2 ether}(listingId);

        // Verify balances updated correctly
        assertEq(VertixNFT1155(collection1155).balanceOf(seller, tokenId), 5);
        assertEq(VertixNFT1155(collection1155).balanceOf(buyer, tokenId), 5);

        // Verify seller received payment
        assertGt(seller.balance, sellerBalanceBefore);

        // Verify listing is marked as sold
        (,,,, AssetTypes.ListingStatus status,,,) = contracts.marketplaceCore.listings(listingId);
        assertEq(uint8(status), uint8(AssetTypes.ListingStatus.Sold));
    }
}

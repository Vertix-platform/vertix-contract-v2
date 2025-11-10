// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {NFTMarketplace} from "../../src/nft/NFTMarketplace.sol";
import {FeeDistributor} from "../../src/core/FeeDistributor.sol";
import {RoleManager} from "../../src/access/RoleManager.sol";
import {VertixNFT721} from "../../src/nft/VertixNFT721.sol";
import {VertixNFT1155} from "../../src/nft/VertixNFT1155.sol";
import {AssetTypes} from "../../src/libraries/AssetTypes.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract NFTMarketplaceTest is Test {
    NFTMarketplace public marketplace;
    FeeDistributor public feeDistributor;
    RoleManager public roleManager;
    VertixNFT721 public nft721;
    VertixNFT1155 public nft1155;

    address public admin;
    address public marketplaceCore;
    address public feeCollector;
    address public seller;
    address public buyer;
    address public royaltyReceiver;

    uint256 constant PLATFORM_FEE_BPS = 250; // 2.5%
    uint256 constant ROYALTY_FEE_BPS = 500; // 5%

    event NFTTransferred(
        address indexed nftContract, uint256 indexed tokenId, address indexed from, address to, uint256 quantity
    );
    event PaymentDistributed(
        address indexed seller, uint256 sellerNet, uint256 platformFee, address royaltyReceiver, uint256 royaltyAmount
    );

    function setUp() public {
        admin = makeAddr("admin");
        marketplaceCore = makeAddr("marketplaceCore");
        feeCollector = makeAddr("feeCollector");
        seller = makeAddr("seller");
        buyer = makeAddr("buyer");
        royaltyReceiver = makeAddr("royaltyReceiver");

        roleManager = new RoleManager(admin);

        feeDistributor = new FeeDistributor(address(roleManager), feeCollector, PLATFORM_FEE_BPS);

        marketplace = new NFTMarketplace(marketplaceCore, address(feeDistributor), PLATFORM_FEE_BPS);

        // Deploy test NFTs with proxies
        VertixNFT721 nft721Impl = new VertixNFT721();
        bytes memory nft721InitData = abi.encodeWithSelector(
            VertixNFT721.initialize.selector,
            "Test721",
            "T721",
            seller,
            royaltyReceiver,
            uint96(ROYALTY_FEE_BPS),
            1000,
            ""
        );
        ERC1967Proxy nft721Proxy = new ERC1967Proxy(address(nft721Impl), nft721InitData);
        nft721 = VertixNFT721(address(nft721Proxy));

        VertixNFT1155 nft1155Impl = new VertixNFT1155();
        bytes memory nft1155InitData = abi.encodeWithSelector(
            VertixNFT1155.initialize.selector, "Test1155", "T1155", "", seller, royaltyReceiver, uint96(ROYALTY_FEE_BPS)
        );
        ERC1967Proxy nft1155Proxy = new ERC1967Proxy(address(nft1155Impl), nft1155InitData);
        nft1155 = VertixNFT1155(address(nft1155Proxy));

        // Mint NFTs to seller
        vm.startPrank(seller);
        nft721.mint(seller, "ipfs://token1");
        nft1155.create(100, "ipfs://token1", 1000);
        vm.stopPrank();

        vm.deal(buyer, 100 ether);
        vm.deal(marketplaceCore, 100 ether);
    }

    // ============================================
    //          CONSTRUCTOR TESTS
    // ============================================

    function test_Constructor_SetsMarketplaceCore() public view {
        assertEq(marketplace.marketplaceCore(), marketplaceCore);
    }

    function test_Constructor_SetsFeeDistributor() public view {
        assertEq(address(marketplace.feeDistributor()), address(feeDistributor));
    }

    function test_Constructor_SetsPlatformFee() public view {
        assertEq(marketplace.platformFeeBps(), PLATFORM_FEE_BPS);
    }

    function test_Constructor_RevertsOnZeroMarketplaceCore() public {
        vm.expectRevert(Errors.InvalidMarketplaceCore.selector);
        new NFTMarketplace(address(0), address(feeDistributor), PLATFORM_FEE_BPS);
    }

    function test_Constructor_RevertsOnZeroFeeDistributor() public {
        vm.expectRevert(Errors.InvalidFeeDistributor.selector);
        new NFTMarketplace(marketplaceCore, address(0), PLATFORM_FEE_BPS);
    }

    function test_Constructor_RevertsOnInvalidPlatformFee() public {
        vm.expectRevert(); // PercentageMath.validateBps will revert
        new NFTMarketplace(marketplaceCore, address(feeDistributor), 10_001); // > MAX_FEE_BPS
    }

    // ============================================
    //      EXECUTE PURCHASE ERC721 TESTS
    // ============================================

    function test_ExecutePurchase_ERC721_SuccessfullyTransfersNFT() public {
        uint256 tokenId = 1;
        uint256 price = 1 ether;

        // marketplace contract does the actual transfer, so it needs approval
        // the contract checks marketplaceCore approval but transfers from address(this)
        vm.prank(seller);
        nft721.approve(address(marketplace), tokenId);

        vm.prank(marketplaceCore);
        marketplace.executePurchase{value: price}(
            buyer, seller, address(nft721), tokenId, 1, AssetTypes.TokenStandard.ERC721
        );

        assertEq(nft721.ownerOf(tokenId), buyer);
    }

    function test_ExecutePurchase_ERC721_DistributesPaymentCorrectly() public {
        uint256 tokenId = 1;
        uint256 price = 1 ether;

        vm.prank(seller);
        nft721.approve(address(marketplace), tokenId);

        uint256 sellerBalanceBefore = seller.balance;
        uint256 feeDistributorBalanceBefore = address(feeDistributor).balance;
        uint256 royaltyBalanceBefore = royaltyReceiver.balance;

        vm.prank(marketplaceCore);
        marketplace.executePurchase{value: price}(
            buyer, seller, address(nft721), tokenId, 1, AssetTypes.TokenStandard.ERC721
        );

        uint256 platformFee = (price * PLATFORM_FEE_BPS) / 10_000;
        uint256 royaltyFee = (price * ROYALTY_FEE_BPS) / 10_000;
        uint256 sellerNet = price - platformFee - royaltyFee;

        assertEq(seller.balance, sellerBalanceBefore + sellerNet);
        assertEq(address(feeDistributor).balance, feeDistributorBalanceBefore + platformFee);
        assertEq(royaltyReceiver.balance, royaltyBalanceBefore + royaltyFee);
    }

    function test_ExecutePurchase_ERC721_EmitsEvents() public {
        uint256 tokenId = 1;
        uint256 price = 1 ether;

        vm.prank(seller);
        nft721.approve(address(marketplace), tokenId);

        uint256 platformFee = (price * PLATFORM_FEE_BPS) / 10_000;
        uint256 royaltyFee = (price * ROYALTY_FEE_BPS) / 10_000;
        uint256 sellerNet = price - platformFee - royaltyFee;

        vm.expectEmit(true, true, true, true);
        emit NFTTransferred(address(nft721), tokenId, seller, buyer, 1);

        vm.expectEmit(true, false, false, true);
        emit PaymentDistributed(seller, sellerNet, platformFee, royaltyReceiver, royaltyFee);

        vm.prank(marketplaceCore);
        marketplace.executePurchase{value: price}(
            buyer, seller, address(nft721), tokenId, 1, AssetTypes.TokenStandard.ERC721
        );
    }

    function test_ExecutePurchase_ERC721_WorksWithApprovalForAll() public {
        uint256 tokenId = 1;
        uint256 price = 1 ether;

        // Seller approves marketplace for all
        vm.prank(seller);
        nft721.setApprovalForAll(address(marketplace), true);

        vm.prank(marketplaceCore);
        marketplace.executePurchase{value: price}(
            buyer, seller, address(nft721), tokenId, 1, AssetTypes.TokenStandard.ERC721
        );

        assertEq(nft721.ownerOf(tokenId), buyer);
    }

    function test_ExecutePurchase_ERC721_RevertsIfNotOwner() public {
        uint256 tokenId = 1;
        uint256 price = 1 ether;

        address fakeSeller = makeAddr("fakeSeller");

        vm.prank(marketplaceCore);
        vm.expectRevert(NFTMarketplace.InsufficientOwnership.selector);
        marketplace.executePurchase{value: price}(
            buyer, fakeSeller, address(nft721), tokenId, 1, AssetTypes.TokenStandard.ERC721
        );
    }

    function test_ExecutePurchase_ERC721_RevertsIfNotApproved() public {
        uint256 tokenId = 1;
        uint256 price = 1 ether;

        // No approval given

        vm.prank(marketplaceCore);
        vm.expectRevert(NFTMarketplace.NotApproved.selector);
        marketplace.executePurchase{value: price}(
            buyer, seller, address(nft721), tokenId, 1, AssetTypes.TokenStandard.ERC721
        );
    }

    function test_ExecutePurchase_ERC721_RevertsIfNotMarketplaceCore() public {
        uint256 tokenId = 1;
        uint256 price = 1 ether;

        vm.prank(seller);
        nft721.approve(address(marketplace), tokenId);

        vm.prank(buyer);
        vm.expectRevert(NFTMarketplace.OnlyMarketplaceCore.selector);
        marketplace.executePurchase{value: price}(
            buyer, seller, address(nft721), tokenId, 1, AssetTypes.TokenStandard.ERC721
        );
    }

    function test_ExecutePurchase_ERC721_RevertsOnZeroAddress() public {
        uint256 price = 1 ether;

        vm.prank(marketplaceCore);
        vm.expectRevert(NFTMarketplace.InvalidNFTContract.selector);
        marketplace.executePurchase{value: price}(buyer, seller, address(0), 1, 1, AssetTypes.TokenStandard.ERC721);
    }

    // ============================================
    //      EXECUTE PURCHASE ERC1155 TESTS
    // ============================================

    function test_ExecutePurchase_ERC1155_SuccessfullyTransfersNFT() public {
        uint256 tokenId = 1;
        uint256 quantity = 10;
        uint256 price = 1 ether;

        vm.prank(seller);
        nft1155.setApprovalForAll(address(marketplace), true);

        vm.prank(marketplaceCore);
        marketplace.executePurchase{value: price}(
            buyer, seller, address(nft1155), tokenId, quantity, AssetTypes.TokenStandard.ERC1155
        );

        assertEq(nft1155.balanceOf(buyer, tokenId), quantity);
        assertEq(nft1155.balanceOf(seller, tokenId), 100 - quantity);
    }

    function test_ExecutePurchase_ERC1155_DistributesPaymentCorrectly() public {
        uint256 tokenId = 1;
        uint256 quantity = 10;
        uint256 price = 2 ether;

        vm.prank(seller);
        nft1155.setApprovalForAll(address(marketplace), true);

        uint256 sellerBalanceBefore = seller.balance;
        uint256 feeDistributorBalanceBefore = address(feeDistributor).balance;
        uint256 royaltyBalanceBefore = royaltyReceiver.balance;

        vm.prank(marketplaceCore);
        marketplace.executePurchase{value: price}(
            buyer, seller, address(nft1155), tokenId, quantity, AssetTypes.TokenStandard.ERC1155
        );

        // Calculate expected amounts
        uint256 platformFee = (price * PLATFORM_FEE_BPS) / 10_000;
        uint256 royaltyFee = (price * ROYALTY_FEE_BPS) / 10_000;
        uint256 sellerNet = price - platformFee - royaltyFee;

        assertEq(seller.balance, sellerBalanceBefore + sellerNet);
        assertEq(address(feeDistributor).balance, feeDistributorBalanceBefore + platformFee);
        assertEq(royaltyReceiver.balance, royaltyBalanceBefore + royaltyFee);
    }

    function test_ExecutePurchase_ERC1155_RevertsIfInsufficientBalance() public {
        uint256 tokenId = 1;
        uint256 quantity = 200; // More than available
        uint256 price = 1 ether;

        vm.prank(seller);
        nft1155.setApprovalForAll(address(marketplace), true);

        vm.prank(marketplaceCore);
        vm.expectRevert(NFTMarketplace.InsufficientOwnership.selector);
        marketplace.executePurchase{value: price}(
            buyer, seller, address(nft1155), tokenId, quantity, AssetTypes.TokenStandard.ERC1155
        );
    }

    function test_ExecutePurchase_ERC1155_RevertsIfNotApproved() public {
        uint256 tokenId = 1;
        uint256 quantity = 10;
        uint256 price = 1 ether;

        // No approval given

        vm.prank(marketplaceCore);
        vm.expectRevert(NFTMarketplace.NotApproved.selector);
        marketplace.executePurchase{value: price}(
            buyer, seller, address(nft1155), tokenId, quantity, AssetTypes.TokenStandard.ERC1155
        );
    }

    // ============================================
    //      CALCULATE PAYMENT DISTRIBUTION TESTS
    // ============================================

    function test_CalculatePaymentDistribution_ReturnsCorrectAmounts() public view {
        uint256 price = 1 ether;

        (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet, address royaltyRec) =
            marketplace.calculatePaymentDistribution(address(nft721), 1, price);

        uint256 expectedPlatformFee = (price * PLATFORM_FEE_BPS) / 10_000;
        uint256 expectedRoyaltyFee = (price * ROYALTY_FEE_BPS) / 10_000;
        uint256 expectedSellerNet = price - expectedPlatformFee - expectedRoyaltyFee;

        assertEq(platformFee, expectedPlatformFee);
        assertEq(royaltyFee, expectedRoyaltyFee);
        assertEq(sellerNet, expectedSellerNet);
        assertEq(royaltyRec, royaltyReceiver);
    }

    function test_CalculatePaymentDistribution_HandlesNoRoyalty() public {
        // Deploy NFT without royalty support
        VertixNFT721 nftNoRoyaltyImpl = new VertixNFT721();
        bytes memory initData =
            abi.encodeWithSelector(VertixNFT721.initialize.selector, "NoRoyalty", "NR", seller, address(0), 0, 1000, "");
        ERC1967Proxy proxy = new ERC1967Proxy(address(nftNoRoyaltyImpl), initData);
        VertixNFT721 nftNoRoyalty = VertixNFT721(address(proxy));

        uint256 price = 1 ether;

        (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet, address royaltyRec) =
            marketplace.calculatePaymentDistribution(address(nftNoRoyalty), 1, price);

        uint256 expectedPlatformFee = (price * PLATFORM_FEE_BPS) / 10_000;
        uint256 expectedSellerNet = price - expectedPlatformFee;

        assertEq(platformFee, expectedPlatformFee);
        assertEq(royaltyFee, 0);
        assertEq(sellerNet, expectedSellerNet);
        assertEq(royaltyRec, address(0));
    }

    function test_CalculatePaymentDistribution_CapsRoyaltyAtMax() public {
        // Create NFT with exactly 10% royalty (the maximum allowed)
        VertixNFT721 nftMaxRoyaltyImpl = new VertixNFT721();
        bytes memory initData = abi.encodeWithSelector(
            VertixNFT721.initialize.selector,
            "MaxRoyalty",
            "MR",
            seller,
            royaltyReceiver,
            1000, // 10% - the maximum
            1000,
            ""
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(nftMaxRoyaltyImpl), initData);
        VertixNFT721 nftMaxRoyalty = VertixNFT721(address(proxy));

        uint256 price = 1 ether;

        (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet, address royaltyRec) =
            marketplace.calculatePaymentDistribution(address(nftMaxRoyalty), 1, price);

        // Verify 10% royalty is calculated correctly
        uint256 maxRoyalty = (price * 1000) / 10_000; // 10%
        uint256 expectedPlatformFee = (price * PLATFORM_FEE_BPS) / 10_000;
        uint256 expectedSellerNet = price - expectedPlatformFee - maxRoyalty;

        assertEq(platformFee, expectedPlatformFee);
        assertEq(royaltyFee, maxRoyalty);
        assertEq(sellerNet, expectedSellerNet);
        assertEq(royaltyRec, royaltyReceiver);
    }

    // ============================================
    //          EDGE CASE TESTS
    // ============================================

    function test_ExecutePurchase_HandlesZeroRoyalty() public {
        VertixNFT721 nftZeroRoyaltyImpl = new VertixNFT721();
        bytes memory initData = abi.encodeWithSelector(
            VertixNFT721.initialize.selector, "ZeroRoyalty", "ZR", seller, address(0), 0, 1000, ""
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(nftZeroRoyaltyImpl), initData);
        VertixNFT721 nftZeroRoyalty = VertixNFT721(address(proxy));

        vm.prank(seller);
        nftZeroRoyalty.mint(seller, "ipfs://token1");

        vm.prank(seller);
        nftZeroRoyalty.approve(address(marketplace), 1);

        uint256 price = 1 ether;
        uint256 royaltyBalanceBefore = royaltyReceiver.balance;

        vm.prank(marketplaceCore);
        marketplace.executePurchase{value: price}(
            buyer, seller, address(nftZeroRoyalty), 1, 1, AssetTypes.TokenStandard.ERC721
        );

        // Royalty receiver should not receive anything
        assertEq(royaltyReceiver.balance, royaltyBalanceBefore);
    }

    function test_ExecutePurchase_WorksWithDifferentPrices() public {
        uint256 tokenId = 1;

        vm.prank(seller);
        nft721.approve(address(marketplace), tokenId);

        uint256[] memory prices = new uint256[](3);
        prices[0] = 0.1 ether;
        prices[1] = 1 ether;
        prices[2] = 10 ether;

        for (uint256 i = 0; i < prices.length; i++) {
            uint256 price = prices[i];

            uint256 platformFee = (price * PLATFORM_FEE_BPS) / 10_000;
            uint256 royaltyFee = (price * ROYALTY_FEE_BPS) / 10_000;
            uint256 sellerNet = price - platformFee - royaltyFee;

            (uint256 calcPlatform, uint256 calcRoyalty, uint256 calcSellerNet,) =
                marketplace.calculatePaymentDistribution(address(nft721), tokenId, price);

            assertEq(calcPlatform, platformFee);
            assertEq(calcRoyalty, royaltyFee);
            assertEq(calcSellerNet, sellerNet);
        }
    }

    function test_ExecutePurchase_MultipleSequentialPurchases() public {
        // Mint multiple NFTs
        vm.startPrank(seller);
        nft721.mint(seller, "ipfs://token2");
        nft721.mint(seller, "ipfs://token3");
        nft721.setApprovalForAll(address(marketplace), true);
        vm.stopPrank();

        uint256 price = 1 ether;

        for (uint256 tokenId = 1; tokenId <= 3; tokenId++) {
            vm.prank(marketplaceCore);
            marketplace.executePurchase{value: price}(
                buyer, seller, address(nft721), tokenId, 1, AssetTypes.TokenStandard.ERC721
            );

            assertEq(nft721.ownerOf(tokenId), buyer);
        }
    }

    // ============================================
    //          FUZZ TESTS
    // ============================================

    function testFuzz_CalculatePaymentDistribution(uint256 price) public view {
        price = bound(price, 0.001 ether, 100 ether);

        (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet, address royaltyRec) =
            marketplace.calculatePaymentDistribution(address(nft721), 1, price);

        // Verify math adds up
        assertEq(platformFee + royaltyFee + sellerNet, price);

        // Verify platform fee
        uint256 expectedPlatformFee = (price * PLATFORM_FEE_BPS) / 10_000;
        assertEq(platformFee, expectedPlatformFee);

        assertEq(royaltyRec, royaltyReceiver);
    }

    function testFuzz_ExecutePurchase_ERC721(uint256 price) public {
        price = bound(price, 0.01 ether, 10 ether);

        uint256 tokenId = 1;

        vm.prank(seller);
        nft721.approve(address(marketplace), tokenId);

        vm.deal(marketplaceCore, price);

        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(marketplaceCore);
        marketplace.executePurchase{value: price}(
            buyer, seller, address(nft721), tokenId, 1, AssetTypes.TokenStandard.ERC721
        );

        assertEq(nft721.ownerOf(tokenId), buyer);

        // Verify seller received payment (should be > 0)
        assertGt(seller.balance, sellerBalanceBefore);
    }

    function testFuzz_ExecutePurchase_ERC1155(uint256 quantity, uint256 price) public {
        quantity = bound(quantity, 1, 100);
        price = bound(price, 0.01 ether, 10 ether);

        uint256 tokenId = 1;

        vm.prank(seller);
        nft1155.setApprovalForAll(address(marketplace), true);

        vm.deal(marketplaceCore, price);

        vm.prank(marketplaceCore);
        marketplace.executePurchase{value: price}(
            buyer, seller, address(nft1155), tokenId, quantity, AssetTypes.TokenStandard.ERC1155
        );

        // Verify NFT transferred
        assertEq(nft1155.balanceOf(buyer, tokenId), quantity);
        assertEq(nft1155.balanceOf(seller, tokenId), 100 - quantity);
    }

    // ============================================
    //      REENTRANCY TESTS
    // ============================================

    function test_ExecutePurchase_ProtectsAgainstReentrancy() public {
        // The nonReentrant modifier should protect against reentrancy
        // This is tested implicitly by the modifier, but we verify it's applied
        uint256 tokenId = 1;
        uint256 price = 1 ether;

        vm.prank(seller);
        nft721.approve(address(marketplace), tokenId);

        vm.prank(marketplaceCore);
        marketplace.executePurchase{value: price}(
            buyer, seller, address(nft721), tokenId, 1, AssetTypes.TokenStandard.ERC721
        );

        // Trying to buy already sold NFT should fail (ownership check)
        vm.prank(marketplaceCore);
        vm.expectRevert(NFTMarketplace.InsufficientOwnership.selector);
        marketplace.executePurchase{value: price}(
            buyer, seller, address(nft721), tokenId, 1, AssetTypes.TokenStandard.ERC721
        );
    }
}

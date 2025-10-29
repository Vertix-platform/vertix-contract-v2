// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../../src/nft/NFTMarketplace.sol";
import "../../src/nft/VertixNFT721.sol";
import "../../src/access/RoleManager.sol";
import "../../src/core/FeeDistributor.sol";

contract NFTMarketplaceTest is Test {
    NFTMarketplace public marketplace;
    VertixNFT721 public nft;
    RoleManager public roleManager;
    FeeDistributor public feeDistributor;

    address public admin = address(1);
    address public seller = address(2);
    address public buyer = address(3);
    address public feeCollector = address(4);
    address public royaltyReceiver = address(5);

    uint256 constant PLATFORM_FEE_BPS = 250;
    uint256 constant ROYALTY_BPS = 1000;

    function setUp() public {
        vm.startPrank(admin);

        roleManager = new RoleManager(admin);
        feeDistributor = new FeeDistributor(
            address(roleManager),
            feeCollector,
            PLATFORM_FEE_BPS
        );
        marketplace = new NFTMarketplace(
            address(roleManager),
            address(feeDistributor),
            PLATFORM_FEE_BPS
        );

        nft = new VertixNFT721(
            "Test",
            "TEST",
            admin,
            royaltyReceiver,
            uint96(ROYALTY_BPS),
            0,
            ""
        );

        vm.stopPrank();

        vm.deal(buyer, 100 ether);
    }

    function test_createListing_ERC721() public {
        uint256 tokenId = _mintNFTToSeller();

        vm.startPrank(seller);
        nft.approve(address(marketplace), tokenId);

        uint256 listingId = marketplace.createListing(
            address(nft),
            tokenId,
            1,
            1 ether,
            AssetTypes.TokenStandard.ERC721
        );

        assertEq(listingId, 1);
        assertTrue(marketplace.isListingActive(listingId));

        vm.stopPrank();
    }

    function test_createListing_RevertIf_NotOwner() public {
        uint256 tokenId = _mintNFTToSeller();

        vm.prank(buyer);
        vm.expectRevert("Not owner");
        marketplace.createListing(
            address(nft),
            tokenId,
            1,
            1 ether,
            AssetTypes.TokenStandard.ERC721
        );
    }

    function test_createListing_RevertIf_NotApproved() public {
        uint256 tokenId = _mintNFTToSeller();

        vm.prank(seller);
        vm.expectRevert("Not approved");
        marketplace.createListing(
            address(nft),
            tokenId,
            1,
            1 ether,
            AssetTypes.TokenStandard.ERC721
        );
    }

    function test_buyNFT_Success() public {
        uint256 tokenId = _mintNFTToSeller();
        uint256 listingId = _createListing(tokenId, 1 ether);

        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(buyer);
        marketplace.buyNFT{value: 1 ether}(listingId);

        // Check NFT transferred
        assertEq(nft.ownerOf(tokenId), buyer);

        // Check payments (97.5% - 10% royalty = 87.5% to seller)
        assertEq(seller.balance, sellerBalanceBefore + 0.875 ether);
        assertFalse(marketplace.isListingActive(listingId));
    }

    function test_buyNFT_RevertIf_IncorrectPayment() public {
        uint256 tokenId = _mintNFTToSeller();
        uint256 listingId = _createListing(tokenId, 1 ether);

        vm.prank(buyer);
        vm.expectRevert("Incorrect payment");
        marketplace.buyNFT{value: 0.5 ether}(listingId);
    }

    function test_cancelListing_Success() public {
        uint256 tokenId = _mintNFTToSeller();
        uint256 listingId = _createListing(tokenId, 1 ether);

        vm.prank(seller);
        marketplace.cancelListing(listingId);

        assertFalse(marketplace.isListingActive(listingId));
    }

    function test_cancelListing_RevertIf_NotSeller() public {
        uint256 tokenId = _mintNFTToSeller();
        uint256 listingId = _createListing(tokenId, 1 ether);

        vm.prank(buyer);
        vm.expectRevert("Not seller");
        marketplace.cancelListing(listingId);
    }

    function test_updateListingPrice_Success() public {
        uint256 tokenId = _mintNFTToSeller();
        uint256 listingId = _createListing(tokenId, 1 ether);

        vm.prank(seller);
        marketplace.updateListingPrice(listingId, 2 ether);

        INFTMarketplace.Listing memory listing = marketplace.getListing(
            listingId
        );
        assertEq(listing.price, 2 ether);
    }

    // Helper functions
    function _mintNFTToSeller() internal returns (uint256) {
        vm.prank(admin);
        return nft.mint(seller, "ipfs://test");
    }

    function _createListing(
        uint256 tokenId,
        uint256 price
    ) internal returns (uint256) {
        vm.startPrank(seller);
        nft.approve(address(marketplace), tokenId);
        uint256 listingId = marketplace.createListing(
            address(nft),
            tokenId,
            1,
            price,
            AssetTypes.TokenStandard.ERC721
        );
        vm.stopPrank();
        return listingId;
    }
}

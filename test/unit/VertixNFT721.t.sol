// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../../src/nft/VertixNFT721.sol";
import "../../src/libraries/AssetTypes.sol";

contract VertixNFT721Test is Test {
    VertixNFT721 public nft;

    address public creator = address(0x1);
    address public royaltyReceiver = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public unauthorized = address(0x5);

    string public constant NAME = "Vertix Collection";
    string public constant SYMBOL = "VTX";
    string public constant BASE_URI = "ipfs://QmBase/";
    string public constant TOKEN_URI_1 = "ipfs://QmToken1";
    string public constant TOKEN_URI_2 = "ipfs://QmToken2";

    uint96 public constant ROYALTY_FEE = 500; // 5%
    uint256 public constant MAX_SUPPLY = 100;

    // Events
    event BatchMinted(
        address indexed to,
        uint256 startTokenId,
        uint256 quantity
    );
    event RoyaltyUpdated(address indexed receiver, uint96 feeBps);
    event MaxSupplyUpdated(uint256 newMaxSupply);
    event BaseURIUpdated(string newBaseURI);

    function setUp() public {
        vm.prank(creator);
        nft = new VertixNFT721(
            NAME,
            SYMBOL,
            creator,
            royaltyReceiver,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );
    }

    // ============================================
    // CONSTRUCTOR TESTS
    // ============================================

    function test_constructor_Success() public {
        assertEq(nft.name(), NAME);
        assertEq(nft.symbol(), SYMBOL);
        assertEq(nft.creator(), creator);
        assertEq(nft.owner(), creator);
        assertEq(nft.maxSupply(), MAX_SUPPLY);
        assertEq(nft.totalMinted(), 0);
        assertEq(nft.nextTokenId(), 0);
        assertFalse(nft.isMaxSupplyReached());
        assertEq(nft.remainingSupply(), MAX_SUPPLY);
    }

    function test_constructor_WithUnlimitedSupply() public {
        VertixNFT721 unlimitedNFT = new VertixNFT721(
            NAME,
            SYMBOL,
            creator,
            royaltyReceiver,
            ROYALTY_FEE,
            0, // Unlimited supply
            BASE_URI
        );

        assertEq(unlimitedNFT.maxSupply(), 0);
        assertEq(unlimitedNFT.remainingSupply(), type(uint256).max);
    }

    function test_constructor_WithoutRoyalty() public {
        VertixNFT721 noRoyaltyNFT = new VertixNFT721(
            NAME,
            SYMBOL,
            creator,
            address(0),
            0, // No royalty
            MAX_SUPPLY,
            BASE_URI
        );

        (address receiver, uint256 royalty) = noRoyaltyNFT.royaltyInfo(0, 1000);
        assertEq(receiver, address(0));
        assertEq(royalty, 0);
    }

    function test_constructor_RevertIf_InvalidCreator() public {
        vm.expectRevert("Invalid creator");
        new VertixNFT721(
            NAME,
            SYMBOL,
            address(0),
            royaltyReceiver,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );
    }

    function test_constructor_RevertIf_InvalidRoyalty() public {
        vm.expectRevert(
            abi.encodeWithSelector(VertixNFT721.InvalidRoyalty.selector, 1100)
        );
        new VertixNFT721(
            NAME,
            SYMBOL,
            creator,
            royaltyReceiver,
            1100, // Exceeds 10%
            MAX_SUPPLY,
            BASE_URI
        );
    }

    function test_constructor_RevertIf_InvalidRoyaltyReceiver() public {
        vm.expectRevert("Invalid royalty receiver");
        new VertixNFT721(
            NAME,
            SYMBOL,
            creator,
            address(0),
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );
    }

    // ============================================
    // MINT TESTS
    // ============================================

    function test_mint_Success() public {
        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, TOKEN_URI_1);

        assertEq(tokenId, 0);
        assertEq(nft.ownerOf(tokenId), user1);
        assertEq(nft.tokenURI(tokenId), TOKEN_URI_1);
        assertEq(nft.totalMinted(), 1);
        assertEq(nft.nextTokenId(), 1);
        assertEq(nft.remainingSupply(), MAX_SUPPLY - 1);
    }

    function test_mint_MultipleTimes() public {
        vm.startPrank(creator);

        uint256 tokenId1 = nft.mint(user1, TOKEN_URI_1);
        uint256 tokenId2 = nft.mint(user2, TOKEN_URI_2);

        vm.stopPrank();

        assertEq(tokenId1, 0);
        assertEq(tokenId2, 1);
        assertEq(nft.totalMinted(), 2);
        assertEq(nft.ownerOf(tokenId1), user1);
        assertEq(nft.ownerOf(tokenId2), user2);
    }

    function test_mint_RevertIf_NotOwner() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                unauthorized
            )
        );
        nft.mint(user1, TOKEN_URI_1);
    }

    function test_mint_RevertIf_MaxSupplyReached() public {
        vm.startPrank(creator);

        // Mint up to max supply
        for (uint256 i = 0; i < MAX_SUPPLY; i++) {
            nft.mint(user1, TOKEN_URI_1);
        }

        // Try to mint one more
        vm.expectRevert(VertixNFT721.MaxSupplyReached.selector);
        nft.mint(user1, TOKEN_URI_1);

        vm.stopPrank();
    }

    function test_mint_RevertIf_Paused() public {
        vm.startPrank(creator);

        nft.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        nft.mint(user1, TOKEN_URI_1);

        vm.stopPrank();
    }

    // ============================================
    // BATCH MINT TESTS
    // ============================================

    function test_batchMint_Success() public {
        string[] memory uris = new string[](3);
        uris[0] = "ipfs://QmToken1";
        uris[1] = "ipfs://QmToken2";
        uris[2] = "ipfs://QmToken3";

        vm.prank(creator);

        vm.expectEmit(true, true, true, true);
        emit BatchMinted(user1, 0, 3);

        uint256 startTokenId = nft.batchMint(user1, uris);

        assertEq(startTokenId, 0);
        assertEq(nft.totalMinted(), 3);
        assertEq(nft.nextTokenId(), 3);

        for (uint256 i = 0; i < 3; i++) {
            assertEq(nft.ownerOf(i), user1);
            assertEq(nft.tokenURI(i), uris[i]);
        }
    }

    function test_batchMint_LargeBatch() public {
        string[] memory uris = new string[](50);
        for (uint256 i = 0; i < 50; i++) {
            uris[i] = string(
                abi.encodePacked("ipfs://QmToken", vm.toString(i))
            );
        }

        vm.prank(creator);
        uint256 startTokenId = nft.batchMint(user1, uris);

        assertEq(startTokenId, 0);
        assertEq(nft.totalMinted(), 50);
        assertEq(nft.balanceOf(user1), 50);
    }

    function test_batchMint_RevertIf_EmptyBatch() public {
        string[] memory uris = new string[](0);

        vm.prank(creator);
        vm.expectRevert(VertixNFT721.EmptyBatch.selector);
        nft.batchMint(user1, uris);
    }

    function test_batchMint_RevertIf_ExceedsMaxSupply() public {
        string[] memory uris = new string[](MAX_SUPPLY + 1);
        for (uint256 i = 0; i < uris.length; i++) {
            uris[i] = TOKEN_URI_1;
        }

        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(
                VertixNFT721.ExceedsMaxSupply.selector,
                MAX_SUPPLY + 1,
                MAX_SUPPLY
            )
        );
        nft.batchMint(user1, uris);
    }

    function test_batchMint_RevertIf_NotOwner() public {
        string[] memory uris = new string[](1);
        uris[0] = TOKEN_URI_1;

        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                unauthorized
            )
        );
        nft.batchMint(user1, uris);
    }

    // ============================================
    // BATCH MINT SAME URI TESTS
    // ============================================

    function test_batchMintSameURI_Success() public {
        uint256 quantity = 10;

        vm.prank(creator);

        vm.expectEmit(true, true, true, true);
        emit BatchMinted(user1, 0, quantity);

        uint256 startTokenId = nft.batchMintSameURI(user1, quantity, BASE_URI);

        assertEq(startTokenId, 0);
        assertEq(nft.totalMinted(), quantity);
        assertEq(nft.balanceOf(user1), quantity);
    }

    function test_batchMintSameURI_RevertIf_EmptyBatch() public {
        vm.prank(creator);
        vm.expectRevert(VertixNFT721.EmptyBatch.selector);
        nft.batchMintSameURI(user1, 0, BASE_URI);
    }

    function test_batchMintSameURI_RevertIf_ExceedsMaxSupply() public {
        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(
                VertixNFT721.ExceedsMaxSupply.selector,
                MAX_SUPPLY + 1,
                MAX_SUPPLY
            )
        );
        nft.batchMintSameURI(user1, MAX_SUPPLY + 1, BASE_URI);
    }

    // ============================================
    // ROYALTY TESTS
    // ============================================

    function test_royaltyInfo() public {
        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, TOKEN_URI_1);

        uint256 salePrice = 1 ether;
        (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(
            tokenId,
            salePrice
        );

        assertEq(receiver, royaltyReceiver);
        assertEq(royaltyAmount, (salePrice * ROYALTY_FEE) / 10000); // 5% of 1 ether
    }

    function test_setDefaultRoyalty_Success() public {
        address newReceiver = address(0x99);
        uint96 newFee = 250; // 2.5%

        vm.prank(creator);

        vm.expectEmit(true, true, true, true);
        emit RoyaltyUpdated(newReceiver, newFee);

        nft.setDefaultRoyalty(newReceiver, newFee);

        // Mint a token and check new royalty
        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, TOKEN_URI_1);

        (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(
            tokenId,
            1000
        );
        assertEq(receiver, newReceiver);
        assertEq(royaltyAmount, 25); // 2.5% of 1000
    }

    function test_setDefaultRoyalty_RevertIf_ExceedsMax() public {
        vm.prank(creator);
        vm.expectRevert(
            abi.encodeWithSelector(VertixNFT721.InvalidRoyalty.selector, 1100)
        );
        nft.setDefaultRoyalty(royaltyReceiver, 1100);
    }

    function test_setDefaultRoyalty_RevertIf_NotOwner() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                unauthorized
            )
        );
        nft.setDefaultRoyalty(royaltyReceiver, 250);
    }

    function test_setTokenRoyalty_Success() public {
        vm.startPrank(creator);

        uint256 tokenId = nft.mint(user1, TOKEN_URI_1);

        address specialReceiver = address(0x88);
        uint96 specialFee = 750; // 7.5%

        nft.setTokenRoyalty(tokenId, specialReceiver, specialFee);

        vm.stopPrank();

        (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(
            tokenId,
            1000
        );
        assertEq(receiver, specialReceiver);
        assertEq(royaltyAmount, 75); // 7.5% of 1000
    }

    function test_deleteDefaultRoyalty_Success() public {
        vm.startPrank(creator);

        nft.deleteDefaultRoyalty();

        uint256 tokenId = nft.mint(user1, TOKEN_URI_1);

        vm.stopPrank();

        (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(
            tokenId,
            1000
        );
        assertEq(receiver, address(0));
        assertEq(royaltyAmount, 0);
    }

    function test_resetTokenRoyalty_Success() public {
        vm.startPrank(creator);

        uint256 tokenId = nft.mint(user1, TOKEN_URI_1);

        // Set special royalty
        address specialReceiver = address(0x88);
        nft.setTokenRoyalty(tokenId, specialReceiver, 750);

        // Reset to default
        nft.resetTokenRoyalty(tokenId);

        vm.stopPrank();

        // Should use default royalty now
        (address receiver, ) = nft.royaltyInfo(tokenId, 1000);
        assertEq(receiver, royaltyReceiver);
    }

    // ============================================
    // ADMIN FUNCTION TESTS
    // ============================================

    function test_setMaxSupply_Success() public {
        uint256 newMaxSupply = 200;

        vm.prank(creator);

        vm.expectEmit(true, true, true, true);
        emit MaxSupplyUpdated(newMaxSupply);

        nft.setMaxSupply(newMaxSupply);

        assertEq(nft.maxSupply(), newMaxSupply);
        assertEq(nft.remainingSupply(), newMaxSupply);
    }

    function test_setMaxSupply_RevertIf_BelowTotalMinted() public {
        vm.startPrank(creator);

        // Mint 10 tokens
        for (uint256 i = 0; i < 10; i++) {
            nft.mint(user1, TOKEN_URI_1);
        }

        // Try to set max supply below total minted
        vm.expectRevert(
            abi.encodeWithSelector(VertixNFT721.InvalidMaxSupply.selector, 5)
        );
        nft.setMaxSupply(5);

        vm.stopPrank();
    }

    function test_setMaxSupply_RevertIf_NotOwner() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                unauthorized
            )
        );
        nft.setMaxSupply(200);
    }

    function test_setBaseURI_Success() public {
        string memory newBaseURI = "ipfs://QmNewBase/";

        vm.prank(creator);

        vm.expectEmit(true, true, true, true);
        emit BaseURIUpdated(newBaseURI);

        nft.setBaseURI(newBaseURI);
    }

    function test_setBaseURI_RevertIf_NotOwner() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                unauthorized
            )
        );
        nft.setBaseURI("ipfs://QmNewBase/");
    }

    function test_pause_Success() public {
        vm.prank(creator);
        nft.pause();

        assertTrue(nft.paused());
    }

    function test_pause_RevertIf_NotOwner() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                unauthorized
            )
        );
        nft.pause();
    }

    function test_unpause_Success() public {
        vm.startPrank(creator);

        nft.pause();
        assertTrue(nft.paused());

        nft.unpause();
        assertFalse(nft.paused());

        vm.stopPrank();
    }

    function test_unpause_RevertIf_NotOwner() public {
        vm.prank(creator);
        nft.pause();

        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                unauthorized
            )
        );
        nft.unpause();
    }

    // ============================================
    // BURN TESTS
    // ============================================

    function test_burn_Success() public {
        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, TOKEN_URI_1);

        vm.prank(user1);
        nft.burn(tokenId);

        vm.expectRevert();
        nft.ownerOf(tokenId);
    }

    function test_burn_RevertIf_NotOwner() public {
        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, TOKEN_URI_1);

        vm.prank(user2);
        vm.expectRevert();
        nft.burn(tokenId);
    }

    // ============================================
    // TRANSFER TESTS
    // ============================================

    function test_transfer_Success() public {
        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, TOKEN_URI_1);

        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        assertEq(nft.ownerOf(tokenId), user2);
    }

    function test_transfer_RevertIf_Paused() public {
        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, TOKEN_URI_1);

        vm.prank(creator);
        nft.pause();

        vm.prank(user1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        nft.transferFrom(user1, user2, tokenId);
    }

    // ============================================
    // VIEW FUNCTION TESTS
    // ============================================

    function test_nextTokenId() public {
        assertEq(nft.nextTokenId(), 0);

        vm.prank(creator);
        nft.mint(user1, TOKEN_URI_1);

        assertEq(nft.nextTokenId(), 1);
    }

    function test_isMaxSupplyReached_False() public {
        assertFalse(nft.isMaxSupplyReached());

        vm.prank(creator);
        nft.mint(user1, TOKEN_URI_1);

        assertFalse(nft.isMaxSupplyReached());
    }

    function test_isMaxSupplyReached_True() public {
        vm.startPrank(creator);

        for (uint256 i = 0; i < MAX_SUPPLY; i++) {
            nft.mint(user1, TOKEN_URI_1);
        }

        vm.stopPrank();

        assertTrue(nft.isMaxSupplyReached());
    }

    function test_remainingSupply() public {
        assertEq(nft.remainingSupply(), MAX_SUPPLY);

        vm.prank(creator);
        nft.mint(user1, TOKEN_URI_1);

        assertEq(nft.remainingSupply(), MAX_SUPPLY - 1);
    }

    function test_supportsInterface() public {
        // ERC721
        assertTrue(nft.supportsInterface(0x80ac58cd));
        // ERC721Metadata
        assertTrue(nft.supportsInterface(0x5b5e139f));
        // ERC2981
        assertTrue(nft.supportsInterface(0x2a55205a));
    }

    // ============================================
    // FUZZ TESTS
    // ============================================

    function testFuzz_mint(address to, string memory uri) public {
        vm.assume(to != address(0));
        vm.assume(bytes(uri).length > 0 && bytes(uri).length < 1000);

        vm.prank(creator);
        uint256 tokenId = nft.mint(to, uri);

        assertEq(nft.ownerOf(tokenId), to);
        assertEq(nft.tokenURI(tokenId), uri);
    }

    function testFuzz_batchMint(uint8 quantity) public {
        vm.assume(quantity > 0 && quantity <= MAX_SUPPLY);

        string[] memory uris = new string[](quantity);
        for (uint256 i = 0; i < quantity; i++) {
            uris[i] = string(abi.encodePacked("ipfs://Qm", vm.toString(i)));
        }

        vm.prank(creator);
        uint256 startTokenId = nft.batchMint(user1, uris);

        assertEq(nft.totalMinted(), quantity);
        assertEq(nft.balanceOf(user1), quantity);
        assertEq(startTokenId, 0);
    }

    function testFuzz_royaltyInfo(uint256 salePrice) public {
        salePrice = bound(salePrice, 1, 1000000 ether);

        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, TOKEN_URI_1);

        (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(
            tokenId,
            salePrice
        );

        assertEq(receiver, royaltyReceiver);
        assertEq(royaltyAmount, (salePrice * ROYALTY_FEE) / 10000);
    }

    function testFuzz_setMaxSupply(uint256 newMaxSupply) public {
        newMaxSupply = bound(newMaxSupply, 0, 1000000);

        vm.prank(creator);
        nft.setMaxSupply(newMaxSupply);

        assertEq(nft.maxSupply(), newMaxSupply);
    }

    // ============================================
    // INTEGRATION TESTS
    // ============================================

    function test_integration_MintTransferBurn() public {
        // Mint
        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, TOKEN_URI_1);

        assertEq(nft.ownerOf(tokenId), user1);
        assertEq(nft.balanceOf(user1), 1);

        // Transfer
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        assertEq(nft.ownerOf(tokenId), user2);
        assertEq(nft.balanceOf(user1), 0);
        assertEq(nft.balanceOf(user2), 1);

        // Burn
        vm.prank(user2);
        nft.burn(tokenId);

        assertEq(nft.balanceOf(user2), 0);
        assertEq(nft.totalMinted(), 1); // Total minted doesn't decrease on burn
    }

    function test_integration_BatchMintWithRoyalty() public {
        string[] memory uris = new string[](5);
        for (uint256 i = 0; i < 5; i++) {
            uris[i] = string(
                abi.encodePacked("ipfs://QmToken", vm.toString(i))
            );
        }

        vm.prank(creator);
        uint256 startTokenId = nft.batchMint(user1, uris);

        // Check all tokens have royalty
        for (uint256 i = 0; i < 5; i++) {
            (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(
                startTokenId + i,
                1000
            );
            assertEq(receiver, royaltyReceiver);
            assertEq(royaltyAmount, 50); // 5% of 1000
        }
    }

    function test_integration_PauseAndUnpause() public {
        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, TOKEN_URI_1);

        // Pause
        vm.prank(creator);
        nft.pause();

        // Can't transfer when paused
        vm.prank(user1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        nft.transferFrom(user1, user2, tokenId);

        // Unpause
        vm.prank(creator);
        nft.unpause();

        // Can transfer after unpause
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        assertEq(nft.ownerOf(tokenId), user2);
    }
}

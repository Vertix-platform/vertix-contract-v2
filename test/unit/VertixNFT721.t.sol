// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {VertixNFT721} from "../../src/nft/VertixNFT721.sol";
import {AssetTypes} from "../../src/libraries/AssetTypes.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

contract VertixNFT721Test is Test {
    VertixNFT721 public nft;

    address public creator;
    address public royaltyReceiver;
    address public user1;
    address public user2;

    string constant NAME = "Test Collection";
    string constant SYMBOL = "TEST";
    uint96 constant ROYALTY_BPS = 500; // 5%
    uint256 constant MAX_SUPPLY = 1000;
    string constant BASE_URI = "ipfs://base/";

    event BatchMinted(address indexed to, uint256 startTokenId, uint256 quantity);
    event RoyaltyUpdated(address indexed receiver, uint96 feeBps);
    event MaxSupplyUpdated(uint256 newMaxSupply);
    event BaseURIUpdated(string newBaseURI);

    function setUp() public {
        creator = makeAddr("creator");
        royaltyReceiver = makeAddr("royaltyReceiver");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy with proxy
        VertixNFT721 impl = new VertixNFT721();
        bytes memory initData = abi.encodeWithSelector(
            VertixNFT721.initialize.selector, NAME, SYMBOL, creator, royaltyReceiver, ROYALTY_BPS, MAX_SUPPLY, BASE_URI
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        nft = VertixNFT721(address(proxy));
    }

    // ============================================
    //          INITIALIZATION TESTS
    // ============================================

    function test_Initialize_SetsNameAndSymbol() public view {
        assertEq(nft.name(), NAME);
        assertEq(nft.symbol(), SYMBOL);
    }

    function test_Initialize_SetsCreator() public view {
        assertEq(nft.creator(), creator);
        assertEq(nft.owner(), creator);
    }

    function test_Initialize_SetsMaxSupply() public view {
        assertEq(nft.maxSupply(), MAX_SUPPLY);
    }

    function test_Initialize_SetsBaseURI() public {
        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, "token1");

        string memory uri = nft.tokenURI(tokenId);
        assertEq(uri, string(abi.encodePacked(BASE_URI, "token1")));
    }

    function test_Initialize_SetsRoyalty() public view {
        (address receiver, uint256 amount) = nft.royaltyInfo(1, 1 ether);
        assertEq(receiver, royaltyReceiver);
        assertEq(amount, 0.05 ether); // 5%
    }

    function test_Initialize_RevertsOnZeroCreator() public {
        VertixNFT721 impl = new VertixNFT721();
        bytes memory initData = abi.encodeWithSelector(
            VertixNFT721.initialize.selector,
            NAME,
            SYMBOL,
            address(0),
            royaltyReceiver,
            ROYALTY_BPS,
            MAX_SUPPLY,
            BASE_URI
        );

        vm.expectRevert(Errors.InvalidCreator.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function test_Initialize_RevertsOnInvalidRoyalty() public {
        VertixNFT721 impl = new VertixNFT721();
        bytes memory initData = abi.encodeWithSelector(
            VertixNFT721.initialize.selector,
            NAME,
            SYMBOL,
            creator,
            royaltyReceiver,
            1500, // 15% - exceeds max
            MAX_SUPPLY,
            BASE_URI
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.RoyaltyTooHigh.selector, 1500, 1000));
        new ERC1967Proxy(address(impl), initData);
    }

    function test_Initialize_RevertsOnZeroRoyaltyReceiverWithNonZeroFee() public {
        VertixNFT721 impl = new VertixNFT721();
        bytes memory initData = abi.encodeWithSelector(
            VertixNFT721.initialize.selector, NAME, SYMBOL, creator, address(0), ROYALTY_BPS, MAX_SUPPLY, BASE_URI
        );

        vm.expectRevert(Errors.InvalidRoyaltyReceiver.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function test_Initialize_AllowsZeroRoyalty() public {
        VertixNFT721 impl = new VertixNFT721();
        bytes memory initData = abi.encodeWithSelector(
            VertixNFT721.initialize.selector, NAME, SYMBOL, creator, address(0), 0, MAX_SUPPLY, BASE_URI
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        VertixNFT721 nftNoRoyalty = VertixNFT721(address(proxy));

        (address receiver, uint256 amount) = nftNoRoyalty.royaltyInfo(1, 1 ether);
        assertEq(receiver, address(0));
        assertEq(amount, 0);
    }

    function test_Initialize_AllowsUnlimitedSupply() public {
        VertixNFT721 impl = new VertixNFT721();
        bytes memory initData = abi.encodeWithSelector(
            VertixNFT721.initialize.selector,
            NAME,
            SYMBOL,
            creator,
            royaltyReceiver,
            ROYALTY_BPS,
            0, // Unlimited
            BASE_URI
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        VertixNFT721 nftUnlimited = VertixNFT721(address(proxy));

        assertEq(nftUnlimited.maxSupply(), 0);
    }

    // ============================================
    //          MINTING TESTS
    // ============================================

    function test_Mint_MintsTokenSuccessfully() public {
        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, "token1");

        assertEq(tokenId, 1);
        assertEq(nft.ownerOf(tokenId), user1);
        assertEq(nft.totalMinted(), 1);
    }

    function test_Mint_IncrementsTokenId() public {
        vm.startPrank(creator);
        uint256 tokenId1 = nft.mint(user1, "token1");
        uint256 tokenId2 = nft.mint(user1, "token2");
        vm.stopPrank();

        assertEq(tokenId1, 1);
        assertEq(tokenId2, 2);
    }

    function test_Mint_SetsTokenURI() public {
        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, "token1");

        assertEq(nft.tokenURI(tokenId), string(abi.encodePacked(BASE_URI, "token1")));
    }

    function test_Mint_RespectsMaxSupply() public {
        // mint up to max supply
        vm.startPrank(creator);
        for (uint256 i = 0; i < MAX_SUPPLY; i++) {
            nft.mint(user1, "token");
        }

        // next mint should fail
        vm.expectRevert(VertixNFT721.MaxSupplyReached.selector);
        nft.mint(user1, "token");
        vm.stopPrank();
    }

    function test_Mint_AllowsUnlimitedWhenMaxSupplyIsZero() public {
        VertixNFT721 impl = new VertixNFT721();
        bytes memory initData = abi.encodeWithSelector(
            VertixNFT721.initialize.selector,
            NAME,
            SYMBOL,
            creator,
            royaltyReceiver,
            ROYALTY_BPS,
            0, // Unlimited
            BASE_URI
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        VertixNFT721 nftUnlimited = VertixNFT721(address(proxy));

        // Should allow minting beyond 1000
        vm.startPrank(creator);
        for (uint256 i = 0; i < 1500; i++) {
            nftUnlimited.mint(user1, "token");
        }
        vm.stopPrank();

        assertEq(nftUnlimited.totalMinted(), 1500);
    }

    function test_Mint_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        nft.mint(user1, "token1");
    }

    function test_Mint_RevertsWhenPaused() public {
        vm.startPrank(creator);
        nft.pause();

        vm.expectRevert();
        nft.mint(user1, "token1");
        vm.stopPrank();
    }

    // ============================================
    //          BATCH MINTING TESTS
    // ============================================

    function test_BatchMint_MintsMultipleTokens() public {
        string[] memory uris = new string[](5);
        for (uint256 i = 0; i < 5; i++) {
            uris[i] = string(abi.encodePacked("token", vm.toString(i)));
        }

        vm.prank(creator);
        uint256 startTokenId = nft.batchMint(user1, uris);

        assertEq(startTokenId, 0); // Counter starts at 0, first mint is 1
        assertEq(nft.totalMinted(), 5);
        assertEq(nft.ownerOf(1), user1);
        assertEq(nft.ownerOf(5), user1);
    }

    function test_BatchMint_EmitsEvent() public {
        string[] memory uris = new string[](3);
        for (uint256 i = 0; i < 3; i++) {
            uris[i] = "token";
        }

        vm.expectEmit(true, false, false, true);
        emit BatchMinted(user1, 0, 3);

        vm.prank(creator);
        nft.batchMint(user1, uris);
    }

    function test_BatchMint_RespectsMaxSupply() public {
        // Mint within batch size limit (100) but exceeding max supply
        string[] memory uris = new string[](50);
        for (uint256 i = 0; i < 50; i++) {
            uris[i] = "token";
        }

        // First mint most of max supply
        vm.startPrank(creator);
        for (uint256 i = 0; i < 19; i++) {
            // 19 * 50 = 950
            nft.batchMint(user1, uris);
        }

        // Now try to mint 100 more (would exceed 1000 max)
        string[] memory uris2 = new string[](100);
        for (uint256 i = 0; i < 100; i++) {
            uris2[i] = "token";
        }

        vm.expectRevert(abi.encodeWithSelector(VertixNFT721.ExceedsMaxSupply.selector, 100, 50));
        nft.batchMint(user1, uris2);
        vm.stopPrank();
    }

    function test_BatchMint_RevertsOnEmptyBatch() public {
        string[] memory uris = new string[](0);

        vm.prank(creator);
        vm.expectRevert(VertixNFT721.EmptyBatch.selector);
        nft.batchMint(user1, uris);
    }

    function test_BatchMint_RevertsOnOversizedBatch() public {
        string[] memory uris = new string[](101); // MAX_BATCH_MINT_SIZE = 100
        for (uint256 i = 0; i < 101; i++) {
            uris[i] = "token";
        }

        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(VertixNFT721.BatchSizeTooLarge.selector, 101, 100));
        nft.batchMint(user1, uris);
    }

    function test_BatchMint_RevertsIfNotOwner() public {
        string[] memory uris = new string[](3);
        for (uint256 i = 0; i < 3; i++) {
            uris[i] = "token";
        }

        vm.prank(user1);
        vm.expectRevert();
        nft.batchMint(user1, uris);
    }

    function test_BatchMint_RevertsWhenPaused() public {
        string[] memory uris = new string[](3);
        for (uint256 i = 0; i < 3; i++) {
            uris[i] = "token";
        }

        vm.startPrank(creator);
        nft.pause();

        vm.expectRevert();
        nft.batchMint(user1, uris);
        vm.stopPrank();
    }

    // ============================================
    //          ROYALTY TESTS
    // ============================================

    function test_SetDefaultRoyalty_UpdatesRoyalty() public {
        address newReceiver = makeAddr("newReceiver");
        uint96 newFee = 750; // 7.5%

        vm.prank(creator);
        vm.expectEmit(true, false, false, true);
        emit RoyaltyUpdated(newReceiver, newFee);
        nft.setDefaultRoyalty(newReceiver, newFee);

        (address receiver, uint256 amount) = nft.royaltyInfo(1, 1 ether);
        assertEq(receiver, newReceiver);
        assertEq(amount, 0.075 ether);
    }

    function test_SetDefaultRoyalty_RevertsOnExcessiveFee() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.RoyaltyTooHigh.selector, 1500, 1000));
        nft.setDefaultRoyalty(royaltyReceiver, 1500);
    }

    function test_SetDefaultRoyalty_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        nft.setDefaultRoyalty(royaltyReceiver, 500);
    }

    function test_SetTokenRoyalty_SetsPerTokenRoyalty() public {
        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, "token1");

        address tokenRoyaltyReceiver = makeAddr("tokenRoyalty");

        vm.prank(creator);
        nft.setTokenRoyalty(tokenId, tokenRoyaltyReceiver, 800); // 8%

        (address receiver, uint256 amount) = nft.royaltyInfo(tokenId, 1 ether);
        assertEq(receiver, tokenRoyaltyReceiver);
        assertEq(amount, 0.08 ether);
    }

    function test_SetTokenRoyalty_RevertsOnExcessiveFee() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.RoyaltyTooHigh.selector, 1500, 1000));
        nft.setTokenRoyalty(1, royaltyReceiver, 1500);
    }

    function test_DeleteDefaultRoyalty_RemovesRoyalty() public {
        vm.prank(creator);
        nft.deleteDefaultRoyalty();

        (address receiver, uint256 amount) = nft.royaltyInfo(1, 1 ether);
        assertEq(receiver, address(0));
        assertEq(amount, 0);
    }

    function test_ResetTokenRoyalty_ResetsToDefault() public {
        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, "token1");

        address tokenRoyaltyReceiver = makeAddr("tokenRoyalty");

        vm.startPrank(creator);
        nft.setTokenRoyalty(tokenId, tokenRoyaltyReceiver, 800);

        // Verify token has custom royalty
        (address receiver1,) = nft.royaltyInfo(tokenId, 1 ether);
        assertEq(receiver1, tokenRoyaltyReceiver);

        // Reset to default
        nft.resetTokenRoyalty(tokenId);

        // Should now use default
        (address receiver2,) = nft.royaltyInfo(tokenId, 1 ether);
        assertEq(receiver2, royaltyReceiver);
        vm.stopPrank();
    }

    // ============================================
    //          ADMIN TESTS
    // ============================================

    function test_SetMaxSupply_UpdatesMaxSupply() public {
        vm.prank(creator);
        vm.expectEmit(false, false, false, true);
        emit MaxSupplyUpdated(2000);
        nft.setMaxSupply(2000);

        assertEq(nft.maxSupply(), 2000);
    }

    function test_SetMaxSupply_RevertsIfBelowTotalMinted() public {
        vm.startPrank(creator);
        nft.mint(user1, "token1");
        nft.mint(user1, "token2");

        vm.expectRevert(abi.encodeWithSelector(VertixNFT721.InvalidMaxSupply.selector, 1));
        nft.setMaxSupply(1);
        vm.stopPrank();
    }

    function test_SetMaxSupply_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        nft.setMaxSupply(2000);
    }

    function test_SetBaseURI_UpdatesBaseURI() public {
        string memory newBaseURI = "https://new.uri/";

        vm.prank(creator);
        vm.expectEmit(false, false, false, true);
        emit BaseURIUpdated(newBaseURI);
        nft.setBaseURI(newBaseURI);

        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, "token1");

        assertEq(nft.tokenURI(tokenId), string(abi.encodePacked(newBaseURI, "token1")));
    }

    function test_SetBaseURI_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        nft.setBaseURI("https://new.uri/");
    }

    function test_Pause_PreventsTransfers() public {
        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, "token1");

        vm.prank(creator);
        nft.pause();

        vm.prank(user1);
        vm.expectRevert();
        nft.transferFrom(user1, user2, tokenId);
    }

    function test_Pause_PreventsMinting() public {
        vm.prank(creator);
        nft.pause();

        vm.prank(creator);
        vm.expectRevert();
        nft.mint(user1, "token1");
    }

    function test_Unpause_AllowsOperations() public {
        vm.startPrank(creator);
        nft.pause();
        nft.unpause();

        uint256 tokenId = nft.mint(user1, "token1");
        vm.stopPrank();

        assertEq(nft.ownerOf(tokenId), user1);
    }

    function test_Pause_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        nft.pause();
    }

    function test_Unpause_RevertsIfNotOwner() public {
        vm.startPrank(creator);
        nft.pause();
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert();
        nft.unpause();
    }

    // ============================================
    //          BURN TESTS
    // ============================================

    function test_Burn_BurnsToken() public {
        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, "token1");

        vm.prank(user1);
        nft.burn(tokenId);

        vm.expectRevert();
        nft.ownerOf(tokenId);
    }

    function test_Burn_DoesNotDecrementTotalMinted() public {
        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, "token1");

        assertEq(nft.totalMinted(), 1);

        vm.prank(user1);
        nft.burn(tokenId);

        // totalMinted should remain 1
        assertEq(nft.totalMinted(), 1);
    }

    function test_Burn_AllowsMintingAfterBurn() public {
        // Mint to max supply
        vm.startPrank(creator);
        for (uint256 i = 0; i < MAX_SUPPLY; i++) {
            nft.mint(user1, "token");
        }
        vm.stopPrank();

        // Cannot mint more
        vm.prank(creator);
        vm.expectRevert(VertixNFT721.MaxSupplyReached.selector);
        nft.mint(user1, "token");

        // Burn a token
        vm.prank(user1);
        nft.burn(1);

        // Still cannot mint (totalMinted doesn't decrease)
        vm.prank(creator);
        vm.expectRevert(VertixNFT721.MaxSupplyReached.selector);
        nft.mint(user1, "token");
    }

    // ============================================
    //          TRANSFER TESTS
    // ============================================

    function test_Transfer_TransfersToken() public {
        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, "token1");

        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        assertEq(nft.ownerOf(tokenId), user2);
    }

    function test_Transfer_RevertsWhenPaused() public {
        vm.prank(creator);
        uint256 tokenId = nft.mint(user1, "token1");

        vm.prank(creator);
        nft.pause();

        vm.prank(user1);
        vm.expectRevert();
        nft.transferFrom(user1, user2, tokenId);
    }

    // ============================================
    //          ERC2981 INTERFACE TESTS
    // ============================================

    function test_SupportsInterface_ERC2981() public view {
        assertTrue(nft.supportsInterface(type(IERC2981).interfaceId));
    }

    function test_SupportsInterface_ERC721() public view {
        assertTrue(nft.supportsInterface(type(IERC721).interfaceId));
    }

    function test_RoyaltyInfo_CalculatesCorrectly() public view {
        (address receiver, uint256 amount) = nft.royaltyInfo(1, 10 ether);
        assertEq(receiver, royaltyReceiver);
        assertEq(amount, 0.5 ether); // 5% of 10 ETH
    }

    // ============================================
    //          EDGE CASE TESTS
    // ============================================

    function test_MintToZeroAddress_Reverts() public {
        vm.prank(creator);
        vm.expectRevert();
        nft.mint(address(0), "token1");
    }

    function test_BatchMintToZeroAddress_Reverts() public {
        string[] memory uris = new string[](3);
        for (uint256 i = 0; i < 3; i++) {
            uris[i] = "token";
        }

        vm.prank(creator);
        vm.expectRevert();
        nft.batchMint(address(0), uris);
    }

    function test_TokenURIForNonexistentToken_Reverts() public {
        vm.expectRevert();
        nft.tokenURI(999);
    }

    // ============================================
    //          FUZZ TESTS
    // ============================================

    function testFuzz_Mint_VariousAddresses(address to) public {
        vm.assume(to != address(0));
        vm.assume(to.code.length == 0); // Not a contract

        vm.prank(creator);
        uint256 tokenId = nft.mint(to, "token1");

        assertEq(nft.ownerOf(tokenId), to);
    }

    function testFuzz_RoyaltyInfo_VariousPrices(uint256 salePrice) public view {
        salePrice = bound(salePrice, 0, type(uint128).max);

        (, uint256 royaltyAmount) = nft.royaltyInfo(1, salePrice);

        // Royalty should be 5% of sale price
        uint256 expected = (salePrice * ROYALTY_BPS) / 10_000;
        assertEq(royaltyAmount, expected);
    }

    function testFuzz_SetMaxSupply_ValidValues(uint256 newMaxSupply) public {
        newMaxSupply = bound(newMaxSupply, 0, type(uint256).max);

        vm.prank(creator);
        nft.setMaxSupply(newMaxSupply);

        assertEq(nft.maxSupply(), newMaxSupply);
    }
}

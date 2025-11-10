// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {VertixNFT1155} from "../../src/nft/VertixNFT1155.sol";
import {AssetTypes} from "../../src/libraries/AssetTypes.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

contract VertixNFT1155Test is Test {
    VertixNFT1155 public nft;

    address public creator;
    address public royaltyReceiver;
    address public user1;
    address public user2;

    string constant NAME = "Test Collection";
    string constant SYMBOL = "TEST";
    string constant BASE_URI = "https://api.example.com/metadata/";
    uint96 constant ROYALTY_BPS = 500; // 5%

    event TokenCreated(uint256 indexed tokenId, uint256 initialSupply, uint256 maxSupply, string tokenURI);
    event TokenURIUpdated(uint256 indexed tokenId, string newURI);
    event RoyaltyUpdated(address indexed receiver, uint96 feeBps);

    function setUp() public {
        creator = makeAddr("creator");
        royaltyReceiver = makeAddr("royaltyReceiver");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy with proxy
        VertixNFT1155 impl = new VertixNFT1155();
        bytes memory initData = abi.encodeWithSelector(
            VertixNFT1155.initialize.selector, NAME, SYMBOL, BASE_URI, creator, royaltyReceiver, ROYALTY_BPS
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        nft = VertixNFT1155(address(proxy));
    }

    // ============================================
    //          INITIALIZATION TESTS
    // ============================================

    function test_Initialize_SetsNameAndSymbol() public view {
        assertEq(nft.name(), NAME);
        assertEq(nft.symbol(), SYMBOL);
    }

    function test_Initialize_SetsOwner() public view {
        assertEq(nft.owner(), creator);
    }

    function test_Initialize_SetsRoyalty() public view {
        (address receiver, uint256 amount) = nft.royaltyInfo(1, 1 ether);
        assertEq(receiver, royaltyReceiver);
        assertEq(amount, 0.05 ether); // 5%
    }

    function test_Initialize_RevertsOnZeroCreator() public {
        VertixNFT1155 impl = new VertixNFT1155();
        bytes memory initData = abi.encodeWithSelector(
            VertixNFT1155.initialize.selector, NAME, SYMBOL, BASE_URI, address(0), royaltyReceiver, ROYALTY_BPS
        );

        vm.expectRevert(Errors.InvalidCreator.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function test_Initialize_RevertsOnInvalidRoyalty() public {
        VertixNFT1155 impl = new VertixNFT1155();
        bytes memory initData = abi.encodeWithSelector(
            VertixNFT1155.initialize.selector,
            NAME,
            SYMBOL,
            BASE_URI,
            creator,
            royaltyReceiver,
            1500 // 15% - exceeds max
        );

        vm.expectRevert(abi.encodeWithSelector(Errors.RoyaltyTooHigh.selector, 1500, AssetTypes.MAX_ROYALTY_BPS));
        new ERC1967Proxy(address(impl), initData);
    }

    function test_Initialize_RevertsOnZeroRoyaltyReceiverWithNonZeroFee() public {
        VertixNFT1155 impl = new VertixNFT1155();
        bytes memory initData = abi.encodeWithSelector(
            VertixNFT1155.initialize.selector, NAME, SYMBOL, BASE_URI, creator, address(0), ROYALTY_BPS
        );

        vm.expectRevert(Errors.InvalidRoyaltyReceiver.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function test_Initialize_AllowsZeroRoyalty() public {
        VertixNFT1155 impl = new VertixNFT1155();
        bytes memory initData =
            abi.encodeWithSelector(VertixNFT1155.initialize.selector, NAME, SYMBOL, BASE_URI, creator, address(0), 0);

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        VertixNFT1155 nftNoRoyalty = VertixNFT1155(address(proxy));

        (address receiver, uint256 amount) = nftNoRoyalty.royaltyInfo(1, 1 ether);
        assertEq(receiver, address(0));
        assertEq(amount, 0);
    }

    // ============================================
    //          TOKEN CREATION TESTS
    // ============================================

    function test_Create_CreatesTokenSuccessfully() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, "token1", 1000);

        assertEq(tokenId, 1);
        assertEq(nft.balanceOf(creator, tokenId), 100);
        assertEq(nft.totalSupply(tokenId), 100);
        assertEq(nft.tokenMaxSupply(tokenId), 1000);
        assertEq(nft.uri(tokenId), "token1");
    }

    function test_Create_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit TokenCreated(1, 100, 1000, "token1");

        vm.prank(creator);
        nft.create(100, "token1", 1000);
    }

    function test_Create_AllowsZeroInitialSupply() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(0, "token1", 1000);

        assertEq(nft.balanceOf(creator, tokenId), 0);
        assertEq(nft.totalSupply(tokenId), 0);
    }

    function test_Create_AllowsUnlimitedMaxSupply() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, "token1", 0);

        assertEq(nft.tokenMaxSupply(tokenId), 0);
    }

    function test_Create_RevertsIfInitialSupplyExceedsMax() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.MaxSupplyReached.selector, 1001, 1000));
        nft.create(1001, "token1", 1000);
    }

    function test_Create_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        nft.create(100, "token1", 1000);
    }

    function test_Create_IncrementsTokenId() public {
        vm.startPrank(creator);
        uint256 tokenId1 = nft.create(100, "token1", 1000);
        uint256 tokenId2 = nft.create(50, "token2", 500);
        vm.stopPrank();

        assertEq(tokenId1, 1);
        assertEq(tokenId2, 2);
    }

    // ============================================
    //          MINTING TESTS
    // ============================================

    function test_Mint_MintsAdditionalTokens() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, "token1", 1000);

        vm.prank(creator);
        nft.mint(user1, tokenId, 50);

        assertEq(nft.balanceOf(user1, tokenId), 50);
        assertEq(nft.totalSupply(tokenId), 150);
    }

    function test_Mint_RespectsMaxSupply() public {
        vm.startPrank(creator);
        uint256 tokenId = nft.create(900, "token1", 1000);

        nft.mint(user1, tokenId, 100);

        vm.expectRevert(abi.encodeWithSelector(Errors.MaxSupplyReached.selector, 1000, 1000));
        nft.mint(user1, tokenId, 1);
        vm.stopPrank();
    }

    function test_Mint_AllowsUnlimitedWhenMaxSupplyIsZero() public {
        vm.startPrank(creator);
        uint256 tokenId = nft.create(100, "token1", 0); // Unlimited

        // Should be able to mint any amount
        nft.mint(user1, tokenId, 1_000_000);

        assertEq(nft.totalSupply(tokenId), 1_000_100);
        vm.stopPrank();
    }

    function test_Mint_RevertsOnNonexistentToken() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.TokenDoesNotExist.selector, 999));
        nft.mint(user1, 999, 50);
    }

    function test_Mint_RevertsOnTokenIdZero() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.TokenDoesNotExist.selector, 0));
        nft.mint(user1, 0, 50);
    }

    function test_Mint_RevertsIfNotOwner() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, "token1", 1000);

        vm.prank(user1);
        vm.expectRevert();
        nft.mint(user1, tokenId, 50);
    }

    function test_Mint_RevertsWhenPaused() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, "token1", 1000);

        vm.prank(creator);
        nft.pause();

        vm.prank(creator);
        vm.expectRevert();
        nft.mint(user1, tokenId, 50);
    }

    // ============================================
    //          BATCH MINTING TESTS
    // ============================================

    function test_MintBatch_MintsMultipleTokens() public {
        vm.startPrank(creator);
        nft.create(100, "token1", 1000);
        nft.create(50, "token2", 500);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 25;
        amounts[1] = 10;

        nft.mintBatch(user1, tokenIds, amounts);
        vm.stopPrank();

        assertEq(nft.balanceOf(user1, 1), 25);
        assertEq(nft.balanceOf(user1, 2), 10);
    }

    function test_MintBatch_RevertsIfNotOwner() public {
        vm.prank(creator);
        nft.create(100, "token1", 1000);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 25;

        vm.prank(user1);
        vm.expectRevert();
        nft.mintBatch(user1, tokenIds, amounts);
    }

    function test_MintBatch_RevertsWhenPaused() public {
        vm.startPrank(creator);
        nft.create(100, "token1", 1000);
        nft.pause();

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 25;

        vm.expectRevert();
        nft.mintBatch(user1, tokenIds, amounts);
        vm.stopPrank();
    }

    // ============================================
    //          URI TESTS
    // ============================================

    function test_SetURI_UpdatesTokenURI() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, "token1", 1000);

        vm.prank(creator);
        vm.expectEmit(true, false, false, true);
        emit TokenURIUpdated(tokenId, "newURI");
        nft.setURI(tokenId, "newURI");

        assertEq(nft.uri(tokenId), "newURI");
    }

    function test_SetURI_RevertsOnNonexistentToken() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.TokenDoesNotExist.selector, 999));
        nft.setURI(999, "newURI");
    }

    function test_SetURI_RevertsOnTokenIdZero() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.TokenDoesNotExist.selector, 0));
        nft.setURI(0, "newURI");
    }

    function test_SetURI_RevertsIfNotOwner() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, "token1", 1000);

        vm.prank(user1);
        vm.expectRevert();
        nft.setURI(tokenId, "newURI");
    }

    function test_URI_ReturnsTokenURI() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, "custom-uri", 1000);

        assertEq(nft.uri(tokenId), "custom-uri");
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
        vm.expectRevert(abi.encodeWithSelector(Errors.RoyaltyTooHigh.selector, 1500, AssetTypes.MAX_ROYALTY_BPS));
        nft.setDefaultRoyalty(royaltyReceiver, 1500);
    }

    function test_SetDefaultRoyalty_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        nft.setDefaultRoyalty(royaltyReceiver, 500);
    }

    function test_SetTokenRoyalty_SetsPerTokenRoyalty() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, "token1", 1000);

        address tokenRoyaltyReceiver = makeAddr("tokenRoyalty");

        vm.prank(creator);
        nft.setTokenRoyalty(tokenId, tokenRoyaltyReceiver, 800); // 8%

        (address receiver, uint256 amount) = nft.royaltyInfo(tokenId, 1 ether);
        assertEq(receiver, tokenRoyaltyReceiver);
        assertEq(amount, 0.08 ether);
    }

    function test_SetTokenRoyalty_RevertsOnExcessiveFee() public {
        vm.prank(creator);
        vm.expectRevert(abi.encodeWithSelector(Errors.RoyaltyTooHigh.selector, 1500, AssetTypes.MAX_ROYALTY_BPS));
        nft.setTokenRoyalty(1, royaltyReceiver, 1500);
    }

    function test_SetTokenRoyalty_RevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        nft.setTokenRoyalty(1, royaltyReceiver, 500);
    }

    // ============================================
    //          PAUSE TESTS
    // ============================================

    function test_Pause_PreventsTransfers() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, "token1", 1000);

        vm.prank(creator);
        nft.pause();

        vm.prank(creator);
        vm.expectRevert();
        nft.safeTransferFrom(creator, user1, tokenId, 10, "");
    }

    function test_Pause_PreventsMinting() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, "token1", 1000);

        vm.prank(creator);
        nft.pause();

        vm.prank(creator);
        vm.expectRevert();
        nft.mint(user1, tokenId, 50);
    }

    function test_Unpause_AllowsOperations() public {
        vm.startPrank(creator);
        uint256 tokenId = nft.create(100, "token1", 1000);
        nft.pause();
        nft.unpause();

        nft.mint(user1, tokenId, 50);
        vm.stopPrank();

        assertEq(nft.balanceOf(user1, tokenId), 50);
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

    function test_Burn_BurnsTokens() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, "token1", 1000);

        vm.prank(creator);
        nft.burn(creator, tokenId, 50);

        assertEq(nft.balanceOf(creator, tokenId), 50);
        assertEq(nft.totalSupply(tokenId), 50);
    }

    function test_Burn_AllowsMintingAfterBurn() public {
        vm.startPrank(creator);
        uint256 tokenId = nft.create(1000, "token1", 1000);

        // Burn some
        nft.burn(creator, tokenId, 100);

        // Can mint again since total supply decreased
        nft.mint(user1, tokenId, 100);

        assertEq(nft.totalSupply(tokenId), 1000);
        vm.stopPrank();
    }

    function test_BurnBatch_BurnsMultipleTokens() public {
        vm.startPrank(creator);
        nft.create(100, "token1", 1000);
        nft.create(50, "token2", 500);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 25;
        amounts[1] = 10;

        nft.burnBatch(creator, tokenIds, amounts);
        vm.stopPrank();

        assertEq(nft.balanceOf(creator, 1), 75);
        assertEq(nft.balanceOf(creator, 2), 40);
    }

    // ============================================
    //          TRANSFER TESTS
    // ============================================

    function test_Transfer_TransfersTokens() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, "token1", 1000);

        vm.prank(creator);
        nft.safeTransferFrom(creator, user1, tokenId, 25, "");

        assertEq(nft.balanceOf(creator, tokenId), 75);
        assertEq(nft.balanceOf(user1, tokenId), 25);
    }

    function test_Transfer_RevertsWhenPaused() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, "token1", 1000);

        vm.prank(creator);
        nft.pause();

        vm.prank(creator);
        vm.expectRevert();
        nft.safeTransferFrom(creator, user1, tokenId, 25, "");
    }

    function test_BatchTransfer_TransfersMultipleTokens() public {
        vm.startPrank(creator);
        nft.create(100, "token1", 1000);
        nft.create(50, "token2", 500);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 25;
        amounts[1] = 10;

        nft.safeBatchTransferFrom(creator, user1, tokenIds, amounts, "");
        vm.stopPrank();

        assertEq(nft.balanceOf(user1, 1), 25);
        assertEq(nft.balanceOf(user1, 2), 10);
    }

    // ============================================
    //          ERC2981 INTERFACE TESTS
    // ============================================

    function test_SupportsInterface_ERC2981() public view {
        assertTrue(nft.supportsInterface(type(IERC2981).interfaceId));
    }

    function test_SupportsInterface_ERC1155() public view {
        assertTrue(nft.supportsInterface(type(IERC1155).interfaceId));
    }

    function test_RoyaltyInfo_CalculatesCorrectly() public view {
        (address receiver, uint256 amount) = nft.royaltyInfo(1, 10 ether);
        assertEq(receiver, royaltyReceiver);
        assertEq(amount, 0.5 ether); // 5% of 10 ETH
    }

    // ============================================
    //          SUPPLY TRACKING TESTS
    // ============================================

    function test_TotalSupply_TracksCorrectly() public {
        vm.startPrank(creator);
        uint256 tokenId = nft.create(100, "token1", 1000);

        assertEq(nft.totalSupply(tokenId), 100);

        nft.mint(user1, tokenId, 50);
        assertEq(nft.totalSupply(tokenId), 150);

        nft.burn(creator, tokenId, 25);
        assertEq(nft.totalSupply(tokenId), 125);
        vm.stopPrank();
    }

    function test_Exists_ReturnsCorrectly() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, "token1", 1000);

        assertTrue(nft.exists(tokenId));
        assertFalse(nft.exists(999));
    }

    // ============================================
    //          EDGE CASE TESTS
    // ============================================

    function test_Create_WithZeroMaxSupplyAndInitialSupply() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(0, "token1", 0);

        assertEq(nft.totalSupply(tokenId), 0);
        assertEq(nft.tokenMaxSupply(tokenId), 0);
    }

    function test_BalanceOfBatch_ReturnsCorrectBalances() public {
        vm.startPrank(creator);
        nft.create(100, "token1", 1000);
        nft.create(50, "token2", 500);
        vm.stopPrank();

        address[] memory accounts = new address[](2);
        accounts[0] = creator;
        accounts[1] = creator;

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        uint256[] memory balances = nft.balanceOfBatch(accounts, tokenIds);

        assertEq(balances[0], 100);
        assertEq(balances[1], 50);
    }

    // ============================================
    //          FUZZ TESTS
    // ============================================

    function testFuzz_Create_VariousSupplies(uint256 initialSupply, uint256 maxSupply) public {
        initialSupply = bound(initialSupply, 0, type(uint128).max);
        maxSupply = bound(maxSupply, initialSupply, type(uint128).max);

        vm.prank(creator);
        uint256 tokenId = nft.create(initialSupply, "token1", maxSupply);

        assertEq(nft.totalSupply(tokenId), initialSupply);
        assertEq(nft.tokenMaxSupply(tokenId), maxSupply);
    }

    function testFuzz_Mint_VariousAmounts(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);

        vm.startPrank(creator);
        uint256 tokenId = nft.create(0, "token1", 0); // Unlimited
        nft.mint(user1, tokenId, amount);
        vm.stopPrank();

        assertEq(nft.balanceOf(user1, tokenId), amount);
    }

    function testFuzz_RoyaltyInfo_VariousPrices(uint256 salePrice) public view {
        salePrice = bound(salePrice, 0, type(uint128).max);

        (, uint256 royaltyAmount) = nft.royaltyInfo(1, salePrice);

        // Royalty should be 5% of sale price
        uint256 expected = (salePrice * ROYALTY_BPS) / 10_000;
        assertEq(royaltyAmount, expected);
    }
}

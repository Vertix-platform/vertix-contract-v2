// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VertixSinglesNFT1155} from "../../src/nft/VertixSinglesNFT1155.sol";
import {Errors} from "../../src/libraries/Errors.sol";

contract VertixSinglesNFT1155Test is Test {
    VertixSinglesNFT1155 public singlesNFT;

    address public owner;
    address public minter1;
    address public minter2;
    address public marketplace;

    event SingleEditionMinted(
        address indexed minter, uint256 indexed tokenId, uint256 amount, uint256 maxSupply, string uri
    );
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    function setUp() public {
        owner = makeAddr("owner");
        minter1 = makeAddr("minter1");
        minter2 = makeAddr("minter2");
        marketplace = makeAddr("marketplace");

        singlesNFT = new VertixSinglesNFT1155();
        singlesNFT.initialize("Vertix Editions", "VEDITION", "", owner);
    }

    // ============================================
    //         INITIALIZATION TESTS
    // ============================================

    function test_Initialize_SetsNameAndSymbol() public view {
        assertEq(singlesNFT.name(), "Vertix Editions");
        assertEq(singlesNFT.symbol(), "VEDITION");
    }

    function test_Initialize_SetsOwner() public view {
        assertEq(singlesNFT.owner(), owner);
    }

    function test_Initialize_RevertsOnZeroOwner() public {
        VertixSinglesNFT1155 newNFT = new VertixSinglesNFT1155();
        vm.expectRevert(Errors.ZeroAddress.selector);
        newNFT.initialize("Test", "TEST", "", address(0));
    }

    function test_Initialize_CanOnlyBeCalledOnce() public {
        vm.expectRevert();
        singlesNFT.initialize("Test", "TEST", "", owner);
    }

    function test_Initialize_StartsWithZeroTokens() public view {
        assertEq(singlesNFT.totalTokens(), 0);
    }

    // ============================================
    //         MINTING TESTS
    // ============================================

    function test_MintPublic_MintsSuccessfully() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(10, 100, "ipfs://test1", "");

        assertEq(tokenId, 1);
        assertEq(singlesNFT.balanceOf(minter1, tokenId), 10);
        assertEq(singlesNFT.totalTokens(), 1);
    }

    function test_MintPublic_EmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit SingleEditionMinted(minter1, 1, 10, 100, "ipfs://test1");

        vm.prank(minter1);
        singlesNFT.mintPublic(10, 100, "ipfs://test1", "");
    }

    function test_MintPublic_SetsTokenURI() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(10, 0, "ipfs://test1", "");

        assertEq(singlesNFT.uri(tokenId), "ipfs://test1");
    }

    function test_MintPublic_TracksMinter() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(10, 0, "ipfs://test1", "");

        assertEq(singlesNFT.tokenMinter(tokenId), minter1);
        assertEq(singlesNFT.getMinter(tokenId), minter1);
    }

    function test_MintPublic_IncrementsTokenId() public {
        vm.prank(minter1);
        uint256 token1 = singlesNFT.mintPublic(10, 0, "ipfs://test1", "");

        vm.prank(minter2);
        uint256 token2 = singlesNFT.mintPublic(5, 0, "ipfs://test2", "");

        assertEq(token1, 1);
        assertEq(token2, 2);
    }

    function test_MintPublic_IncrementsTokenCount() public {
        vm.prank(minter1);
        singlesNFT.mintPublic(10, 0, "ipfs://test1", "");
        assertEq(singlesNFT.totalTokens(), 1);

        vm.prank(minter1);
        singlesNFT.mintPublic(20, 0, "ipfs://test2", "");
        assertEq(singlesNFT.totalTokens(), 2);

        vm.prank(minter2);
        singlesNFT.mintPublic(5, 0, "ipfs://test3", "");
        assertEq(singlesNFT.totalTokens(), 3);
    }

    function test_MintPublic_WithUnlimitedSupply() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(100, 0, "ipfs://test1", "");

        assertEq(singlesNFT.tokenMaxSupply(tokenId), 0);
        (bool canMint, uint256 available) = singlesNFT.canMintMore(tokenId);
        assertTrue(canMint);
        assertEq(available, 0); // 0 means unlimited
    }

    function test_MintPublic_WithMaxSupply() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(50, 100, "ipfs://test1", "");

        assertEq(singlesNFT.tokenMaxSupply(tokenId), 100);
        (bool canMint, uint256 available) = singlesNFT.canMintMore(tokenId);
        assertTrue(canMint);
        assertEq(available, 50); // 100 - 50 = 50 available
    }

    function test_MintPublic_RevertsOnZeroAmount() public {
        vm.prank(minter1);
        vm.expectRevert(Errors.InvalidAmount.selector);
        singlesNFT.mintPublic(0, 0, "ipfs://test1", "");
    }

    function test_MintPublic_RevertsWhenPaused() public {
        vm.prank(owner);
        singlesNFT.pause();

        vm.prank(minter1);
        vm.expectRevert();
        singlesNFT.mintPublic(10, 0, "ipfs://test1", "");
    }

    // ============================================
    //         MINT MORE TESTS
    // ============================================

    function test_MintMore_AllowsMinterToMintMore() public {
        vm.startPrank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(50, 0, "ipfs://test1", "");

        singlesNFT.mintMore(tokenId, 25, "");
        vm.stopPrank();

        assertEq(singlesNFT.balanceOf(minter1, tokenId), 75);
    }

    function test_MintMore_RespectsMaxSupply() public {
        vm.startPrank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(50, 100, "ipfs://test1", "");

        singlesNFT.mintMore(tokenId, 50, "");
        vm.stopPrank();

        assertEq(singlesNFT.balanceOf(minter1, tokenId), 100);
        assertEq(singlesNFT.totalSupply(tokenId), 100);
    }

    function test_MintMore_RevertsIfExceedsMaxSupply() public {
        vm.startPrank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(50, 100, "ipfs://test1", "");

        vm.expectRevert(Errors.ExceedsMaxSupply.selector);
        singlesNFT.mintMore(tokenId, 51, "");
        vm.stopPrank();
    }

    function test_MintMore_RevertsIfNotOriginalMinter() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(50, 0, "ipfs://test1", "");

        vm.prank(minter2);
        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedCaller.selector, minter2));
        singlesNFT.mintMore(tokenId, 25, "");
    }

    function test_MintMore_RevertsOnZeroAmount() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(50, 0, "ipfs://test1", "");

        vm.prank(minter1);
        vm.expectRevert(Errors.InvalidAmount.selector);
        singlesNFT.mintMore(tokenId, 0, "");
    }

    function test_MintMore_RevertsWhenPaused() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(50, 0, "ipfs://test1", "");

        vm.prank(owner);
        singlesNFT.pause();

        vm.prank(minter1);
        vm.expectRevert();
        singlesNFT.mintMore(tokenId, 25, "");
    }

    function test_MintMore_AllowsUnlimitedIfMaxSupplyZero() public {
        vm.startPrank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(100, 0, "ipfs://test1", "");

        singlesNFT.mintMore(tokenId, 500, "");
        singlesNFT.mintMore(tokenId, 1000, "");
        vm.stopPrank();

        assertEq(singlesNFT.balanceOf(minter1, tokenId), 1600);
    }

    // ============================================
    //         TRANSFER TESTS
    // ============================================

    function test_Transfer_WorksAfterMinting() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(100, 0, "ipfs://test1", "");

        vm.prank(minter1);
        singlesNFT.safeTransferFrom(minter1, minter2, tokenId, 50, "");

        assertEq(singlesNFT.balanceOf(minter1, tokenId), 50);
        assertEq(singlesNFT.balanceOf(minter2, tokenId), 50);
    }

    function test_Transfer_PreservesOriginalMinter() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(100, 0, "ipfs://test1", "");

        vm.prank(minter1);
        singlesNFT.safeTransferFrom(minter1, minter2, tokenId, 50, "");

        assertEq(singlesNFT.getMinter(tokenId), minter1);
    }

    function test_Transfer_AllowedWhenPaused() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(100, 0, "ipfs://test1", "");

        vm.prank(owner);
        singlesNFT.pause();

        // Transfers are still allowed when paused (only minting is blocked)
        vm.prank(minter1);
        singlesNFT.safeTransferFrom(minter1, minter2, tokenId, 50, "");

        assertEq(singlesNFT.balanceOf(minter1, tokenId), 50);
        assertEq(singlesNFT.balanceOf(minter2, tokenId), 50);
    }

    // ============================================
    //         APPROVAL TESTS
    // ============================================

    function test_SetApprovalForAll_WorksForMarketplace() public {
        vm.prank(minter1);
        singlesNFT.setApprovalForAll(marketplace, true);

        assertTrue(singlesNFT.isApprovedForAll(minter1, marketplace));
    }

    function test_SetApprovalForAll_AllowsMarketplaceTransfer() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(100, 0, "ipfs://test1", "");

        vm.prank(minter1);
        singlesNFT.setApprovalForAll(marketplace, true);

        vm.prank(marketplace);
        singlesNFT.safeTransferFrom(minter1, minter2, tokenId, 50, "");

        assertEq(singlesNFT.balanceOf(minter2, tokenId), 50);
    }

    // ============================================
    //         BURN TESTS
    // ============================================

    function test_Burn_OwnerCanBurnTokens() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(100, 0, "ipfs://test1", "");

        vm.prank(minter1);
        singlesNFT.burn(minter1, tokenId, 50);

        assertEq(singlesNFT.balanceOf(minter1, tokenId), 50);
        assertEq(singlesNFT.totalSupply(tokenId), 50);
    }

    function test_Burn_CanBurnAllTokens() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(100, 0, "ipfs://test1", "");

        vm.prank(minter1);
        singlesNFT.burn(minter1, tokenId, 100);

        assertEq(singlesNFT.balanceOf(minter1, tokenId), 0);
        assertEq(singlesNFT.totalSupply(tokenId), 0);
    }

    function test_Burn_PreservesMinterRecord() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(100, 0, "ipfs://test1", "");

        vm.prank(minter1);
        singlesNFT.burn(minter1, tokenId, 100);

        assertEq(singlesNFT.tokenMinter(tokenId), minter1);
    }

    function test_Burn_DoesNotDecrementTokenCount() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(100, 0, "ipfs://test1", "");

        assertEq(singlesNFT.totalTokens(), 1);

        vm.prank(minter1);
        singlesNFT.burn(minter1, tokenId, 100);

        assertEq(singlesNFT.totalTokens(), 1);
    }

    function test_Burn_AllowsMintMoreAfterBurn() public {
        vm.startPrank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(50, 100, "ipfs://test1", "");

        singlesNFT.burn(minter1, tokenId, 50);
        assertEq(singlesNFT.totalSupply(tokenId), 0);

        singlesNFT.mintMore(tokenId, 100, "");
        vm.stopPrank();

        assertEq(singlesNFT.totalSupply(tokenId), 100);
    }

    // ============================================
    //         PAUSE/UNPAUSE TESTS
    // ============================================

    function test_Pause_OnlyOwnerCanPause() public {
        vm.prank(owner);
        singlesNFT.pause();

        assertTrue(singlesNFT.paused());
    }

    function test_Pause_RevertsIfNotOwner() public {
        vm.prank(minter1);
        vm.expectRevert();
        singlesNFT.pause();
    }

    function test_Unpause_OnlyOwnerCanUnpause() public {
        vm.prank(owner);
        singlesNFT.pause();

        vm.prank(owner);
        singlesNFT.unpause();

        assertFalse(singlesNFT.paused());
    }

    function test_Unpause_RevertsIfNotOwner() public {
        vm.prank(owner);
        singlesNFT.pause();

        vm.prank(minter1);
        vm.expectRevert();
        singlesNFT.unpause();
    }

    // ============================================
    //         URI TESTS
    // ============================================

    function test_SetURI_OnlyOwnerCanSetBaseURI() public {
        vm.prank(owner);
        singlesNFT.setURI("https://newbaseuri.com/");

        // Base URI is set but individual token URIs override it
    }

    function test_SetURI_RevertsIfNotOwner() public {
        vm.prank(minter1);
        vm.expectRevert();
        singlesNFT.setURI("https://newbaseuri.com/");
    }

    function test_URI_ReturnsTokenURI() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(100, 0, "ipfs://QmTest123", "");

        assertEq(singlesNFT.uri(tokenId), "ipfs://QmTest123");
    }

    // ============================================
    //         VIEW FUNCTION TESTS
    // ============================================

    function test_CanMintMore_UnlimitedSupply() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(100, 0, "ipfs://test1", "");

        (bool canMint, uint256 available) = singlesNFT.canMintMore(tokenId);
        assertTrue(canMint);
        assertEq(available, 0); // 0 means unlimited
    }

    function test_CanMintMore_WithAvailableSupply() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(60, 100, "ipfs://test1", "");

        (bool canMint, uint256 available) = singlesNFT.canMintMore(tokenId);
        assertTrue(canMint);
        assertEq(available, 40);
    }

    function test_CanMintMore_MaxSupplyReached() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(100, 100, "ipfs://test1", "");

        (bool canMint, uint256 available) = singlesNFT.canMintMore(tokenId);
        assertFalse(canMint);
        assertEq(available, 0);
    }

    function test_GetMinter_ReturnsCorrectMinter() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(100, 0, "ipfs://test1", "");

        assertEq(singlesNFT.getMinter(tokenId), minter1);
    }

    function test_GetMinter_ReturnsZeroForNonExistent() public view {
        assertEq(singlesNFT.getMinter(999), address(0));
    }

    function test_TotalSupply_TracksCorrectly() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(100, 0, "ipfs://test1", "");

        assertEq(singlesNFT.totalSupply(tokenId), 100);

        vm.prank(minter1);
        singlesNFT.burn(minter1, tokenId, 30);

        assertEq(singlesNFT.totalSupply(tokenId), 70);
    }

    function test_SupportsInterface_ERC1155() public view {
        assertTrue(singlesNFT.supportsInterface(0xd9b67a26)); // ERC1155
    }

    function test_SupportsInterface_ERC165() public view {
        assertTrue(singlesNFT.supportsInterface(0x01ffc9a7)); // ERC165
    }

    // ============================================
    //         INTEGRATION TESTS
    // ============================================

    function test_Integration_MintTransferAndBurn() public {
        // Minter1 mints
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(100, 0, "ipfs://test1", "");

        // Minter1 transfers 50 to minter2
        vm.prank(minter1);
        singlesNFT.safeTransferFrom(minter1, minter2, tokenId, 50, "");

        assertEq(singlesNFT.balanceOf(minter1, tokenId), 50);
        assertEq(singlesNFT.balanceOf(minter2, tokenId), 50);

        // Minter2 burns their 50
        vm.prank(minter2);
        singlesNFT.burn(minter2, tokenId, 50);

        assertEq(singlesNFT.balanceOf(minter2, tokenId), 0);
        assertEq(singlesNFT.totalSupply(tokenId), 50);

        // Original minter is still preserved
        assertEq(singlesNFT.getMinter(tokenId), minter1);
    }

    function test_Integration_MultipleMintersDifferentTokens() public {
        vm.prank(minter1);
        uint256 token1 = singlesNFT.mintPublic(100, 0, "ipfs://minter1-token1", "");

        vm.prank(minter2);
        uint256 token2 = singlesNFT.mintPublic(50, 100, "ipfs://minter2-token1", "");

        vm.prank(minter1);
        uint256 token3 = singlesNFT.mintPublic(200, 0, "ipfs://minter1-token2", "");

        assertEq(singlesNFT.totalTokens(), 3);
        assertEq(singlesNFT.balanceOf(minter1, token1), 100);
        assertEq(singlesNFT.balanceOf(minter2, token2), 50);
        assertEq(singlesNFT.balanceOf(minter1, token3), 200);
        assertEq(singlesNFT.getMinter(token1), minter1);
        assertEq(singlesNFT.getMinter(token2), minter2);
        assertEq(singlesNFT.getMinter(token3), minter1);
    }

    function test_Integration_MintMoreUntilMaxSupply() public {
        vm.startPrank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(25, 100, "ipfs://test1", "");

        singlesNFT.mintMore(tokenId, 25, "");
        assertEq(singlesNFT.totalSupply(tokenId), 50);

        singlesNFT.mintMore(tokenId, 50, "");
        assertEq(singlesNFT.totalSupply(tokenId), 100);

        vm.expectRevert(Errors.ExceedsMaxSupply.selector);
        singlesNFT.mintMore(tokenId, 1, "");
        vm.stopPrank();
    }

    // ============================================
    //         FUZZ TESTS
    // ============================================

    function testFuzz_MintPublic_VariousAmounts(uint16 amount) public {
        vm.assume(amount > 0);

        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(amount, 0, "ipfs://test", "");

        assertEq(singlesNFT.balanceOf(minter1, tokenId), amount);
        assertEq(singlesNFT.totalSupply(tokenId), amount);
    }

    function testFuzz_MintPublic_VariousMaxSupplies(uint16 amount, uint16 maxSupply) public {
        vm.assume(amount > 0);
        vm.assume(maxSupply == 0 || maxSupply >= amount);

        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(amount, maxSupply, "ipfs://test", "");

        assertEq(singlesNFT.tokenMaxSupply(tokenId), maxSupply);
    }

    function testFuzz_MintPublic_VariousURIs(string memory uri) public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(100, 0, uri, "");

        assertEq(singlesNFT.uri(tokenId), uri);
    }

    function testFuzz_Transfer_VariousAmounts(uint16 amount, uint16 transferAmount) public {
        vm.assume(amount > 0);
        vm.assume(transferAmount > 0 && transferAmount <= amount);

        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(amount, 0, "ipfs://test", "");

        vm.prank(minter1);
        singlesNFT.safeTransferFrom(minter1, minter2, tokenId, transferAmount, "");

        assertEq(singlesNFT.balanceOf(minter1, tokenId), amount - transferAmount);
        assertEq(singlesNFT.balanceOf(minter2, tokenId), transferAmount);
    }
}

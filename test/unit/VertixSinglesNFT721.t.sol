// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VertixSinglesNFT721} from "../../src/nft/VertixSinglesNFT721.sol";
import {Errors} from "../../src/libraries/Errors.sol";

contract VertixSinglesNFT721Test is Test {
    VertixSinglesNFT721 public singlesNFT;

    address public owner;
    address public minter1;
    address public minter2;
    address public marketplace;

    event SingleNFTMinted(address indexed minter, uint256 indexed tokenId, string uri);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function setUp() public {
        owner = makeAddr("owner");
        minter1 = makeAddr("minter1");
        minter2 = makeAddr("minter2");
        marketplace = makeAddr("marketplace");

        singlesNFT = new VertixSinglesNFT721();
        singlesNFT.initialize("Vertix Singles", "VSINGLE", owner);
    }

    // ============================================
    //         INITIALIZATION TESTS
    // ============================================

    function test_Initialize_SetsNameAndSymbol() public view {
        assertEq(singlesNFT.name(), "Vertix Singles");
        assertEq(singlesNFT.symbol(), "VSINGLE");
    }

    function test_Initialize_SetsOwner() public view {
        assertEq(singlesNFT.owner(), owner);
    }

    function test_Initialize_RevertsOnZeroOwner() public {
        VertixSinglesNFT721 newNFT = new VertixSinglesNFT721();
        vm.expectRevert(Errors.ZeroAddress.selector);
        newNFT.initialize("Test", "TEST", address(0));
    }

    function test_Initialize_CanOnlyBeCalledOnce() public {
        vm.expectRevert();
        singlesNFT.initialize("Test", "TEST", owner);
    }

    function test_Initialize_StartsWithZeroSupply() public view {
        assertEq(singlesNFT.totalMinted(), 0);
    }

    // ============================================
    //         MINTING TESTS
    // ============================================

    function test_MintPublic_MintsSuccessfully() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic("ipfs://test1");

        assertEq(tokenId, 1);
        assertEq(singlesNFT.ownerOf(tokenId), minter1);
        assertEq(singlesNFT.totalMinted(), 1);
    }

    function test_MintPublic_EmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit SingleNFTMinted(minter1, 1, "ipfs://test1");

        vm.prank(minter1);
        singlesNFT.mintPublic("ipfs://test1");
    }

    function test_MintPublic_SetsTokenURI() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic("ipfs://test1");

        assertEq(singlesNFT.tokenURI(tokenId), "ipfs://test1");
    }

    function test_MintPublic_TracksMinter() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic("ipfs://test1");

        assertEq(singlesNFT.tokenMinter(tokenId), minter1);
        assertEq(singlesNFT.getMinter(tokenId), minter1);
    }

    function test_MintPublic_IncrementsTokenId() public {
        vm.prank(minter1);
        uint256 token1 = singlesNFT.mintPublic("ipfs://test1");

        vm.prank(minter2);
        uint256 token2 = singlesNFT.mintPublic("ipfs://test2");

        assertEq(token1, 1);
        assertEq(token2, 2);
    }

    function test_MintPublic_IncrementsSupply() public {
        vm.prank(minter1);
        singlesNFT.mintPublic("ipfs://test1");
        assertEq(singlesNFT.totalMinted(), 1);

        vm.prank(minter1);
        singlesNFT.mintPublic("ipfs://test2");
        assertEq(singlesNFT.totalMinted(), 2);

        vm.prank(minter2);
        singlesNFT.mintPublic("ipfs://test3");
        assertEq(singlesNFT.totalMinted(), 3);
    }

    function test_MintPublic_AllowsMultipleMintsByOneUser() public {
        vm.startPrank(minter1);

        uint256 token1 = singlesNFT.mintPublic("ipfs://test1");
        uint256 token2 = singlesNFT.mintPublic("ipfs://test2");
        uint256 token3 = singlesNFT.mintPublic("ipfs://test3");

        vm.stopPrank();

        assertEq(singlesNFT.ownerOf(token1), minter1);
        assertEq(singlesNFT.ownerOf(token2), minter1);
        assertEq(singlesNFT.ownerOf(token3), minter1);
        assertEq(singlesNFT.totalMinted(), 3);
    }

    function test_MintPublic_AllowsMultipleUsers() public {
        vm.prank(minter1);
        uint256 token1 = singlesNFT.mintPublic("ipfs://test1");

        vm.prank(minter2);
        uint256 token2 = singlesNFT.mintPublic("ipfs://test2");

        assertEq(singlesNFT.ownerOf(token1), minter1);
        assertEq(singlesNFT.ownerOf(token2), minter2);
        assertEq(singlesNFT.getMinter(token1), minter1);
        assertEq(singlesNFT.getMinter(token2), minter2);
    }

    function test_MintPublic_RevertsWhenPaused() public {
        vm.prank(owner);
        singlesNFT.pause();

        vm.prank(minter1);
        vm.expectRevert();
        singlesNFT.mintPublic("ipfs://test1");
    }

    function test_MintPublic_WorksWithEmptyURI() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic("");

        assertEq(singlesNFT.tokenURI(tokenId), "");
    }

    // ============================================
    //         TRANSFER TESTS
    // ============================================

    function test_Transfer_WorksAfterMinting() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic("ipfs://test1");

        vm.prank(minter1);
        singlesNFT.transferFrom(minter1, minter2, tokenId);

        assertEq(singlesNFT.ownerOf(tokenId), minter2);
    }

    function test_Transfer_PreservesOriginalMinter() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic("ipfs://test1");

        vm.prank(minter1);
        singlesNFT.transferFrom(minter1, minter2, tokenId);

        assertEq(singlesNFT.getMinter(tokenId), minter1);
    }

    function test_Transfer_AllowedWhenPaused() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic("ipfs://test1");

        vm.prank(owner);
        singlesNFT.pause();

        // Transfers are still allowed when paused (only minting is blocked)
        vm.prank(minter1);
        singlesNFT.transferFrom(minter1, minter2, tokenId);

        assertEq(singlesNFT.ownerOf(tokenId), minter2);
    }

    // ============================================
    //         APPROVAL TESTS
    // ============================================

    function test_Approve_WorksForMarketplace() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic("ipfs://test1");

        vm.prank(minter1);
        singlesNFT.approve(marketplace, tokenId);

        assertEq(singlesNFT.getApproved(tokenId), marketplace);
    }

    function test_SetApprovalForAll_WorksForMarketplace() public {
        vm.prank(minter1);
        singlesNFT.setApprovalForAll(marketplace, true);

        assertTrue(singlesNFT.isApprovedForAll(minter1, marketplace));
    }

    // ============================================
    //         BURN TESTS
    // ============================================

    function test_Burn_OwnerCanBurnToken() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic("ipfs://test1");

        vm.prank(minter1);
        singlesNFT.burn(tokenId);

        vm.expectRevert();
        singlesNFT.ownerOf(tokenId);
    }

    function test_Burn_DoesNotDecrementTotalMinted() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic("ipfs://test1");

        assertEq(singlesNFT.totalMinted(), 1);

        vm.prank(minter1);
        singlesNFT.burn(tokenId);

        assertEq(singlesNFT.totalMinted(), 1);
    }

    function test_Burn_PreservesMinterRecord() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic("ipfs://test1");

        vm.prank(minter1);
        singlesNFT.burn(tokenId);

        // Minter mapping still exists
        assertEq(singlesNFT.tokenMinter(tokenId), minter1);
    }

    function test_Burn_RevertsIfNotOwner() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic("ipfs://test1");

        vm.prank(minter2);
        vm.expectRevert();
        singlesNFT.burn(tokenId);
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

    function test_Pause_PreventsMinting() public {
        vm.prank(owner);
        singlesNFT.pause();

        vm.prank(minter1);
        vm.expectRevert();
        singlesNFT.mintPublic("ipfs://test1");
    }

    function test_Unpause_AllowsMinting() public {
        vm.prank(owner);
        singlesNFT.pause();

        vm.prank(owner);
        singlesNFT.unpause();

        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic("ipfs://test1");

        assertEq(singlesNFT.ownerOf(tokenId), minter1);
    }

    // ============================================
    //         VIEW FUNCTION TESTS
    // ============================================

    function test_GetMinter_ReturnsCorrectMinter() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic("ipfs://test1");

        assertEq(singlesNFT.getMinter(tokenId), minter1);
    }

    function test_GetMinter_ReturnsZeroForNonExistent() public view {
        assertEq(singlesNFT.getMinter(999), address(0));
    }

    function test_TokenURI_ReturnsCorrectURI() public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic("ipfs://QmTest123");

        assertEq(singlesNFT.tokenURI(tokenId), "ipfs://QmTest123");
    }

    function test_TokenURI_RevertsForNonExistentToken() public {
        vm.expectRevert();
        singlesNFT.tokenURI(999);
    }

    function test_SupportsInterface_ERC721() public view {
        assertTrue(singlesNFT.supportsInterface(0x80ac58cd)); // ERC721
    }

    function test_SupportsInterface_ERC165() public view {
        assertTrue(singlesNFT.supportsInterface(0x01ffc9a7)); // ERC165
    }

    // ============================================
    //         INTEGRATION TESTS
    // ============================================

    function test_Integration_MintApproveAndTransfer() public {
        // Minter1 mints
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic("ipfs://test1");

        // Minter1 approves marketplace
        vm.prank(minter1);
        singlesNFT.approve(marketplace, tokenId);

        // Marketplace transfers to minter2
        vm.prank(marketplace);
        singlesNFT.transferFrom(minter1, minter2, tokenId);

        assertEq(singlesNFT.ownerOf(tokenId), minter2);
        assertEq(singlesNFT.getMinter(tokenId), minter1);
    }

    function test_Integration_MultipleMintersDifferentTokens() public {
        vm.prank(minter1);
        uint256 token1 = singlesNFT.mintPublic("ipfs://minter1-token1");

        vm.prank(minter2);
        uint256 token2 = singlesNFT.mintPublic("ipfs://minter2-token1");

        vm.prank(minter1);
        uint256 token3 = singlesNFT.mintPublic("ipfs://minter1-token2");

        assertEq(singlesNFT.totalMinted(), 3);
        assertEq(singlesNFT.ownerOf(token1), minter1);
        assertEq(singlesNFT.ownerOf(token2), minter2);
        assertEq(singlesNFT.ownerOf(token3), minter1);
        assertEq(singlesNFT.getMinter(token1), minter1);
        assertEq(singlesNFT.getMinter(token2), minter2);
        assertEq(singlesNFT.getMinter(token3), minter1);
    }

    // ============================================
    //         FUZZ TESTS
    // ============================================

    function testFuzz_MintPublic_WithVariousURIs(string memory uri) public {
        vm.prank(minter1);
        uint256 tokenId = singlesNFT.mintPublic(uri);

        assertEq(singlesNFT.tokenURI(tokenId), uri);
        assertEq(singlesNFT.ownerOf(tokenId), minter1);
    }

    function testFuzz_MintPublic_MultipleMints(uint8 count) public {
        vm.assume(count > 0 && count <= 50);

        vm.startPrank(minter1);
        for (uint256 i = 0; i < count; i++) {
            singlesNFT.mintPublic(string(abi.encodePacked("ipfs://test", vm.toString(i))));
        }
        vm.stopPrank();

        assertEq(singlesNFT.totalMinted(), count);
    }
}

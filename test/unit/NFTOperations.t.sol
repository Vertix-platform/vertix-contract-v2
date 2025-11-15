// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {NFTOperations} from "../../src/libraries/NFTOperations.sol";
import {AssetTypes} from "../../src/libraries/AssetTypes.sol";
import {MockERC721} from "../mocks/MockERC721.sol";
import {MockERC1155} from "../mocks/MockERC1155.sol";
import {MockNFT} from "../mocks/MockNFT.sol";

contract NFTOperationsTest is Test {
    using NFTOperations for *;

    MockERC721 public nft721;
    MockERC1155 public nft1155;
    MockNFT public nftWithRoyalty;

    address public owner;
    address public operator;
    address public receiver;
    address public royaltyReceiver;

    uint256 public constant TOKEN_ID = 1;
    uint256 public constant QUANTITY = 10;

    function setUp() public {
        owner = makeAddr("owner");
        operator = makeAddr("operator");
        receiver = makeAddr("receiver");
        royaltyReceiver = makeAddr("royaltyReceiver");

        nft721 = new MockERC721();
        nft1155 = new MockERC1155();
        nftWithRoyalty = new MockNFT(true, royaltyReceiver, 0.1 ether);

        // Mint tokens
        nft721.mint(owner, TOKEN_ID);
        nft1155.mint(owner, TOKEN_ID, QUANTITY);
    }

    // ============================================
    //          TRANSFER NFT TESTS
    // ============================================

    function test_TransferNFT_ERC721_Success() public {
        vm.prank(owner);
        nft721.approve(address(this), TOKEN_ID);

        NFTOperations.transferNFT(address(nft721), owner, receiver, TOKEN_ID, 1, AssetTypes.TokenStandard.ERC721);

        assertEq(nft721.ownerOf(TOKEN_ID), receiver);
    }

    function test_TransferNFT_ERC1155_Success() public {
        vm.prank(owner);
        nft1155.setApprovalForAll(address(this), true);

        NFTOperations.transferNFT(address(nft1155), owner, receiver, TOKEN_ID, 5, AssetTypes.TokenStandard.ERC1155);

        assertEq(nft1155.balanceOf(receiver, TOKEN_ID), 5);
        assertEq(nft1155.balanceOf(owner, TOKEN_ID), 5);
    }

    function test_TransferNFT_ERC721_RevertsOnNotApproved() public {
        vm.expectRevert();
        NFTOperations.transferNFT(address(nft721), owner, receiver, TOKEN_ID, 1, AssetTypes.TokenStandard.ERC721);
    }

    function test_TransferNFT_ERC1155_RevertsOnInsufficientBalance() public {
        vm.prank(owner);
        nft1155.setApprovalForAll(address(this), true);

        vm.expectRevert();
        NFTOperations.transferNFT(
            address(nft1155),
            owner,
            receiver,
            TOKEN_ID,
            100, // More than balance
            AssetTypes.TokenStandard.ERC1155
        );
    }

    // ============================================
    //          VALIDATE OWNERSHIP TESTS
    // ============================================

    function test_ValidateOwnership_ERC721_Success() public view {
        NFTOperations.validateOwnership(address(nft721), TOKEN_ID, owner, 1, AssetTypes.TokenStandard.ERC721);
    }

    // Note: Cannot test revert cases with vm.expectRevert for library view functions
    // The validation functions will revert with custom errors when called from contracts

    function test_ValidateOwnership_ERC1155_Success() public view {
        NFTOperations.validateOwnership(address(nft1155), TOKEN_ID, owner, QUANTITY, AssetTypes.TokenStandard.ERC1155);
    }

    // ============================================
    //          VALIDATE APPROVAL TESTS
    // ============================================

    function test_ValidateApproval_ERC721_Success() public {
        vm.prank(owner);
        nft721.setApprovalForAll(operator, true);

        NFTOperations.validateApproval(address(nft721), owner, operator, AssetTypes.TokenStandard.ERC721);
    }

    function test_ValidateApproval_ERC1155_Success() public {
        vm.prank(owner);
        nft1155.setApprovalForAll(operator, true);

        NFTOperations.validateApproval(address(nft1155), owner, operator, AssetTypes.TokenStandard.ERC1155);
    }

    // ============================================
    //    VALIDATE APPROVAL WITH TOKEN ID TESTS
    // ============================================

    function test_ValidateApprovalWithTokenId_ERC721_ApprovalForAll() public {
        vm.prank(owner);
        nft721.setApprovalForAll(operator, true);

        NFTOperations.validateApprovalWithTokenId(
            address(nft721), owner, operator, TOKEN_ID, AssetTypes.TokenStandard.ERC721
        );
    }

    function test_ValidateApprovalWithTokenId_ERC721_IndividualApproval() public {
        vm.prank(owner);
        nft721.approve(operator, TOKEN_ID);

        NFTOperations.validateApprovalWithTokenId(
            address(nft721), owner, operator, TOKEN_ID, AssetTypes.TokenStandard.ERC721
        );
    }

    function test_ValidateApprovalWithTokenId_ERC1155_Success() public {
        vm.prank(owner);
        nft1155.setApprovalForAll(operator, true);

        NFTOperations.validateApprovalWithTokenId(
            address(nft1155), owner, operator, TOKEN_ID, AssetTypes.TokenStandard.ERC1155
        );
    }

    // ============================================
    //          GET ROYALTY INFO TESTS
    // ============================================

    function test_GetRoyaltyInfo_Success() public view {
        uint256 salePrice = 1 ether;
        (address _receiver, uint256 amount) = NFTOperations.getRoyaltyInfo(address(nftWithRoyalty), TOKEN_ID, salePrice);

        assertEq(_receiver, royaltyReceiver);
        assertEq(amount, 0.1 ether);
    }

    function test_GetRoyaltyInfo_CapsExcessiveRoyalty() public {
        uint256 salePrice = 1 ether;
        // Create NFT with excessive royalty (20%)
        MockNFT nftExcessiveRoyalty = new MockNFT(true, royaltyReceiver, 0.2 ether);

        (address _receiver, uint256 amount) =
            NFTOperations.getRoyaltyInfo(address(nftExcessiveRoyalty), TOKEN_ID, salePrice);

        assertEq(_receiver, royaltyReceiver);
        // Should be capped at 10% (MAX_ROYALTY_BPS)
        assertEq(amount, 0.1 ether);
    }

    function test_GetRoyaltyInfo_ReturnsZeroOnNoRoyalty() public {
        MockNFT nftNoRoyalty = new MockNFT(false, address(0), 0);

        (address _receiver, uint256 amount) = NFTOperations.getRoyaltyInfo(address(nftNoRoyalty), TOKEN_ID, 1 ether);

        assertEq(_receiver, address(0));
        assertEq(amount, 0);
    }

    function test_GetRoyaltyInfo_ReturnsZeroOnRevert() public view {
        // Use an address that doesn't support royaltyInfo
        (address _receiver, uint256 amount) = NFTOperations.getRoyaltyInfo(address(nft721), TOKEN_ID, 1 ether);

        assertEq(_receiver, address(0));
        assertEq(amount, 0);
    }

    // ============================================
    //       SUPPORTS ROYALTIES TESTS
    // ============================================

    function test_SupportsRoyalties_True() public view {
        bool supportsRoyalty = NFTOperations.supportsRoyalties(address(nftWithRoyalty));
        assertTrue(supportsRoyalty);
    }

    function test_SupportsRoyalties_False() public view {
        bool supportsRoyalty = NFTOperations.supportsRoyalties(address(nft721));
        assertFalse(supportsRoyalty);
    }

    // ============================================
    //          INTEGRATION TESTS
    // ============================================

    function test_CompleteFlow_ERC721() public {
        // Validate ownership
        NFTOperations.validateOwnership(address(nft721), TOKEN_ID, owner, 1, AssetTypes.TokenStandard.ERC721);

        // Approve
        vm.prank(owner);
        nft721.setApprovalForAll(address(this), true);

        // Validate approval
        NFTOperations.validateApprovalWithTokenId(
            address(nft721), owner, address(this), TOKEN_ID, AssetTypes.TokenStandard.ERC721
        );

        // Transfer
        NFTOperations.transferNFT(address(nft721), owner, receiver, TOKEN_ID, 1, AssetTypes.TokenStandard.ERC721);

        // Verify
        assertEq(nft721.ownerOf(TOKEN_ID), receiver);
    }

    function test_CompleteFlow_ERC1155() public {
        // Validate ownership
        NFTOperations.validateOwnership(address(nft1155), TOKEN_ID, owner, 5, AssetTypes.TokenStandard.ERC1155);

        // Approve
        vm.prank(owner);
        nft1155.setApprovalForAll(address(this), true);

        // Validate approval
        NFTOperations.validateApproval(address(nft1155), owner, address(this), AssetTypes.TokenStandard.ERC1155);

        // Transfer
        NFTOperations.transferNFT(address(nft1155), owner, receiver, TOKEN_ID, 5, AssetTypes.TokenStandard.ERC1155);

        // Verify
        assertEq(nft1155.balanceOf(receiver, TOKEN_ID), 5);
    }
}

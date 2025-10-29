// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../../src/nft/VertixNFT1155.sol";
import "../../src/libraries/AssetTypes.sol";

contract VertixNFT1155Test is Test {
    VertixNFT1155 public nft;

    address public creator = address(0x1);
    address public royaltyReceiver = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    address public unauthorized = address(0x5);

    string public constant NAME = "Vertix Multi-Edition";
    string public constant SYMBOL = "VTXM";
    string public constant BASE_URI = "ipfs://QmBase/";
    string public constant TOKEN_URI_1 = "ipfs://QmToken1";
    string public constant TOKEN_URI_2 = "ipfs://QmToken2";

    uint96 public constant ROYALTY_FEE = 500; // 5%

    function setUp() public {
        vm.prank(creator);
        nft = new VertixNFT1155(
            NAME,
            SYMBOL,
            BASE_URI,
            creator,
            royaltyReceiver,
            ROYALTY_FEE
        );
    }

    // ============================================
    // CONSTRUCTOR TESTS
    // ============================================

    function test_constructor_Success() public {
        assertEq(nft.name(), NAME);
        assertEq(nft.symbol(), SYMBOL);
        assertEq(nft.owner(), creator);
        assertFalse(nft.paused());
    }

    function test_constructor_WithRoyalty() public {
        (address receiver, uint256 royalty) = nft.royaltyInfo(0, 1000);
        assertEq(receiver, royaltyReceiver);
        assertEq(royalty, 50); // 5% of 1000
    }

    function test_constructor_WithoutRoyalty() public {
        VertixNFT1155 noRoyaltyNFT = new VertixNFT1155(
            NAME,
            SYMBOL,
            BASE_URI,
            creator,
            address(0),
            0
        );

        (address receiver, uint256 royalty) = noRoyaltyNFT.royaltyInfo(0, 1000);
        assertEq(receiver, address(0));
        assertEq(royalty, 0);
    }

    // ============================================
    // CREATE TOKEN TESTS
    // ============================================

    function test_create_Success() public {
        uint256 initialSupply = 100;
        uint256 maxSupply = 1000;

        vm.prank(creator);
        uint256 tokenId = nft.create(initialSupply, TOKEN_URI_1, maxSupply);

        assertEq(tokenId, 0);
        assertEq(nft.balanceOf(creator, tokenId), initialSupply);
        assertEq(nft.totalSupply(tokenId), initialSupply);
        assertEq(nft.uri(tokenId), TOKEN_URI_1);
        assertEq(nft.tokenMaxSupply(tokenId), maxSupply);
    }

    function test_create_WithZeroInitialSupply() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(0, TOKEN_URI_1, 1000);

        assertEq(nft.balanceOf(creator, tokenId), 0);
        assertEq(nft.totalSupply(tokenId), 0);
    }

    function test_create_WithUnlimitedSupply() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, TOKEN_URI_1, 0);

        assertEq(nft.tokenMaxSupply(tokenId), 0); // Unlimited
    }

    function test_create_MultipleTokens() public {
        vm.startPrank(creator);

        uint256 tokenId1 = nft.create(100, TOKEN_URI_1, 1000);
        uint256 tokenId2 = nft.create(200, TOKEN_URI_2, 2000);

        vm.stopPrank();

        assertEq(tokenId1, 0);
        assertEq(tokenId2, 1);
        assertEq(nft.balanceOf(creator, tokenId1), 100);
        assertEq(nft.balanceOf(creator, tokenId2), 200);
    }

    function test_create_RevertIf_NotOwner() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                unauthorized
            )
        );
        nft.create(100, TOKEN_URI_1, 1000);
    }

    // ============================================
    // MINT TESTS
    // ============================================

    function test_mint_Success() public {
        vm.startPrank(creator);

        uint256 tokenId = nft.create(0, TOKEN_URI_1, 1000);
        nft.mint(user1, tokenId, 50);

        vm.stopPrank();

        assertEq(nft.balanceOf(user1, tokenId), 50);
        assertEq(nft.totalSupply(tokenId), 50);
    }

    function test_mint_MultipleTimes() public {
        vm.startPrank(creator);

        uint256 tokenId = nft.create(0, TOKEN_URI_1, 1000);
        nft.mint(user1, tokenId, 50);
        nft.mint(user1, tokenId, 30);

        vm.stopPrank();

        assertEq(nft.balanceOf(user1, tokenId), 80);
        assertEq(nft.totalSupply(tokenId), 80);
    }

    function test_mint_ToMultipleUsers() public {
        vm.startPrank(creator);

        uint256 tokenId = nft.create(0, TOKEN_URI_1, 1000);
        nft.mint(user1, tokenId, 50);
        nft.mint(user2, tokenId, 30);

        vm.stopPrank();

        assertEq(nft.balanceOf(user1, tokenId), 50);
        assertEq(nft.balanceOf(user2, tokenId), 30);
        assertEq(nft.totalSupply(tokenId), 80);
    }

    function test_mint_RevertIf_TokenDoesNotExist() public {
        vm.prank(creator);
        vm.expectRevert("Token doesn't exist");
        nft.mint(user1, 999, 50);
    }

    function test_mint_RevertIf_MaxSupplyReached() public {
        vm.startPrank(creator);

        uint256 tokenId = nft.create(0, TOKEN_URI_1, 100);
        nft.mint(user1, tokenId, 100);

        vm.expectRevert("Max supply reached");
        nft.mint(user1, tokenId, 1);

        vm.stopPrank();
    }

    function test_mint_UnlimitedSupply() public {
        vm.startPrank(creator);

        uint256 tokenId = nft.create(0, TOKEN_URI_1, 0); // Unlimited

        // Mint large amounts
        nft.mint(user1, tokenId, 1000);
        nft.mint(user1, tokenId, 1000);
        nft.mint(user1, tokenId, 1000);

        vm.stopPrank();

        assertEq(nft.balanceOf(user1, tokenId), 3000);
    }

    function test_mint_RevertIf_NotOwner() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(0, TOKEN_URI_1, 1000);

        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                unauthorized
            )
        );
        nft.mint(user1, tokenId, 50);
    }

    function test_mint_RevertIf_Paused() public {
        vm.startPrank(creator);

        uint256 tokenId = nft.create(0, TOKEN_URI_1, 1000);
        nft.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        nft.mint(user1, tokenId, 50);

        vm.stopPrank();
    }

    // ============================================
    // MINT BATCH TESTS
    // ============================================

    function test_mintBatch_Success() public {
        vm.startPrank(creator);

        uint256 tokenId1 = nft.create(0, TOKEN_URI_1, 1000);
        uint256 tokenId2 = nft.create(0, TOKEN_URI_2, 2000);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 50;
        amounts[1] = 100;

        nft.mintBatch(user1, tokenIds, amounts);

        vm.stopPrank();

        assertEq(nft.balanceOf(user1, tokenId1), 50);
        assertEq(nft.balanceOf(user1, tokenId2), 100);
    }

    function test_mintBatch_RevertIf_NotOwner() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(0, TOKEN_URI_1, 1000);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 50;

        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                unauthorized
            )
        );
        nft.mintBatch(user1, tokenIds, amounts);
    }

    function test_mintBatch_RevertIf_Paused() public {
        vm.startPrank(creator);

        uint256 tokenId = nft.create(0, TOKEN_URI_1, 1000);
        nft.pause();

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 50;

        vm.expectRevert(Pausable.EnforcedPause.selector);
        nft.mintBatch(user1, tokenIds, amounts);

        vm.stopPrank();
    }

    // ============================================
    // BURN TESTS
    // ============================================

    function test_burn_Success() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, TOKEN_URI_1, 1000);

        vm.prank(creator);
        nft.burn(creator, tokenId, 30);

        assertEq(nft.balanceOf(creator, tokenId), 70);
        assertEq(nft.totalSupply(tokenId), 70);
    }

    function test_burn_AllTokens() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, TOKEN_URI_1, 1000);

        vm.prank(creator);
        nft.burn(creator, tokenId, 100);

        assertEq(nft.balanceOf(creator, tokenId), 0);
        assertEq(nft.totalSupply(tokenId), 0);
    }

    function test_burn_RevertIf_InsufficientBalance() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, TOKEN_URI_1, 1000);

        vm.prank(creator);
        vm.expectRevert();
        nft.burn(creator, tokenId, 101);
    }

    function test_burnBatch_Success() public {
        vm.startPrank(creator);

        uint256 tokenId1 = nft.create(100, TOKEN_URI_1, 1000);
        uint256 tokenId2 = nft.create(200, TOKEN_URI_2, 2000);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 30;
        amounts[1] = 50;

        nft.burnBatch(creator, tokenIds, amounts);

        vm.stopPrank();

        assertEq(nft.balanceOf(creator, tokenId1), 70);
        assertEq(nft.balanceOf(creator, tokenId2), 150);
    }

    // ============================================
    // TRANSFER TESTS
    // ============================================

    function test_safeTransferFrom_Success() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, TOKEN_URI_1, 1000);

        vm.prank(creator);
        nft.safeTransferFrom(creator, user1, tokenId, 30, "");

        assertEq(nft.balanceOf(creator, tokenId), 70);
        assertEq(nft.balanceOf(user1, tokenId), 30);
    }

    function test_safeTransferFrom_RevertIf_Paused() public {
        vm.startPrank(creator);

        uint256 tokenId = nft.create(100, TOKEN_URI_1, 1000);
        nft.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        nft.safeTransferFrom(creator, user1, tokenId, 30, "");

        vm.stopPrank();
    }

    function test_safeBatchTransferFrom_Success() public {
        vm.startPrank(creator);

        uint256 tokenId1 = nft.create(100, TOKEN_URI_1, 1000);
        uint256 tokenId2 = nft.create(200, TOKEN_URI_2, 2000);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 30;
        amounts[1] = 50;

        nft.safeBatchTransferFrom(creator, user1, tokenIds, amounts, "");

        vm.stopPrank();

        assertEq(nft.balanceOf(user1, tokenId1), 30);
        assertEq(nft.balanceOf(user1, tokenId2), 50);
    }

    // ============================================
    // URI TESTS
    // ============================================

    function test_uri() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, TOKEN_URI_1, 1000);

        assertEq(nft.uri(tokenId), TOKEN_URI_1);
    }

    function test_setURI_Success() public {
        vm.startPrank(creator);

        uint256 tokenId = nft.create(100, TOKEN_URI_1, 1000);

        string memory newURI = "ipfs://QmNewToken";
        nft.setURI(tokenId, newURI);

        vm.stopPrank();

        assertEq(nft.uri(tokenId), newURI);
    }

    function test_setURI_RevertIf_NotOwner() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, TOKEN_URI_1, 1000);

        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                unauthorized
            )
        );
        nft.setURI(tokenId, "ipfs://QmNewToken");
    }

    // ============================================
    // ROYALTY TESTS
    // ============================================

    function test_royaltyInfo() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, TOKEN_URI_1, 1000);

        uint256 salePrice = 1 ether;
        (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(
            tokenId,
            salePrice
        );

        assertEq(receiver, royaltyReceiver);
        assertEq(royaltyAmount, (salePrice * ROYALTY_FEE) / 10000);
    }

    function test_setDefaultRoyalty_Success() public {
        address newReceiver = address(0x99);
        uint96 newFee = 250; // 2.5%

        vm.prank(creator);
        nft.setDefaultRoyalty(newReceiver, newFee);

        vm.prank(creator);
        uint256 tokenId = nft.create(100, TOKEN_URI_1, 1000);

        (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(
            tokenId,
            1000
        );
        assertEq(receiver, newReceiver);
        assertEq(royaltyAmount, 25);
    }

    function test_setDefaultRoyalty_RevertIf_TooHigh() public {
        vm.prank(creator);
        vm.expectRevert("Royalty too high");
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

        uint256 tokenId = nft.create(100, TOKEN_URI_1, 1000);

        address specialReceiver = address(0x88);
        uint96 specialFee = 750; // 7.5%

        nft.setTokenRoyalty(tokenId, specialReceiver, specialFee);

        vm.stopPrank();

        (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(
            tokenId,
            1000
        );
        assertEq(receiver, specialReceiver);
        assertEq(royaltyAmount, 75);
    }

    function test_setTokenRoyalty_RevertIf_TooHigh() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, TOKEN_URI_1, 1000);

        vm.prank(creator);
        vm.expectRevert("Royalty too high");
        nft.setTokenRoyalty(tokenId, royaltyReceiver, 1100);
    }

    // ============================================
    // ADMIN TESTS
    // ============================================

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
    // VIEW FUNCTION TESTS
    // ============================================

    function test_supportsInterface() public {
        // ERC1155
        assertTrue(nft.supportsInterface(0xd9b67a26));
        // ERC2981
        assertTrue(nft.supportsInterface(0x2a55205a));
    }

    function test_totalSupply() public {
        vm.startPrank(creator);

        uint256 tokenId = nft.create(100, TOKEN_URI_1, 1000);
        assertEq(nft.totalSupply(tokenId), 100);

        nft.mint(user1, tokenId, 50);
        assertEq(nft.totalSupply(tokenId), 150);

        vm.stopPrank();

        vm.prank(creator);
        nft.burn(creator, tokenId, 30);
        assertEq(nft.totalSupply(tokenId), 120);
    }

    function test_exists() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, TOKEN_URI_1, 1000);

        assertTrue(nft.exists(tokenId));
        assertFalse(nft.exists(999));
    }

    // ============================================
    // FUZZ TESTS
    // ============================================

    function testFuzz_create(uint256 initialSupply, uint256 maxSupply) public {
        initialSupply = bound(initialSupply, 0, 1000000);
        maxSupply = bound(maxSupply, initialSupply, 1000000);

        vm.prank(creator);
        uint256 tokenId = nft.create(initialSupply, TOKEN_URI_1, maxSupply);

        assertEq(nft.totalSupply(tokenId), initialSupply);
        assertEq(nft.tokenMaxSupply(tokenId), maxSupply);
    }

    function testFuzz_mint(uint256 amount) public {
        amount = bound(amount, 1, 100000);

        vm.startPrank(creator);

        uint256 tokenId = nft.create(0, TOKEN_URI_1, 0); // Unlimited supply
        nft.mint(user1, tokenId, amount);

        vm.stopPrank();

        assertEq(nft.balanceOf(user1, tokenId), amount);
    }

    function testFuzz_royaltyInfo(uint256 salePrice) public {
        salePrice = bound(salePrice, 1, 1000000 ether);

        vm.prank(creator);
        uint256 tokenId = nft.create(100, TOKEN_URI_1, 1000);

        (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(
            tokenId,
            salePrice
        );

        assertEq(receiver, royaltyReceiver);
        assertEq(royaltyAmount, (salePrice * ROYALTY_FEE) / 10000);
    }

    function testFuzz_transfer(
        uint256 initialAmount,
        uint256 transferAmount
    ) public {
        initialAmount = bound(initialAmount, 1, 100000);
        transferAmount = bound(transferAmount, 1, initialAmount);

        vm.prank(creator);
        uint256 tokenId = nft.create(initialAmount, TOKEN_URI_1, 0);

        vm.prank(creator);
        nft.safeTransferFrom(creator, user1, tokenId, transferAmount, "");

        assertEq(
            nft.balanceOf(creator, tokenId),
            initialAmount - transferAmount
        );
        assertEq(nft.balanceOf(user1, tokenId), transferAmount);
    }

    // ============================================
    // INTEGRATION TESTS
    // ============================================

    function test_integration_CreateMintTransferBurn() public {
        // Create token
        vm.prank(creator);
        uint256 tokenId = nft.create(100, TOKEN_URI_1, 1000);

        assertEq(nft.balanceOf(creator, tokenId), 100);
        assertEq(nft.totalSupply(tokenId), 100);

        // Mint more
        vm.prank(creator);
        nft.mint(user1, tokenId, 50);

        assertEq(nft.balanceOf(user1, tokenId), 50);
        assertEq(nft.totalSupply(tokenId), 150);

        // Transfer
        vm.prank(user1);
        nft.safeTransferFrom(user1, user2, tokenId, 20, "");

        assertEq(nft.balanceOf(user1, tokenId), 30);
        assertEq(nft.balanceOf(user2, tokenId), 20);

        // Burn
        vm.prank(user2);
        nft.burn(user2, tokenId, 10);

        assertEq(nft.balanceOf(user2, tokenId), 10);
        assertEq(nft.totalSupply(tokenId), 140);
    }

    function test_integration_MultipleTokens() public {
        vm.startPrank(creator);

        // Create multiple tokens
        uint256 tokenId1 = nft.create(100, TOKEN_URI_1, 1000);
        uint256 tokenId2 = nft.create(200, TOKEN_URI_2, 2000);

        // Mint additional amounts
        nft.mint(user1, tokenId1, 50);
        nft.mint(user1, tokenId2, 100);

        vm.stopPrank();

        // Verify balances
        assertEq(nft.balanceOf(creator, tokenId1), 100);
        assertEq(nft.balanceOf(creator, tokenId2), 200);
        assertEq(nft.balanceOf(user1, tokenId1), 50);
        assertEq(nft.balanceOf(user1, tokenId2), 100);

        // Batch transfer
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = tokenId1;
        tokenIds[1] = tokenId2;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 20;
        amounts[1] = 30;

        vm.prank(user1);
        nft.safeBatchTransferFrom(user1, user2, tokenIds, amounts, "");

        assertEq(nft.balanceOf(user2, tokenId1), 20);
        assertEq(nft.balanceOf(user2, tokenId2), 30);
    }

    function test_integration_PauseAndUnpause() public {
        vm.prank(creator);
        uint256 tokenId = nft.create(100, TOKEN_URI_1, 1000);

        // Pause
        vm.prank(creator);
        nft.pause();

        // Can't transfer when paused
        vm.prank(creator);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        nft.safeTransferFrom(creator, user1, tokenId, 30, "");

        // Unpause
        vm.prank(creator);
        nft.unpause();

        // Can transfer after unpause
        vm.prank(creator);
        nft.safeTransferFrom(creator, user1, tokenId, 30, "");

        assertEq(nft.balanceOf(user1, tokenId), 30);
    }

    function test_integration_MaxSupplyEnforcement() public {
        vm.startPrank(creator);

        uint256 tokenId = nft.create(50, TOKEN_URI_1, 100);

        // Can mint up to max supply
        nft.mint(user1, tokenId, 30);
        assertEq(nft.totalSupply(tokenId), 80);

        nft.mint(user1, tokenId, 20);
        assertEq(nft.totalSupply(tokenId), 100);

        // Cannot exceed max supply
        vm.expectRevert("Max supply reached");
        nft.mint(user1, tokenId, 1);

        vm.stopPrank();
    }
}

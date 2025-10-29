// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../../src/nft/NFTFactory.sol";
import "../../src/nft/VertixNFT721.sol";
import "../../src/nft/VertixNFT1155.sol";
import "../../src/access/RoleManager.sol";

contract NFTFactoryTest is Test {
    NFTFactory public factory;
    RoleManager public roleManager;

    address public admin = address(0x1);
    address public feeManager = address(0x2);
    address public creator1 = address(0x3);
    address public creator2 = address(0x4);
    address public unauthorized = address(0x5);

    string public constant NAME_721 = "Test Collection 721";
    string public constant SYMBOL_721 = "TST721";
    string public constant NAME_1155 = "Test Collection 1155";
    string public constant SYMBOL_1155 = "TST1155";
    string public constant BASE_URI = "ipfs://QmBase/";
    string public constant URI_1155 = "ipfs://Qm1155/";

    uint96 public constant ROYALTY_FEE = 500; // 5%
    uint256 public constant MAX_SUPPLY = 1000;
    uint256 public constant CREATION_FEE = 0.01 ether;

    // Events
    event Collection721Created(
        address indexed collection,
        address indexed creator,
        string name,
        string symbol
    );

    event Collection1155Created(
        address indexed collection,
        address indexed creator,
        string name,
        string symbol
    );

    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);

    function setUp() public {
        vm.startPrank(admin);

        // Deploy RoleManager
        roleManager = new RoleManager(admin);

        // Grant fee manager role
        roleManager.grantRole(roleManager.FEE_MANAGER_ROLE(), feeManager);

        vm.stopPrank();

        // Deploy NFTFactory
        factory = new NFTFactory(address(roleManager));

        // Fund creators
        vm.deal(creator1, 10 ether);
        vm.deal(creator2, 10 ether);
    }

    // ============================================
    // CONSTRUCTOR TESTS
    // ============================================

    function test_constructor_Success() public {
        assertEq(address(factory.roleManager()), address(roleManager));
        assertEq(factory.creationFee(), 0);
        assertEq(factory.getTotalCollections(), 0);

        // Check implementation contracts deployed
        assertTrue(factory.nft721Implementation() != address(0));
        assertTrue(factory.nft1155Implementation() != address(0));
    }

    function test_constructor_RevertIf_InvalidRoleManager() public {
        vm.expectRevert("Invalid role manager");
        new NFTFactory(address(0));
    }

    // ============================================
    // CREATE COLLECTION 721 TESTS
    // ============================================

    function test_createCollection721_Success() public {
        vm.prank(creator1);

        vm.expectEmit(false, true, true, true);
        emit Collection721Created(address(0), creator1, NAME_721, SYMBOL_721);

        address collection = factory.createCollection721(
            NAME_721,
            SYMBOL_721,
            creator1,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );

        // Verify collection was created
        assertTrue(collection != address(0));
        assertTrue(factory.isVertixCollection(collection));

        // Verify tracking
        assertEq(factory.getTotalCollections(), 1);
        address[] memory allCollections = factory.getAllCollections();
        assertEq(allCollections.length, 1);
        assertEq(allCollections[0], collection);

        // Verify creator tracking
        address[] memory creatorCollections = factory.getCreatorCollections(
            creator1
        );
        assertEq(creatorCollections.length, 1);
        assertEq(creatorCollections[0], collection);
    }

    function test_createCollection721_WithCreationFee() public {
        // Set creation fee
        vm.prank(feeManager);
        factory.setCreationFee(CREATION_FEE);

        // Create collection with fee
        vm.prank(creator1);
        address collection = factory.createCollection721{value: CREATION_FEE}(
            NAME_721,
            SYMBOL_721,
            creator1,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );

        assertTrue(collection != address(0));
        assertEq(address(factory).balance, CREATION_FEE);
    }

    function test_createCollection721_MultipleCollections() public {
        vm.startPrank(creator1);

        address collection1 = factory.createCollection721(
            "Collection 1",
            "COL1",
            creator1,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );

        address collection2 = factory.createCollection721(
            "Collection 2",
            "COL2",
            creator1,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );

        vm.stopPrank();

        assertTrue(collection1 != collection2);
        assertEq(factory.getTotalCollections(), 2);

        address[] memory creatorCollections = factory.getCreatorCollections(
            creator1
        );
        assertEq(creatorCollections.length, 2);
    }

    function test_createCollection721_MultipleCreators() public {
        vm.prank(creator1);
        address collection1 = factory.createCollection721(
            NAME_721,
            SYMBOL_721,
            creator1,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );

        vm.prank(creator2);
        address collection2 = factory.createCollection721(
            NAME_721,
            SYMBOL_721,
            creator2,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );

        assertEq(factory.getTotalCollections(), 2);
        assertEq(factory.getCreatorCollections(creator1).length, 1);
        assertEq(factory.getCreatorCollections(creator2).length, 1);
    }

    function test_createCollection721_RevertIf_InsufficientFee() public {
        vm.prank(feeManager);
        factory.setCreationFee(CREATION_FEE);

        vm.prank(creator1);
        vm.expectRevert("Insufficient creation fee");
        factory.createCollection721{value: CREATION_FEE - 1}(
            NAME_721,
            SYMBOL_721,
            creator1,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );
    }

    function test_createCollection721_RevertIf_EmptyName() public {
        vm.prank(creator1);
        vm.expectRevert("Empty name");
        factory.createCollection721(
            "",
            SYMBOL_721,
            creator1,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );
    }

    function test_createCollection721_RevertIf_EmptySymbol() public {
        vm.prank(creator1);
        vm.expectRevert("Empty symbol");
        factory.createCollection721(
            NAME_721,
            "",
            creator1,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );
    }

    function test_createCollection721_WithExcessFee() public {
        vm.prank(feeManager);
        factory.setCreationFee(CREATION_FEE);

        // Send more than required fee
        vm.prank(creator1);
        address collection = factory.createCollection721{
            value: CREATION_FEE * 2
        }(NAME_721, SYMBOL_721, creator1, ROYALTY_FEE, MAX_SUPPLY, BASE_URI);

        assertTrue(collection != address(0));
        assertEq(address(factory).balance, CREATION_FEE * 2);
    }

    // ============================================
    // CREATE COLLECTION 1155 TESTS
    // ============================================

    function test_createCollection1155_Success() public {
        vm.prank(creator1);

        vm.expectEmit(false, true, true, true);
        emit Collection1155Created(
            address(0),
            creator1,
            NAME_1155,
            SYMBOL_1155
        );

        address collection = factory.createCollection1155(
            NAME_1155,
            SYMBOL_1155,
            URI_1155,
            creator1,
            ROYALTY_FEE
        );

        assertTrue(collection != address(0));
        assertTrue(factory.isVertixCollection(collection));
        assertEq(factory.getTotalCollections(), 1);
    }

    function test_createCollection1155_WithCreationFee() public {
        vm.prank(feeManager);
        factory.setCreationFee(CREATION_FEE);

        vm.prank(creator1);
        address collection = factory.createCollection1155{value: CREATION_FEE}(
            NAME_1155,
            SYMBOL_1155,
            URI_1155,
            creator1,
            ROYALTY_FEE
        );

        assertTrue(collection != address(0));
        assertEq(address(factory).balance, CREATION_FEE);
    }

    function test_createCollection1155_MultipleCollections() public {
        vm.startPrank(creator1);

        address collection1 = factory.createCollection1155(
            "Collection 1",
            "COL1",
            URI_1155,
            creator1,
            ROYALTY_FEE
        );

        address collection2 = factory.createCollection1155(
            "Collection 2",
            "COL2",
            URI_1155,
            creator1,
            ROYALTY_FEE
        );

        vm.stopPrank();

        assertTrue(collection1 != collection2);
        assertEq(factory.getTotalCollections(), 2);
    }

    function test_createCollection1155_RevertIf_InsufficientFee() public {
        vm.prank(feeManager);
        factory.setCreationFee(CREATION_FEE);

        vm.prank(creator1);
        vm.expectRevert("Insufficient creation fee");
        factory.createCollection1155{value: CREATION_FEE - 1}(
            NAME_1155,
            SYMBOL_1155,
            URI_1155,
            creator1,
            ROYALTY_FEE
        );
    }

    function test_createCollection1155_RevertIf_EmptyName() public {
        vm.prank(creator1);
        vm.expectRevert("Empty name");
        factory.createCollection1155(
            "",
            SYMBOL_1155,
            URI_1155,
            creator1,
            ROYALTY_FEE
        );
    }

    // ============================================
    // ADMIN FUNCTION TESTS
    // ============================================

    function test_setCreationFee_Success() public {
        vm.prank(feeManager);

        vm.expectEmit(true, true, true, true);
        emit CreationFeeUpdated(0, CREATION_FEE);

        factory.setCreationFee(CREATION_FEE);

        assertEq(factory.creationFee(), CREATION_FEE);
    }

    function test_setCreationFee_UpdateExisting() public {
        vm.startPrank(feeManager);

        factory.setCreationFee(CREATION_FEE);
        assertEq(factory.creationFee(), CREATION_FEE);

        uint256 newFee = CREATION_FEE * 2;

        vm.expectEmit(true, true, true, true);
        emit CreationFeeUpdated(CREATION_FEE, newFee);

        factory.setCreationFee(newFee);

        vm.stopPrank();

        assertEq(factory.creationFee(), newFee);
    }

    function test_setCreationFee_SetToZero() public {
        vm.startPrank(feeManager);

        factory.setCreationFee(CREATION_FEE);
        factory.setCreationFee(0);

        vm.stopPrank();

        assertEq(factory.creationFee(), 0);
    }

    function test_setCreationFee_RevertIf_NotFeeManager() public {
        vm.prank(unauthorized);
        vm.expectRevert("Not fee manager");
        factory.setCreationFee(CREATION_FEE);
    }

    function test_withdrawFees_Success() public {
        // Set fee and create collections
        vm.prank(feeManager);
        factory.setCreationFee(CREATION_FEE);

        vm.prank(creator1);
        factory.createCollection721{value: CREATION_FEE}(
            NAME_721,
            SYMBOL_721,
            creator1,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );

        vm.prank(creator2);
        factory.createCollection721{value: CREATION_FEE}(
            NAME_721,
            SYMBOL_721,
            creator2,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );

        assertEq(address(factory).balance, CREATION_FEE * 2);

        uint256 adminBalanceBefore = admin.balance;

        // Withdraw fees
        vm.prank(admin);
        factory.withdrawFees();

        assertEq(address(factory).balance, 0);
        assertEq(admin.balance, adminBalanceBefore + (CREATION_FEE * 2));
    }

    function test_withdrawFees_RevertIf_NoFees() public {
        vm.prank(admin);
        vm.expectRevert("No fees to withdraw");
        factory.withdrawFees();
    }

    function test_withdrawFees_RevertIf_NotAdmin() public {
        // Set fee and create collection
        vm.prank(feeManager);
        factory.setCreationFee(CREATION_FEE);

        vm.prank(creator1);
        factory.createCollection721{value: CREATION_FEE}(
            NAME_721,
            SYMBOL_721,
            creator1,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );

        vm.prank(unauthorized);
        vm.expectRevert("Not admin");
        factory.withdrawFees();
    }

    // ============================================
    // VIEW FUNCTION TESTS
    // ============================================

    function test_getCreatorCollections_Empty() public {
        address[] memory collections = factory.getCreatorCollections(creator1);
        assertEq(collections.length, 0);
    }

    function test_getCreatorCollections_Single() public {
        vm.prank(creator1);
        address collection = factory.createCollection721(
            NAME_721,
            SYMBOL_721,
            creator1,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );

        address[] memory collections = factory.getCreatorCollections(creator1);
        assertEq(collections.length, 1);
        assertEq(collections[0], collection);
    }

    function test_getCreatorCollections_Multiple() public {
        vm.startPrank(creator1);

        address collection1 = factory.createCollection721(
            "Collection 1",
            "COL1",
            creator1,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );

        address collection2 = factory.createCollection1155(
            "Collection 2",
            "COL2",
            URI_1155,
            creator1,
            ROYALTY_FEE
        );

        vm.stopPrank();

        address[] memory collections = factory.getCreatorCollections(creator1);
        assertEq(collections.length, 2);
        assertEq(collections[0], collection1);
        assertEq(collections[1], collection2);
    }

    function test_getAllCollections_Empty() public {
        address[] memory collections = factory.getAllCollections();
        assertEq(collections.length, 0);
    }

    function test_getAllCollections_Multiple() public {
        vm.prank(creator1);
        address collection1 = factory.createCollection721(
            NAME_721,
            SYMBOL_721,
            creator1,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );

        vm.prank(creator2);
        address collection2 = factory.createCollection1155(
            NAME_1155,
            SYMBOL_1155,
            URI_1155,
            creator2,
            ROYALTY_FEE
        );

        address[] memory collections = factory.getAllCollections();
        assertEq(collections.length, 2);
        assertEq(collections[0], collection1);
        assertEq(collections[1], collection2);
    }

    function test_getTotalCollections() public {
        assertEq(factory.getTotalCollections(), 0);

        vm.prank(creator1);
        factory.createCollection721(
            NAME_721,
            SYMBOL_721,
            creator1,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );

        assertEq(factory.getTotalCollections(), 1);

        vm.prank(creator1);
        factory.createCollection1155(
            NAME_1155,
            SYMBOL_1155,
            URI_1155,
            creator1,
            ROYALTY_FEE
        );

        assertEq(factory.getTotalCollections(), 2);
    }

    function test_isVertixCollection() public {
        vm.prank(creator1);
        address collection = factory.createCollection721(
            NAME_721,
            SYMBOL_721,
            creator1,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );

        assertTrue(factory.isVertixCollection(collection));
        assertFalse(factory.isVertixCollection(address(0x999)));
    }

    // ============================================
    // FUZZ TESTS
    // ============================================

    function testFuzz_createCollection721_WithFee(uint256 fee) public {
        fee = bound(fee, 0, 1 ether);

        vm.prank(feeManager);
        factory.setCreationFee(fee);

        vm.deal(creator1, fee);
        vm.prank(creator1);
        address collection = factory.createCollection721{value: fee}(
            NAME_721,
            SYMBOL_721,
            creator1,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );

        assertTrue(collection != address(0));
        assertEq(address(factory).balance, fee);
    }

    function testFuzz_createMultipleCollections(uint8 count) public {
        count = uint8(bound(count, 1, 50));

        vm.startPrank(creator1);

        for (uint8 i = 0; i < count; i++) {
            factory.createCollection721(
                string(abi.encodePacked("Collection ", vm.toString(i))),
                string(abi.encodePacked("COL", vm.toString(i))),
                creator1,
                ROYALTY_FEE,
                MAX_SUPPLY,
                BASE_URI
            );
        }

        vm.stopPrank();

        assertEq(factory.getTotalCollections(), count);
        assertEq(factory.getCreatorCollections(creator1).length, count);
    }

    function testFuzz_setCreationFee(uint256 fee) public {
        fee = bound(fee, 0, 10 ether);

        vm.prank(feeManager);
        factory.setCreationFee(fee);

        assertEq(factory.creationFee(), fee);
    }

    // ============================================
    // INTEGRATION TESTS
    // ============================================

    function test_integration_CreateMultipleTypesWithFees() public {
        // Set creation fee
        vm.prank(feeManager);
        factory.setCreationFee(CREATION_FEE);

        // Create 721 collection
        vm.prank(creator1);
        address collection721 = factory.createCollection721{
            value: CREATION_FEE
        }(NAME_721, SYMBOL_721, creator1, ROYALTY_FEE, MAX_SUPPLY, BASE_URI);

        // Create 1155 collection
        vm.prank(creator1);
        address collection1155 = factory.createCollection1155{
            value: CREATION_FEE
        }(NAME_1155, SYMBOL_1155, URI_1155, creator1, ROYALTY_FEE);

        // Verify tracking
        assertEq(factory.getTotalCollections(), 2);
        assertEq(factory.getCreatorCollections(creator1).length, 2);
        assertEq(address(factory).balance, CREATION_FEE * 2);

        // Withdraw fees
        uint256 adminBalanceBefore = admin.balance;
        vm.prank(admin);
        factory.withdrawFees();

        assertEq(address(factory).balance, 0);
        assertEq(admin.balance, adminBalanceBefore + (CREATION_FEE * 2));
    }

    function test_integration_MultipleCreatorsMultipleCollections() public {
        // Creator1 creates 2 collections
        vm.startPrank(creator1);
        address c1_721 = factory.createCollection721(
            "Creator1 721",
            "C1721",
            creator1,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );
        address c1_1155 = factory.createCollection1155(
            "Creator1 1155",
            "C11155",
            URI_1155,
            creator1,
            ROYALTY_FEE
        );
        vm.stopPrank();

        // Creator2 creates 1 collection
        vm.prank(creator2);
        address c2_721 = factory.createCollection721(
            "Creator2 721",
            "C2721",
            creator2,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );

        // Verify global tracking
        assertEq(factory.getTotalCollections(), 3);
        address[] memory allCollections = factory.getAllCollections();
        assertEq(allCollections.length, 3);

        // Verify per-creator tracking
        address[] memory c1Collections = factory.getCreatorCollections(
            creator1
        );
        address[] memory c2Collections = factory.getCreatorCollections(
            creator2
        );

        assertEq(c1Collections.length, 2);
        assertEq(c2Collections.length, 1);

        assertEq(c1Collections[0], c1_721);
        assertEq(c1Collections[1], c1_1155);
        assertEq(c2Collections[0], c2_721);

        // Verify isVertixCollection
        assertTrue(factory.isVertixCollection(c1_721));
        assertTrue(factory.isVertixCollection(c1_1155));
        assertTrue(factory.isVertixCollection(c2_721));
    }

    function test_integration_FeeUpdatesAndWithdrawals() public {
        // Set initial fee
        vm.prank(feeManager);
        factory.setCreationFee(CREATION_FEE);

        // Create collection with initial fee
        vm.prank(creator1);
        factory.createCollection721{value: CREATION_FEE}(
            NAME_721,
            SYMBOL_721,
            creator1,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );

        assertEq(address(factory).balance, CREATION_FEE);

        // Update fee
        uint256 newFee = CREATION_FEE * 2;
        vm.prank(feeManager);
        factory.setCreationFee(newFee);

        // Create collection with new fee
        vm.prank(creator2);
        factory.createCollection721{value: newFee}(
            NAME_721,
            SYMBOL_721,
            creator2,
            ROYALTY_FEE,
            MAX_SUPPLY,
            BASE_URI
        );

        assertEq(address(factory).balance, CREATION_FEE + newFee);

        // Withdraw all fees
        uint256 expectedTotal = CREATION_FEE + newFee;
        uint256 adminBalanceBefore = admin.balance;

        vm.prank(admin);
        factory.withdrawFees();

        assertEq(address(factory).balance, 0);
        assertEq(admin.balance, adminBalanceBefore + expectedTotal);
    }

    function test_integration_CloneUniqueness() public {
        // Create multiple collections and verify they're all unique addresses
        vm.startPrank(creator1);

        address[] memory collections = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            collections[i] = factory.createCollection721(
                string(abi.encodePacked("Collection ", vm.toString(i))),
                string(abi.encodePacked("COL", vm.toString(i))),
                creator1,
                ROYALTY_FEE,
                MAX_SUPPLY,
                BASE_URI
            );
        }

        vm.stopPrank();

        // Verify all addresses are unique
        for (uint256 i = 0; i < 5; i++) {
            for (uint256 j = i + 1; j < 5; j++) {
                assertTrue(collections[i] != collections[j]);
            }
        }
    }
}

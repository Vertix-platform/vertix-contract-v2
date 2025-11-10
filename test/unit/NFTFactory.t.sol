// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {NFTFactory} from "../../src/nft/NFTFactory.sol";
import {VertixNFT721} from "../../src/nft/VertixNFT721.sol";
import {VertixNFT1155} from "../../src/nft/VertixNFT1155.sol";
import {RoleManager} from "../../src/access/RoleManager.sol";
import {Errors} from "../../src/libraries/Errors.sol";

contract NFTFactoryTest is Test {
    NFTFactory public factory;
    RoleManager public roleManager;

    address public admin;
    address public creator1;
    address public creator2;
    address public royaltyReceiver;

    event Collection721Created(address indexed collection, address indexed creator, string name, string symbol);
    event Collection1155Created(address indexed collection, address indexed creator, string name, string symbol);
    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);

    function setUp() public {
        admin = makeAddr("admin");
        creator1 = makeAddr("creator1");
        creator2 = makeAddr("creator2");
        royaltyReceiver = makeAddr("royaltyReceiver");

        roleManager = new RoleManager(admin);

        factory = new NFTFactory(address(roleManager));

        vm.deal(creator1, 100 ether);
        vm.deal(creator2, 100 ether);
    }

    // ============================================
    //          CONSTRUCTOR TESTS
    // ============================================

    function test_Constructor_SetsRoleManager() public view {
        assertEq(address(factory.roleManager()), address(roleManager));
    }

    function test_Constructor_DeploysImplementations() public view {
        address nft721Impl = factory.nft721Implementation();
        address nft1155Impl = factory.nft1155Implementation();

        assertTrue(nft721Impl != address(0));
        assertTrue(nft1155Impl != address(0));
        assertTrue(nft721Impl != nft1155Impl);
    }

    function test_Constructor_RevertsOnZeroAddress() public {
        vm.expectRevert(Errors.InvalidRoleManager.selector);
        new NFTFactory(address(0));
    }

    function test_Constructor_InitializesCreationFeeToZero() public view {
        assertEq(factory.creationFee(), 0);
    }

    // ============================================
    //      CREATE COLLECTION 721 TESTS
    // ============================================

    function test_CreateCollection721_SuccessfullyCreatesCollection() public {
        vm.startPrank(creator1);

        string memory name = "Test NFT";
        string memory symbol = "TEST";
        uint96 royaltyFee = 500; // 5%
        uint256 maxSupply = 1000;
        string memory baseURI = "ipfs://test/";

        vm.expectEmit(false, true, false, true);
        emit Collection721Created(address(0), creator1, name, symbol);

        address collection = factory.createCollection721(name, symbol, royaltyReceiver, royaltyFee, maxSupply, baseURI);

        assertTrue(collection != address(0));

        vm.stopPrank();
    }

    function test_CreateCollection721_InitializesCollectionCorrectly() public {
        vm.startPrank(creator1);

        string memory name = "Test NFT";
        string memory symbol = "TEST";
        uint96 royaltyFee = 500;
        uint256 maxSupply = 1000;
        string memory baseURI = "ipfs://test/";

        address collection = factory.createCollection721(name, symbol, royaltyReceiver, royaltyFee, maxSupply, baseURI);

        VertixNFT721 nft = VertixNFT721(collection);

        assertEq(nft.name(), name);
        assertEq(nft.symbol(), symbol);
        assertEq(nft.creator(), creator1);
        assertEq(nft.owner(), creator1);
        assertEq(nft.maxSupply(), maxSupply);

        vm.stopPrank();
    }

    function test_CreateCollection721_TracksInAllCollections() public {
        vm.startPrank(creator1);

        address collection1 = factory.createCollection721("NFT1", "N1", royaltyReceiver, 500, 1000, "");

        address collection2 = factory.createCollection721("NFT2", "N2", royaltyReceiver, 500, 1000, "");

        address[] memory allCollections = new address[](2);
        for (uint256 i = 0; i < 2; i++) {
            allCollections[i] = factory.allCollections(i);
        }

        assertEq(allCollections.length, 2);
        assertEq(allCollections[0], collection1);
        assertEq(allCollections[1], collection2);

        vm.stopPrank();
    }

    function test_CreateCollection721_TracksCreatorCollections() public {
        vm.startPrank(creator1);

        address collection1 = factory.createCollection721("NFT1", "N1", royaltyReceiver, 500, 1000, "");

        address collection2 = factory.createCollection721("NFT2", "N2", royaltyReceiver, 500, 1000, "");

        address[] memory creatorColls = new address[](2);
        for (uint256 i = 0; i < 2; i++) {
            creatorColls[i] = factory.creatorCollections(creator1, i);
        }

        assertEq(creatorColls.length, 2);
        assertEq(creatorColls[0], collection1);
        assertEq(creatorColls[1], collection2);

        vm.stopPrank();
    }

    function test_CreateCollection721_MarksAsVertixCollection() public {
        vm.startPrank(creator1);

        address collection = factory.createCollection721("Test NFT", "TEST", royaltyReceiver, 500, 1000, "");

        assertTrue(factory.isVertixCollection(collection));

        vm.stopPrank();
    }

    function test_CreateCollection721_RequiresCreationFee() public {
        vm.startPrank(admin);
        factory.setCreationFee(0.1 ether);
        vm.stopPrank();

        vm.startPrank(creator1);

        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientPayment.selector, 0.05 ether, 0.1 ether));

        factory.createCollection721{value: 0.05 ether}("Test NFT", "TEST", royaltyReceiver, 500, 1000, "");

        vm.stopPrank();
    }

    function test_CreateCollection721_AcceptsExcessPayment() public {
        vm.startPrank(admin);
        factory.setCreationFee(0.1 ether);
        vm.stopPrank();

        vm.startPrank(creator1);

        address collection =
            factory.createCollection721{value: 0.2 ether}("Test NFT", "TEST", royaltyReceiver, 500, 1000, "");

        assertTrue(collection != address(0));
        assertEq(address(factory).balance, 0.2 ether);

        vm.stopPrank();
    }

    function test_CreateCollection721_RevertsOnEmptyName() public {
        vm.startPrank(creator1);

        vm.expectRevert(abi.encodeWithSelector(Errors.EmptyString.selector, "name"));

        factory.createCollection721("", "TEST", royaltyReceiver, 500, 1000, "");

        vm.stopPrank();
    }

    function test_CreateCollection721_RevertsOnEmptySymbol() public {
        vm.startPrank(creator1);

        vm.expectRevert(abi.encodeWithSelector(Errors.EmptyString.selector, "symbol"));

        factory.createCollection721("Test NFT", "", royaltyReceiver, 500, 1000, "");

        vm.stopPrank();
    }

    function test_CreateCollection721_MultipleCreatorsIndependent() public {
        // Creator1 creates collection
        vm.prank(creator1);
        address collection1 = factory.createCollection721("Creator1 NFT", "C1", royaltyReceiver, 500, 1000, "");

        // Creator2 creates collection
        vm.prank(creator2);
        address collection2 = factory.createCollection721("Creator2 NFT", "C2", royaltyReceiver, 500, 1000, "");

        // Check creator1's collections
        address[] memory creator1Colls = new address[](1);
        creator1Colls[0] = factory.creatorCollections(creator1, 0);
        assertEq(creator1Colls[0], collection1);

        // Check creator2's collections
        address[] memory creator2Colls = new address[](1);
        creator2Colls[0] = factory.creatorCollections(creator2, 0);
        assertEq(creator2Colls[0], collection2);
    }

    // ============================================
    //      CREATE COLLECTION 1155 TESTS
    // ============================================

    function test_CreateCollection1155_SuccessfullyCreatesCollection() public {
        vm.startPrank(creator1);

        string memory name = "Test 1155";
        string memory symbol = "T1155";
        string memory uri = "ipfs://test/{id}.json";
        uint96 royaltyFee = 500;

        vm.expectEmit(false, true, false, true);
        emit Collection1155Created(address(0), creator1, name, symbol);

        address collection = factory.createCollection1155(name, symbol, uri, royaltyReceiver, royaltyFee);

        assertTrue(collection != address(0));

        vm.stopPrank();
    }

    function test_CreateCollection1155_InitializesCollectionCorrectly() public {
        vm.startPrank(creator1);

        string memory name = "Test 1155";
        string memory symbol = "T1155";
        string memory uri = "ipfs://test/{id}.json";
        uint96 royaltyFee = 500;

        address collection = factory.createCollection1155(name, symbol, uri, royaltyReceiver, royaltyFee);

        VertixNFT1155 nft = VertixNFT1155(collection);

        assertEq(nft.name(), name);
        assertEq(nft.symbol(), symbol);
        assertEq(nft.owner(), creator1);

        vm.stopPrank();
    }

    function test_CreateCollection1155_TracksInAllCollections() public {
        vm.startPrank(creator1);

        address collection1 = factory.createCollection1155("1155-1", "M1", "ipfs://test1/", royaltyReceiver, 500);

        address collection2 = factory.createCollection1155("1155-2", "M2", "ipfs://test2/", royaltyReceiver, 500);

        address[] memory allCollections = new address[](2);
        for (uint256 i = 0; i < 2; i++) {
            allCollections[i] = factory.allCollections(i);
        }

        assertEq(allCollections.length, 2);
        assertEq(allCollections[0], collection1);
        assertEq(allCollections[1], collection2);

        vm.stopPrank();
    }

    function test_CreateCollection1155_TracksCreatorCollections() public {
        vm.startPrank(creator1);

        address collection = factory.createCollection1155("Test 1155", "T1155", "ipfs://test/", royaltyReceiver, 500);

        address[] memory creatorColls = new address[](1);
        creatorColls[0] = factory.creatorCollections(creator1, 0);

        assertEq(creatorColls[0], collection);

        vm.stopPrank();
    }

    function test_CreateCollection1155_MarksAsVertixCollection() public {
        vm.startPrank(creator1);

        address collection = factory.createCollection1155("Test 1155", "T1155", "ipfs://test/", royaltyReceiver, 500);

        assertTrue(factory.isVertixCollection(collection));

        vm.stopPrank();
    }

    function test_CreateCollection1155_RequiresCreationFee() public {
        vm.startPrank(admin);
        factory.setCreationFee(0.1 ether);
        vm.stopPrank();

        vm.startPrank(creator1);

        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientPayment.selector, 0.05 ether, 0.1 ether));

        factory.createCollection1155{value: 0.05 ether}("Test 1155", "T1155", "ipfs://test/", royaltyReceiver, 500);

        vm.stopPrank();
    }

    function test_CreateCollection1155_RevertsOnEmptyName() public {
        vm.startPrank(creator1);

        vm.expectRevert(abi.encodeWithSelector(Errors.EmptyString.selector, "name"));

        factory.createCollection1155("", "T1155", "ipfs://test/", royaltyReceiver, 500);

        vm.stopPrank();
    }

    // ============================================
    //        SET CREATION FEE TESTS
    // ============================================

    function test_SetCreationFee_FeeManagerCanUpdate() public {
        vm.startPrank(admin);

        vm.expectEmit(true, true, true, true);
        emit CreationFeeUpdated(0, 0.1 ether);

        factory.setCreationFee(0.1 ether);

        assertEq(factory.creationFee(), 0.1 ether);

        vm.stopPrank();
    }

    function test_SetCreationFee_UpdatesMultipleTimes() public {
        vm.startPrank(admin);

        factory.setCreationFee(0.1 ether);
        assertEq(factory.creationFee(), 0.1 ether);

        vm.expectEmit(true, true, true, true);
        emit CreationFeeUpdated(0.1 ether, 0.2 ether);

        factory.setCreationFee(0.2 ether);
        assertEq(factory.creationFee(), 0.2 ether);

        vm.stopPrank();
    }

    function test_SetCreationFee_CanSetToZero() public {
        vm.startPrank(admin);

        factory.setCreationFee(0.1 ether);
        factory.setCreationFee(0);

        assertEq(factory.creationFee(), 0);

        vm.stopPrank();
    }

    function test_SetCreationFee_RevertsIfNotFeeManager() public {
        vm.startPrank(creator1);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotFeeManager.selector, creator1));

        factory.setCreationFee(0.1 ether);

        vm.stopPrank();
    }

    // ============================================
    //         WITHDRAW FEES TESTS
    // ============================================

    function test_WithdrawFees_AdminCanWithdraw() public {
        vm.startPrank(admin);
        factory.setCreationFee(0.1 ether);
        vm.stopPrank();

        vm.prank(creator1);
        factory.createCollection721{value: 0.1 ether}("NFT1", "N1", royaltyReceiver, 500, 1000, "");

        vm.prank(creator2);
        factory.createCollection721{value: 0.1 ether}("NFT2", "N2", royaltyReceiver, 500, 1000, "");

        assertEq(address(factory).balance, 0.2 ether);

        uint256 adminBalanceBefore = admin.balance;

        vm.prank(admin);
        factory.withdrawFees();

        assertEq(address(factory).balance, 0);
        assertEq(admin.balance, adminBalanceBefore + 0.2 ether);
    }

    function test_WithdrawFees_RevertsIfNoFees() public {
        vm.startPrank(admin);

        vm.expectRevert(Errors.NoFeesToWithdraw.selector);

        factory.withdrawFees();

        vm.stopPrank();
    }

    function test_WithdrawFees_RevertsIfNotAdmin() public {
        vm.startPrank(creator1);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotAdmin.selector, creator1));

        factory.withdrawFees();

        vm.stopPrank();
    }

    // ============================================
    //          INTEGRATION TESTS
    // ============================================

    function test_Integration_MixedCollectionTypes() public {
        vm.prank(creator1);
        address collection721 = factory.createCollection721("ERC721", "721", royaltyReceiver, 500, 1000, "");

        // Create 1155 collection
        vm.prank(creator1);
        address collection1155 = factory.createCollection1155("ERC1155", "1155", "ipfs://test/", royaltyReceiver, 500);

        assertEq(factory.allCollections(0), collection721);
        assertEq(factory.allCollections(1), collection1155);

        assertEq(factory.creatorCollections(creator1, 0), collection721);
        assertEq(factory.creatorCollections(creator1, 1), collection1155);

        assertTrue(factory.isVertixCollection(collection721));
        assertTrue(factory.isVertixCollection(collection1155));
    }

    function test_Integration_CompleteWorkflow() public {
        // 1. Set creation fee
        vm.prank(admin);
        factory.setCreationFee(0.05 ether);

        // 2. Creator creates multiple collections
        vm.startPrank(creator1);

        address collection1 = factory.createCollection721{value: 0.05 ether}(
            "Collection 1",
            "COL1",
            royaltyReceiver,
            250, // 2.5%
            500,
            "ipfs://col1/"
        );

        address collection2 = factory.createCollection1155{value: 0.05 ether}(
            "Collection 2",
            "COL2",
            "ipfs://col2/",
            royaltyReceiver,
            500 // 5%
        );

        vm.stopPrank();

        // 3. Verify collections work
        VertixNFT721 nft721 = VertixNFT721(collection1);
        assertEq(nft721.owner(), creator1);

        VertixNFT1155 nft1155 = VertixNFT1155(collection2);
        assertEq(nft1155.owner(), creator1);

        // 4. Admin withdraws fees
        vm.prank(admin);
        factory.withdrawFees();

        assertEq(address(factory).balance, 0);
    }

    function test_Integration_MultipleCreators() public {
        // Multiple creators create collections
        vm.prank(creator1);
        address c1_721 = factory.createCollection721("Creator1-721", "C1-721", royaltyReceiver, 500, 1000, "");

        vm.prank(creator1);
        address c1_1155 = factory.createCollection1155("Creator1-1155", "C1-1155", "ipfs://c1/", royaltyReceiver, 500);

        vm.prank(creator2);
        address c2_721 = factory.createCollection721("Creator2-721", "C2-721", royaltyReceiver, 500, 2000, "");

        assertEq(factory.creatorCollections(creator1, 0), c1_721);
        assertEq(factory.creatorCollections(creator1, 1), c1_1155);
        assertEq(factory.creatorCollections(creator2, 0), c2_721);

        assertEq(VertixNFT721(c1_721).owner(), creator1);
        assertEq(VertixNFT1155(c1_1155).owner(), creator1);
        assertEq(VertixNFT721(c2_721).owner(), creator2);
    }

    // ============================================
    //          FUZZ TESTS
    // ============================================

    function testFuzz_CreateCollection721_WithDifferentParameters(
        string memory name,
        string memory symbol,
        uint96 royaltyFee,
        uint256 maxSupply
    )
        public
    {
        // Bound inputs
        vm.assume(bytes(name).length > 0 && bytes(name).length < 100);
        vm.assume(bytes(symbol).length > 0 && bytes(symbol).length < 20);
        royaltyFee = uint96(bound(royaltyFee, 0, 1000)); // 0-10%
        maxSupply = bound(maxSupply, 1, 1_000_000);

        vm.prank(creator1);
        address collection = factory.createCollection721(name, symbol, royaltyReceiver, royaltyFee, maxSupply, "");

        assertTrue(collection != address(0));
        assertTrue(factory.isVertixCollection(collection));

        VertixNFT721 nft = VertixNFT721(collection);
        assertEq(nft.name(), name);
        assertEq(nft.symbol(), symbol);
        assertEq(nft.maxSupply(), maxSupply);
    }

    function testFuzz_SetCreationFee(uint256 fee) public {
        fee = bound(fee, 0, 100 ether);

        vm.prank(admin);
        factory.setCreationFee(fee);

        assertEq(factory.creationFee(), fee);
    }

    function testFuzz_CreateCollection721_WithFee(uint256 fee, uint256 payment) public {
        fee = bound(fee, 0.01 ether, 1 ether);
        payment = bound(payment, fee, 10 ether);

        vm.prank(admin);
        factory.setCreationFee(fee);

        vm.deal(creator1, payment);

        vm.prank(creator1);
        address collection = factory.createCollection721{value: payment}("Test", "TST", royaltyReceiver, 500, 1000, "");

        assertTrue(collection != address(0));
        assertEq(address(factory).balance, payment);
    }
}

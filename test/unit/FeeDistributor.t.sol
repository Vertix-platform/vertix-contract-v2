// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../../src/core/FeeDistributor.sol";
import "../../src/access/RoleManager.sol";
import "../../src/nft/VertixNFT721.sol";

contract FeeDistributorTest is Test {
    FeeDistributor public feeDistributor;
    RoleManager public roleManager;
    VertixNFT721 public nft;

    address public admin = address(1);
    address public feeCollector = address(2);
    address public seller = address(3);
    address public buyer = address(4);
    address public royaltyReceiver = address(5);

    uint256 constant PLATFORM_FEE_BPS = 250; // 2.5%
    uint256 constant ROYALTY_BPS = 1000; // 10%

    event PaymentDistributed(
        address indexed seller,
        address indexed buyer,
        uint256 totalAmount,
        uint256 platformFee,
        uint256 royaltyFee,
        uint256 sellerNet
    );

    function setUp() public {
        vm.startPrank(admin);

        roleManager = new RoleManager(admin);
        feeDistributor = new FeeDistributor(
            address(roleManager),
            feeCollector,
            PLATFORM_FEE_BPS
        );

        // Deploy NFT with royalty
        nft = new VertixNFT721(
            "Test NFT",
            "TEST",
            admin,
            royaltyReceiver,
            uint96(ROYALTY_BPS),
            0,
            ""
        );

        vm.stopPrank();

        // Fund accounts
        vm.deal(buyer, 100 ether);
        vm.deal(seller, 10 ether);
    }

    // ============================================
    // CONSTRUCTOR TESTS
    // ============================================

    function test_constructor_Success() public {
        assertEq(feeDistributor.platformFeeBps(), PLATFORM_FEE_BPS);
        assertEq(feeDistributor.feeCollector(), feeCollector);
        assertEq(address(feeDistributor.roleManager()), address(roleManager));
    }

    function test_constructor_RevertIf_InvalidRoleManager() public {
        vm.expectRevert("Invalid role manager");
        new FeeDistributor(address(0), feeCollector, PLATFORM_FEE_BPS);
    }

    function test_constructor_RevertIf_InvalidFeeCollector() public {
        vm.expectRevert("Invalid fee collector");
        new FeeDistributor(address(roleManager), address(0), PLATFORM_FEE_BPS);
    }

    function test_constructor_RevertIf_FeeTooHigh() public {
        vm.expectRevert();
        new FeeDistributor(address(roleManager), feeCollector, 1001); // > 10%
    }

    // ============================================
    // PAYMENT DISTRIBUTION TESTS
    // ============================================

    function test_distributeSaleProceeds_WithoutRoyalty() public {
        uint256 amount = 1 ether;

        uint256 feeCollectorBalanceBefore = feeCollector.balance;
        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(buyer);
        vm.expectEmit(true, true, false, true);
        emit PaymentDistributed(
            seller,
            buyer,
            amount,
            0.025 ether, // 2.5%
            0,
            0.975 ether
        );

        feeDistributor.distributeSaleProceeds{value: amount}(
            seller,
            amount,
            address(0),
            0
        );

        // Check balances
        assertEq(seller.balance, sellerBalanceBefore + 0.975 ether);
        assertEq(feeDistributor.accumulatedFees(), 0.025 ether);
    }

    function test_distributeSaleProceeds_WithRoyalty() public {
        uint256 amount = 1 ether;

        uint256 sellerBalanceBefore = seller.balance;
        uint256 royaltyBalanceBefore = royaltyReceiver.balance;

        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: amount}(
            seller,
            amount,
            royaltyReceiver,
            0.1 ether // 10%
        );

        // Platform fee: 2.5% = 0.025 ETH
        // Royalty: 10% = 0.1 ETH
        // Seller net: 87.5% = 0.875 ETH

        assertEq(seller.balance, sellerBalanceBefore + 0.875 ether);
        assertEq(royaltyReceiver.balance, royaltyBalanceBefore + 0.1 ether);
        assertEq(feeDistributor.accumulatedFees(), 0.025 ether);
    }

    function test_distributeSaleProceeds_RevertIf_IncorrectPayment() public {
        vm.prank(buyer);
        vm.expectRevert("Incorrect payment");
        feeDistributor.distributeSaleProceeds{value: 0.5 ether}(
            seller,
            1 ether,
            address(0),
            0
        );
    }

    function test_distributeSaleProceeds_RevertIf_InvalidSeller() public {
        vm.prank(buyer);
        vm.expectRevert("Invalid seller");
        feeDistributor.distributeSaleProceeds{value: 1 ether}(
            address(0),
            1 ether,
            address(0),
            0
        );
    }

    function test_distributeSaleProceeds_RevertIf_RoyaltyTooHigh() public {
        vm.prank(buyer);
        vm.expectRevert("Royalty too high");
        feeDistributor.distributeSaleProceeds{value: 1 ether}(
            seller,
            1 ether,
            royaltyReceiver,
            0.11 ether // 11% > 10% max
        );
    }

    function test_distributeSaleProceeds_RevertIf_InvalidRoyaltyReceiver()
        public
    {
        vm.prank(buyer);
        vm.expectRevert("Invalid royalty receiver");
        feeDistributor.distributeSaleProceeds{value: 1 ether}(
            seller,
            1 ether,
            address(0),
            0.1 ether
        );
    }

    // ============================================
    // CALCULATION TESTS
    // ============================================

    function test_calculateDistribution_WithoutRoyalty() public {
        // Mint NFT without royalty
        vm.prank(admin);
        nft.deleteDefaultRoyalty();

        uint256 tokenId = 1;
        vm.prank(admin);
        nft.mint(seller, "ipfs://test");

        IFeeDistributor.PaymentDistribution memory distribution = feeDistributor
            .calculateDistribution(1 ether, address(nft), tokenId);

        assertEq(distribution.platformFee, 0.025 ether);
        assertEq(distribution.royaltyFee, 0);
        assertEq(distribution.sellerNet, 0.975 ether);
        assertEq(distribution.royaltyReceiver, address(0));
    }

    function test_calculateDistribution_WithRoyalty() public {
        uint256 tokenId = 1;
        vm.prank(admin);
        nft.mint(seller, "ipfs://test");

        IFeeDistributor.PaymentDistribution memory distribution = feeDistributor
            .calculateDistribution(1 ether, address(nft), tokenId);

        assertEq(distribution.platformFee, 0.025 ether);
        assertEq(distribution.royaltyFee, 0.1 ether); // 10%
        assertEq(distribution.sellerNet, 0.875 ether);
        assertEq(distribution.royaltyReceiver, royaltyReceiver);
    }

    function test_calculatePlatformFee() public {
        assertEq(feeDistributor.calculatePlatformFee(1 ether), 0.025 ether);
        assertEq(feeDistributor.calculatePlatformFee(10 ether), 0.25 ether);
        assertEq(feeDistributor.calculatePlatformFee(0.1 ether), 0.0025 ether);
    }

    function test_calculateSellerNet() public {
        // Without royalty
        assertEq(feeDistributor.calculateSellerNet(1 ether, 0), 0.975 ether);

        // With royalty
        assertEq(
            feeDistributor.calculateSellerNet(1 ether, 0.1 ether),
            0.875 ether
        );
    }

    function test_supportsRoyalties() public {
        assertTrue(feeDistributor.supportsRoyalties(address(nft)));
        assertFalse(feeDistributor.supportsRoyalties(address(this)));
    }

    // ============================================
    // ADMIN FUNCTIONS TESTS
    // ============================================

    function test_updatePlatformFee_Success() public {
        vm.prank(admin);
        feeDistributor.updatePlatformFee(300); // 3%

        assertEq(feeDistributor.platformFeeBps(), 300);
    }

    function test_updatePlatformFee_RevertIf_NotFeeManager() public {
        vm.prank(buyer);
        vm.expectRevert("Not fee manager");
        feeDistributor.updatePlatformFee(300);
    }

    function test_updatePlatformFee_RevertIf_TooHigh() public {
        vm.prank(admin);
        vm.expectRevert();
        feeDistributor.updatePlatformFee(1001); // > 10%
    }

    function test_updateFeeCollector_Success() public {
        address newCollector = address(999);

        vm.prank(admin);
        feeDistributor.updateFeeCollector(newCollector);

        assertEq(feeDistributor.feeCollector(), newCollector);
    }

    function test_updateFeeCollector_RevertIf_NotFeeManager() public {
        vm.prank(buyer);
        vm.expectRevert("Not fee manager");
        feeDistributor.updateFeeCollector(address(999));
    }

    function test_updateFeeCollector_RevertIf_InvalidAddress() public {
        vm.prank(admin);
        vm.expectRevert();
        feeDistributor.updateFeeCollector(address(0));
    }

    // ============================================
    // FEE WITHDRAWAL TESTS
    // ============================================

    function test_withdrawFees_Success() public {
        // Accumulate some fees
        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: 1 ether}(
            seller,
            1 ether,
            address(0),
            0
        );

        uint256 accumulatedFees = feeDistributor.accumulatedFees();
        assertEq(accumulatedFees, 0.025 ether);

        uint256 collectorBalanceBefore = feeCollector.balance;

        vm.prank(feeCollector);
        feeDistributor.withdrawFees();

        assertEq(
            feeCollector.balance,
            collectorBalanceBefore + accumulatedFees
        );
        assertEq(feeDistributor.accumulatedFees(), 0);
    }

    function test_withdrawFees_RevertIf_NotFeeCollector() public {
        vm.prank(buyer);
        vm.expectRevert("Not fee collector");
        feeDistributor.withdrawFees();
    }

    function test_withdrawFees_RevertIf_NoFees() public {
        vm.prank(feeCollector);
        vm.expectRevert("No fees to withdraw");
        feeDistributor.withdrawFees();
    }

    function test_withdrawFeesAmount_Success() public {
        // Accumulate fees
        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: 2 ether}(
            seller,
            2 ether,
            address(0),
            0
        );

        assertEq(feeDistributor.accumulatedFees(), 0.05 ether);

        uint256 collectorBalanceBefore = feeCollector.balance;

        // Withdraw partial amount
        vm.prank(feeCollector);
        feeDistributor.withdrawFeesAmount(0.03 ether);

        assertEq(feeCollector.balance, collectorBalanceBefore + 0.03 ether);
        assertEq(feeDistributor.accumulatedFees(), 0.02 ether);
    }

    function test_withdrawFeesAmount_RevertIf_InsufficientFees() public {
        vm.prank(feeCollector);
        vm.expectRevert("Insufficient fees");
        feeDistributor.withdrawFeesAmount(1 ether);
    }

    // ============================================
    // FUZZ TESTS
    // ============================================

    function testFuzz_calculatePlatformFee(uint256 amount) public {
        vm.assume(amount <= 1000 ether);

        uint256 fee = feeDistributor.calculatePlatformFee(amount);
        assertEq(fee, (amount * PLATFORM_FEE_BPS) / 10000);
    }

    function testFuzz_distributeSaleProceeds(uint96 amount) public {
        vm.assume(amount >= 0.01 ether);
        vm.assume(amount <= 100 ether);

        vm.deal(buyer, amount);

        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: amount}(
            seller,
            amount,
            address(0),
            0
        );

        uint256 expectedNet = amount - ((amount * PLATFORM_FEE_BPS) / 10000);
        assertEq(seller.balance, sellerBalanceBefore + expectedNet);
    }
}

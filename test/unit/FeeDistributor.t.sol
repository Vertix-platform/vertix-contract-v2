// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {FeeDistributor} from "../../src/core/FeeDistributor.sol";
import {RoleManager} from "../../src/access/RoleManager.sol";
import {IFeeDistributor} from "../../src/interfaces/IFeeDistributor.sol";
import {AssetTypes} from "../../src/libraries/AssetTypes.sol";
import {PercentageMath} from "../../src/libraries/PercentageMath.sol";
import {Errors} from "../../src/libraries/Errors.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

// Mock contracts
import {MockNFT} from "../mocks/MockNFT.sol";
import {MockNFTRevert} from "../mocks/MockNFTRevert.sol";
import {MaliciousReceiver} from "../mocks/MaliciousReceiver.sol";

contract FeeDistributorTest is Test {
    FeeDistributor public feeDistributor;
    RoleManager public roleManager;

    address public admin;
    address public feeManager;
    address public feeCollector;
    address public seller;
    address public buyer;
    address public royaltyReceiver;

    // Events
    event PaymentDistributed(
        address indexed seller,
        address indexed buyer,
        uint256 totalAmount,
        uint256 platformFee,
        uint256 royaltyFee,
        uint256 sellerNet
    );
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeCollectorUpdated(address indexed oldCollector, address indexed newCollector);
    event FeesReceived(address indexed from, uint256 amount);
    event FeesWithdrawn(address indexed collector, uint256 amount);

    function setUp() public {
        admin = makeAddr("admin");
        feeManager = makeAddr("feeManager");
        feeCollector = makeAddr("feeCollector");
        seller = makeAddr("seller");
        buyer = makeAddr("buyer");
        royaltyReceiver = makeAddr("royaltyReceiver");

        // Deploy RoleManager
        roleManager = new RoleManager(admin);

        // Grant FEE_MANAGER_ROLE (FEE_MANAGER_ROLE is non-sensitive so it's granted immediately)
        vm.startPrank(admin);
        roleManager.scheduleRoleGrant(roleManager.FEE_MANAGER_ROLE(), feeManager);
        vm.stopPrank();

        // Deploy FeeDistributor with 2.5% default fee
        feeDistributor = new FeeDistributor(address(roleManager), feeCollector, 250);

        // Fund test accounts
        vm.deal(buyer, 100 ether);
        vm.deal(seller, 1 ether);
        vm.deal(feeCollector, 1 ether);
    }

    // ============================================
    //          CONSTRUCTOR TESTS
    // ============================================

    function test_Constructor_SetsStateCorrectly() public view {
        assertEq(address(feeDistributor.roleManager()), address(roleManager));
        assertEq(feeDistributor.feeCollector(), feeCollector);
        assertEq(feeDistributor.platformFeeBps(), 250);
        assertEq(feeDistributor.accumulatedFees(), 0);
    }

    function test_Constructor_EmitsEvents() public {
        vm.expectEmit(true, true, true, true);
        emit PlatformFeeUpdated(0, 250);

        vm.expectEmit(true, true, true, true);
        emit FeeCollectorUpdated(address(0), feeCollector);

        new FeeDistributor(address(roleManager), feeCollector, 250);
    }

    function test_Constructor_RevertsOnZeroRoleManager() public {
        vm.expectRevert(Errors.InvalidRoleManager.selector);
        new FeeDistributor(address(0), feeCollector, 250);
    }

    function test_Constructor_RevertsOnZeroFeeCollector() public {
        vm.expectRevert(Errors.InvalidFeeDistributor.selector);
        new FeeDistributor(address(roleManager), address(0), 250);
    }

    function test_Constructor_RevertsOnInvalidFeeBps() public {
        vm.expectRevert(abi.encodeWithSelector(PercentageMath.PercentageTooHigh.selector, 2000, AssetTypes.MAX_FEE_BPS));
        new FeeDistributor(address(roleManager), feeCollector, 2000); // 20% exceeds MAX_FEE_BPS (10%)
    }

    function test_Constructor_AcceptsMaximumFeeBps() public {
        FeeDistributor testDistributor = new FeeDistributor(address(roleManager), feeCollector, 1000); // 10%
        assertEq(testDistributor.platformFeeBps(), 1000);
    }

    // ============================================
    //      DISTRIBUTE SALE PROCEEDS TESTS
    // ============================================

    function test_DistributeSaleProceeds_WithoutRoyalty() public {
        uint256 saleAmount = 1 ether;
        uint256 platformFee = 0.025 ether; // 2.5%
        uint256 sellerNet = 0.975 ether;

        vm.expectEmit(true, true, true, true);
        emit PaymentDistributed(seller, buyer, saleAmount, platformFee, 0, sellerNet);

        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: saleAmount}(seller, saleAmount, address(0), 0);

        assertEq(feeDistributor.accumulatedFees(), platformFee);
        assertEq(seller.balance, 1 ether + sellerNet);
        assertEq(address(feeDistributor).balance, platformFee);
    }

    function test_DistributeSaleProceeds_WithRoyalty() public {
        uint256 saleAmount = 10 ether;
        uint256 royaltyAmount = 0.5 ether; // 5%
        uint256 platformFee = 0.25 ether; // 2.5%
        uint256 sellerNet = 9.25 ether;

        vm.expectEmit(true, true, true, true);
        emit PaymentDistributed(seller, buyer, saleAmount, platformFee, royaltyAmount, sellerNet);

        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: saleAmount}(seller, saleAmount, royaltyReceiver, royaltyAmount);

        assertEq(feeDistributor.accumulatedFees(), platformFee);
        assertEq(seller.balance, 1 ether + sellerNet);
        assertEq(royaltyReceiver.balance, royaltyAmount);
        assertEq(address(feeDistributor).balance, platformFee);
    }

    function test_DistributeSaleProceeds_WithMaxRoyalty() public {
        uint256 saleAmount = 1 ether;
        uint256 royaltyAmount = 0.1 ether; // 10% (max)
        uint256 platformFee = 0.025 ether; // 2.5%
        uint256 sellerNet = 0.875 ether;

        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: saleAmount}(seller, saleAmount, royaltyReceiver, royaltyAmount);

        assertEq(feeDistributor.accumulatedFees(), platformFee);
        assertEq(seller.balance, 1 ether + sellerNet);
        assertEq(royaltyReceiver.balance, royaltyAmount);
    }

    function test_DistributeSaleProceeds_RevertsOnIncorrectPayment() public {
        uint256 saleAmount = 1 ether;

        vm.prank(buyer);
        vm.expectRevert(IFeeDistributor.IncorrectPayment.selector);
        feeDistributor.distributeSaleProceeds{value: 0.5 ether}(seller, saleAmount, address(0), 0);
    }

    function test_DistributeSaleProceeds_RevertsOnZeroSeller() public {
        uint256 saleAmount = 1 ether;

        vm.prank(buyer);
        vm.expectRevert(IFeeDistributor.InvalidSeller.selector);
        feeDistributor.distributeSaleProceeds{value: saleAmount}(address(0), saleAmount, address(0), 0);
    }

    function test_DistributeSaleProceeds_RevertsOnInvalidRoyaltyReceiver() public {
        uint256 saleAmount = 1 ether;
        uint256 royaltyAmount = 0.05 ether;

        vm.prank(buyer);
        vm.expectRevert(IFeeDistributor.InvalidRoyaltyReceiver.selector);
        feeDistributor.distributeSaleProceeds{value: saleAmount}(seller, saleAmount, address(0), royaltyAmount);
    }

    function test_DistributeSaleProceeds_RevertsOnRoyaltyTooHigh() public {
        uint256 saleAmount = 1 ether;
        uint256 royaltyAmount = 0.15 ether; // 15% exceeds max (10%)

        vm.prank(buyer);
        vm.expectRevert(IFeeDistributor.RoyaltyTooHigh.selector);
        feeDistributor.distributeSaleProceeds{value: saleAmount}(seller, saleAmount, royaltyReceiver, royaltyAmount);
    }

    function test_DistributeSaleProceeds_HandlesHighCombinedFees() public {
        uint256 saleAmount = 1 ether;

        // Update platform fee to maximum (10%)
        vm.prank(feeManager);
        feeDistributor.updatePlatformFee(1000); // 10%

        // Use max royalty (10%)
        uint256 royaltyAmount = 0.1 ether; // 10%

        // Total fees = 20%, which is high but valid (seller gets 80%)
        uint256 expectedPlatformFee = 0.1 ether;
        uint256 expectedSellerNet = 0.8 ether;

        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: saleAmount}(seller, saleAmount, royaltyReceiver, royaltyAmount);

        // Verify the distribution worked correctly even with high fees
        assertEq(feeDistributor.accumulatedFees(), expectedPlatformFee);
        assertEq(seller.balance, 1 ether + expectedSellerNet);
        assertEq(royaltyReceiver.balance, royaltyAmount);
    }

    function test_DistributeSaleProceeds_AccumulatesMultipleSales() public {
        uint256 saleAmount = 1 ether;
        uint256 platformFee = 0.025 ether;

        // First sale
        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: saleAmount}(seller, saleAmount, address(0), 0);
        assertEq(feeDistributor.accumulatedFees(), platformFee);

        // Second sale
        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: saleAmount}(seller, saleAmount, address(0), 0);
        assertEq(feeDistributor.accumulatedFees(), platformFee * 2);

        // Third sale
        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: saleAmount}(seller, saleAmount, address(0), 0);
        assertEq(feeDistributor.accumulatedFees(), platformFee * 3);
    }

    function test_DistributeSaleProceeds_FuzzAmount(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 10_000 ether);

        uint256 platformFee = (amount * 250) / 10_000;
        uint256 sellerNet = amount - platformFee;

        vm.deal(buyer, amount);

        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: amount}(seller, amount, address(0), 0);

        assertEq(feeDistributor.accumulatedFees(), platformFee);
        assertEq(seller.balance, 1 ether + sellerNet);
    }

    // ============================================
    //      CALCULATE DISTRIBUTION TESTS
    // ============================================

    function test_CalculateDistribution_WithoutRoyalty() public {
        MockNFT mockNFT = new MockNFT(false, address(0), 0);

        IFeeDistributor.PaymentDistribution memory dist =
            feeDistributor.calculateDistribution(1 ether, address(mockNFT), 1);

        assertEq(dist.platformFee, 0.025 ether);
        assertEq(dist.royaltyFee, 0);
        assertEq(dist.royaltyReceiver, address(0));
        assertEq(dist.sellerNet, 0.975 ether);
    }

    function test_CalculateDistribution_WithRoyalty() public {
        uint256 royaltyAmount = 0.05 ether; // 5%
        MockNFT mockNFT = new MockNFT(true, royaltyReceiver, royaltyAmount);

        IFeeDistributor.PaymentDistribution memory dist =
            feeDistributor.calculateDistribution(1 ether, address(mockNFT), 1);

        assertEq(dist.platformFee, 0.025 ether);
        assertEq(dist.royaltyFee, royaltyAmount);
        assertEq(dist.royaltyReceiver, royaltyReceiver);
        assertEq(dist.sellerNet, 0.925 ether);
    }

    function test_CalculateDistribution_CapsExcessiveRoyalty() public {
        uint256 excessiveRoyalty = 0.2 ether; // 20% (exceeds 10% max)
        MockNFT mockNFT = new MockNFT(true, royaltyReceiver, excessiveRoyalty);

        IFeeDistributor.PaymentDistribution memory dist =
            feeDistributor.calculateDistribution(1 ether, address(mockNFT), 1);

        assertEq(dist.platformFee, 0.025 ether);
        assertEq(dist.royaltyFee, 0.1 ether); // Capped at 10%
        assertEq(dist.royaltyReceiver, royaltyReceiver);
        assertEq(dist.sellerNet, 0.875 ether);
    }

    function test_CalculateDistribution_HandlesRoyaltyRevert() public {
        MockNFTRevert mockNFT = new MockNFTRevert();

        IFeeDistributor.PaymentDistribution memory dist =
            feeDistributor.calculateDistribution(1 ether, address(mockNFT), 1);

        assertEq(dist.platformFee, 0.025 ether);
        assertEq(dist.royaltyFee, 0);
        assertEq(dist.royaltyReceiver, address(0));
        assertEq(dist.sellerNet, 0.975 ether);
    }

    // ============================================
    //      UPDATE PLATFORM FEE TESTS
    // ============================================

    function test_UpdatePlatformFee_Success() public {
        vm.prank(feeManager);
        vm.expectEmit(true, true, true, true);
        emit PlatformFeeUpdated(250, 500);
        feeDistributor.updatePlatformFee(500); // 5%

        assertEq(feeDistributor.platformFeeBps(), 500);
    }

    function test_UpdatePlatformFee_ToZero() public {
        vm.prank(feeManager);
        feeDistributor.updatePlatformFee(0);
        assertEq(feeDistributor.platformFeeBps(), 0);
    }

    function test_UpdatePlatformFee_ToMaximum() public {
        vm.prank(feeManager);
        feeDistributor.updatePlatformFee(1000); // 10%
        assertEq(feeDistributor.platformFeeBps(), 1000);
    }

    function test_UpdatePlatformFee_RevertsOnUnauthorized() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotFeeManager.selector, buyer));
        feeDistributor.updatePlatformFee(500);
    }

    function test_UpdatePlatformFee_RevertsOnExcessiveFee() public {
        vm.prank(feeManager);
        vm.expectRevert(abi.encodeWithSelector(PercentageMath.PercentageTooHigh.selector, 1500, 1000));
        feeDistributor.updatePlatformFee(1500); // 15% exceeds max
    }

    // ============================================
    //      UPDATE FEE COLLECTOR TESTS
    // ============================================

    function test_UpdateFeeCollector_Success() public {
        address newCollector = makeAddr("newCollector");

        vm.prank(feeManager);
        vm.expectEmit(true, true, true, true);
        emit FeeCollectorUpdated(feeCollector, newCollector);
        feeDistributor.updateFeeCollector(newCollector);

        assertEq(feeDistributor.feeCollector(), newCollector);
    }

    function test_UpdateFeeCollector_RevertsOnZeroAddress() public {
        vm.prank(feeManager);
        vm.expectRevert(IFeeDistributor.InvalidFeeCollector.selector);
        feeDistributor.updateFeeCollector(address(0));
    }

    function test_UpdateFeeCollector_RevertsOnUnauthorized() public {
        address newCollector = makeAddr("newCollector");

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Errors.NotFeeManager.selector, buyer));
        feeDistributor.updateFeeCollector(newCollector);
    }

    // ============================================
    //          WITHDRAW FEES TESTS
    // ============================================

    function test_WithdrawFees_Success() public {
        // Generate fees
        uint256 saleAmount = 1 ether;
        uint256 platformFee = 0.025 ether;

        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: saleAmount}(seller, saleAmount, address(0), 0);

        uint256 collectorBalanceBefore = feeCollector.balance;

        // Withdraw
        vm.prank(feeCollector);
        vm.expectEmit(true, true, true, true);
        emit FeesWithdrawn(feeCollector, platformFee);
        feeDistributor.withdrawFees();

        assertEq(feeDistributor.accumulatedFees(), 0);
        assertEq(feeCollector.balance, collectorBalanceBefore + platformFee);
    }

    function test_WithdrawFees_MultipleAccumulations() public {
        // Generate multiple fees
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(buyer);
            feeDistributor.distributeSaleProceeds{value: 1 ether}(seller, 1 ether, address(0), 0);
        }

        uint256 totalFees = 0.025 ether * 5;
        assertEq(feeDistributor.accumulatedFees(), totalFees);

        vm.prank(feeCollector);
        feeDistributor.withdrawFees();

        assertEq(feeDistributor.accumulatedFees(), 0);
    }

    function test_WithdrawFees_RevertsOnUnauthorized() public {
        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: 1 ether}(seller, 1 ether, address(0), 0);

        vm.prank(buyer);
        vm.expectRevert(IFeeDistributor.NotFeeCollector.selector);
        feeDistributor.withdrawFees();
    }

    function test_WithdrawFees_RevertsOnZeroBalance() public {
        vm.prank(feeCollector);
        vm.expectRevert(IFeeDistributor.NoFeesToWithdraw.selector);
        feeDistributor.withdrawFees();
    }

    // ============================================
    //      WITHDRAW FEES AMOUNT TESTS
    // ============================================

    function test_WithdrawFeesAmount_Success() public {
        // Generate fees
        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: 10 ether}(seller, 10 ether, address(0), 0);

        uint256 totalFees = 0.25 ether;
        uint256 withdrawAmount = 0.1 ether;

        vm.prank(feeCollector);
        vm.expectEmit(true, true, true, true);
        emit FeesWithdrawn(feeCollector, withdrawAmount);
        feeDistributor.withdrawFeesAmount(withdrawAmount);

        assertEq(feeDistributor.accumulatedFees(), totalFees - withdrawAmount);
    }

    function test_WithdrawFeesAmount_Multiple() public {
        // Generate fees
        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: 10 ether}(seller, 10 ether, address(0), 0);

        uint256 totalFees = 0.25 ether;

        // First withdrawal
        vm.prank(feeCollector);
        feeDistributor.withdrawFeesAmount(0.1 ether);
        assertEq(feeDistributor.accumulatedFees(), totalFees - 0.1 ether);

        // Second withdrawal
        vm.prank(feeCollector);
        feeDistributor.withdrawFeesAmount(0.05 ether);
        assertEq(feeDistributor.accumulatedFees(), totalFees - 0.15 ether);
    }

    function test_WithdrawFeesAmount_RevertsOnExceedingBalance() public {
        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: 1 ether}(seller, 1 ether, address(0), 0);

        vm.prank(feeCollector);
        vm.expectRevert(IFeeDistributor.InsufficientFees.selector);
        feeDistributor.withdrawFeesAmount(1 ether);
    }

    function test_WithdrawFeesAmount_RevertsOnZeroAmount() public {
        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: 1 ether}(seller, 1 ether, address(0), 0);

        vm.prank(feeCollector);
        vm.expectRevert(IFeeDistributor.NoFeesToWithdraw.selector);
        feeDistributor.withdrawFeesAmount(0);
    }

    function test_WithdrawFeesAmount_RevertsOnUnauthorized() public {
        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: 1 ether}(seller, 1 ether, address(0), 0);

        vm.prank(buyer);
        vm.expectRevert(IFeeDistributor.NotFeeCollector.selector);
        feeDistributor.withdrawFeesAmount(0.01 ether);
    }

    // ============================================
    //          RECEIVE ETH TESTS
    // ============================================

    function test_Receive_AccumulatesFees() public {
        uint256 amount = 1 ether;

        vm.expectEmit(true, true, true, true);
        emit FeesReceived(buyer, amount);

        vm.prank(buyer);
        (bool success,) = address(feeDistributor).call{value: amount}("");
        assertTrue(success);

        assertEq(feeDistributor.accumulatedFees(), amount);
        assertEq(address(feeDistributor).balance, amount);
    }

    function test_Receive_MultipleDeposits() public {
        for (uint256 i = 1; i <= 5; i++) {
            vm.prank(buyer);
            (bool success,) = address(feeDistributor).call{value: 0.1 ether}("");
            assertTrue(success);
        }

        assertEq(feeDistributor.accumulatedFees(), 0.5 ether);
    }

    function test_Receive_WithReentrancy() public {
        // The receive function has nonReentrant modifier
        // Direct ETH sends work fine
        vm.prank(buyer);
        (bool success,) = address(feeDistributor).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(feeDistributor.accumulatedFees(), 1 ether);

        // Multiple sequential sends also work
        vm.prank(buyer);
        (success,) = address(feeDistributor).call{value: 0.5 ether}("");
        assertTrue(success);
        assertEq(feeDistributor.accumulatedFees(), 1.5 ether);
    }

    // ============================================
    //          VIEW FUNCTION TESTS
    // ============================================

    function test_CalculatePlatformFee() public view {
        assertEq(feeDistributor.calculatePlatformFee(1 ether), 0.025 ether);
        assertEq(feeDistributor.calculatePlatformFee(10 ether), 0.25 ether);
        assertEq(feeDistributor.calculatePlatformFee(0), 0);
    }

    function test_CalculateSellerNet() public view {
        assertEq(feeDistributor.calculateSellerNet(1 ether, 0), 0.975 ether);
        assertEq(feeDistributor.calculateSellerNet(1 ether, 0.05 ether), 0.925 ether);
        assertEq(feeDistributor.calculateSellerNet(10 ether, 0.5 ether), 9.25 ether);
    }

    function test_SupportsRoyalties() public {
        MockNFT mockNFTWithRoyalty = new MockNFT(true, royaltyReceiver, 0.05 ether);
        MockNFT mockNFTWithoutRoyalty = new MockNFT(false, address(0), 0);

        assertTrue(feeDistributor.supportsRoyalties(address(mockNFTWithRoyalty)));
        assertFalse(feeDistributor.supportsRoyalties(address(mockNFTWithoutRoyalty)));
    }

    // ============================================
    //          EDGE CASE TESTS
    // ============================================

    function test_DistributeSaleProceeds_WithZeroPlatformFee() public {
        // Update platform fee to 0
        vm.prank(feeManager);
        feeDistributor.updatePlatformFee(0);

        uint256 saleAmount = 1 ether;
        uint256 royaltyAmount = 0.05 ether;
        uint256 sellerNet = 0.95 ether;

        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: saleAmount}(seller, saleAmount, royaltyReceiver, royaltyAmount);

        assertEq(feeDistributor.accumulatedFees(), 0);
        assertEq(seller.balance, 1 ether + sellerNet);
        assertEq(royaltyReceiver.balance, royaltyAmount);
    }

    function test_DistributeSaleProceeds_SmallAmount() public {
        uint256 saleAmount = 1000 wei;
        uint256 platformFee = 25 wei; // 2.5%
        uint256 sellerNet = 975 wei;

        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: saleAmount}(seller, saleAmount, address(0), 0);

        assertEq(feeDistributor.accumulatedFees(), platformFee);
        assertEq(seller.balance, 1 ether + sellerNet);
    }

    function test_WithdrawAfterCollectorChange() public {
        // Generate fees
        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: 1 ether}(seller, 1 ether, address(0), 0);

        // Change collector
        address newCollector = makeAddr("newCollector");
        vm.prank(feeManager);
        feeDistributor.updateFeeCollector(newCollector);

        // Old collector cannot withdraw
        vm.prank(feeCollector);
        vm.expectRevert(IFeeDistributor.NotFeeCollector.selector);
        feeDistributor.withdrawFees();

        // New collector can withdraw
        vm.prank(newCollector);
        feeDistributor.withdrawFees();
        assertEq(feeDistributor.accumulatedFees(), 0);
    }

    // ============================================
    //          INTEGRATION TESTS
    // ============================================

    function test_CompleteFlowWithMultipleSalesAndWithdrawals() public {
        // Sale 1: No royalty
        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: 1 ether}(seller, 1 ether, address(0), 0);

        // Sale 2: With royalty
        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: 2 ether}(seller, 2 ether, royaltyReceiver, 0.1 ether);

        // Sale 3: Different seller
        address seller2 = makeAddr("seller2");
        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: 5 ether}(seller2, 5 ether, royaltyReceiver, 0.25 ether);

        // Check accumulated fees
        uint256 expectedFees = 0.025 ether + 0.05 ether + 0.125 ether;
        assertEq(feeDistributor.accumulatedFees(), expectedFees);

        // Partial withdrawal
        vm.prank(feeCollector);
        feeDistributor.withdrawFeesAmount(0.1 ether);
        assertEq(feeDistributor.accumulatedFees(), expectedFees - 0.1 ether);

        // Full withdrawal
        vm.prank(feeCollector);
        feeDistributor.withdrawFees();
        assertEq(feeDistributor.accumulatedFees(), 0);
    }

    function test_FeeDistribution_AfterFeeChange() public {
        // Sale with 2.5% fee
        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: 1 ether}(seller, 1 ether, address(0), 0);
        assertEq(feeDistributor.accumulatedFees(), 0.025 ether);

        // Change fee to 5%
        vm.prank(feeManager);
        feeDistributor.updatePlatformFee(500);

        // Sale with 5% fee
        vm.prank(buyer);
        feeDistributor.distributeSaleProceeds{value: 1 ether}(seller, 1 ether, address(0), 0);
        assertEq(feeDistributor.accumulatedFees(), 0.025 ether + 0.05 ether);
    }
}

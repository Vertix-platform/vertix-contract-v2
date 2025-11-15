// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PaymentUtils} from "../../src/libraries/PaymentUtils.sol";

contract PaymentUtilsWrapper {
    function safeTransferETH(address recipient, uint256 amount) external {
        PaymentUtils.safeTransferETH(recipient, amount);
    }

    function calculatePaymentSplit(
        uint256 salePrice,
        uint256 platformFeeBps,
        uint256 royaltyAmount
    )
        external
        pure
        returns (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet)
    {
        return PaymentUtils.calculatePaymentSplit(salePrice, platformFeeBps, royaltyAmount);
    }

    function distributePayment(
        address feeCollector,
        address royaltyReceiver,
        address seller,
        uint256 platformFee,
        uint256 royaltyFee,
        uint256 sellerNet
    )
        external
    {
        PaymentUtils.distributePayment(feeCollector, royaltyReceiver, seller, platformFee, royaltyFee, sellerNet);
    }

    function validatePayment(uint256 required, uint256 provided) external pure {
        PaymentUtils.validatePayment(required, provided);
    }

    function refundExcess(uint256 required, uint256 provided, address recipient) external {
        PaymentUtils.refundExcess(required, provided, recipient);
    }

    function calculateAndDistribute(
        uint256 salePrice,
        uint256 platformFeeBps,
        uint256 royaltyAmount,
        address feeCollector,
        address royaltyReceiver,
        address seller
    )
        external
        returns (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet)
    {
        return PaymentUtils.calculateAndDistribute(
            salePrice, platformFeeBps, royaltyAmount, feeCollector, royaltyReceiver, seller
        );
    }

    receive() external payable {}
}

// Mock malicious receiver that rejects ETH
contract MaliciousReceiverReject {
    receive() external payable {
        revert("I reject your ETH");
    }
}

// Mock receiver that accepts ETH
contract GoodReceiver {
    uint256 public balance;

    receive() external payable {
        balance += msg.value;
    }

    function getBalance() external view returns (uint256) {
        return balance;
    }
}

contract PaymentUtilsTest is Test {
    PaymentUtilsWrapper public wrapper;
    GoodReceiver public receiver1;
    GoodReceiver public receiver2;
    GoodReceiver public receiver3;
    MaliciousReceiverReject public maliciousReceiver;

    address public feeCollector;
    address public royaltyReceiver;
    address public seller;

    function setUp() public {
        wrapper = new PaymentUtilsWrapper();
        receiver1 = new GoodReceiver();
        receiver2 = new GoodReceiver();
        receiver3 = new GoodReceiver();
        maliciousReceiver = new MaliciousReceiverReject();

        feeCollector = address(receiver1);
        royaltyReceiver = address(receiver2);
        seller = address(receiver3);

        // Fund wrapper with ETH for transfers
        vm.deal(address(wrapper), 100 ether);
    }

    // ============ safeTransferETH Tests ============

    function test_SafeTransferETH_Success() public {
        uint256 amount = 1 ether;
        uint256 balanceBefore = address(receiver1).balance;

        vm.prank(address(wrapper));
        PaymentUtils.safeTransferETH(address(receiver1), amount);

        assertEq(address(receiver1).balance, balanceBefore + amount);
    }

    function test_SafeTransferETH_ZeroAmount() public {
        // Should not revert, just return early
        uint256 balanceBefore = address(receiver1).balance;

        vm.prank(address(wrapper));
        PaymentUtils.safeTransferETH(address(receiver1), 0);

        assertEq(address(receiver1).balance, balanceBefore);
    }

    function test_SafeTransferETH_RevertOnFailure() public {
        uint256 amount = 1 ether;

        vm.expectRevert(
            abi.encodeWithSelector(PaymentUtils.TransferFailed.selector, address(maliciousReceiver), amount)
        );
        wrapper.safeTransferETH(address(maliciousReceiver), amount);
    }

    function testFuzz_SafeTransferETH(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 100 ether);

        uint256 balanceBefore = address(receiver1).balance;

        vm.prank(address(wrapper));
        PaymentUtils.safeTransferETH(address(receiver1), amount);

        assertEq(address(receiver1).balance, balanceBefore + amount);
    }

    // ============ calculatePaymentSplit Tests ============

    function test_CalculatePaymentSplit_NoFees() public view {
        uint256 salePrice = 10 ether;
        uint256 platformFeeBps = 0;
        uint256 royaltyAmount = 0;

        (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet) =
            wrapper.calculatePaymentSplit(salePrice, platformFeeBps, royaltyAmount);

        assertEq(platformFee, 0);
        assertEq(royaltyFee, 0);
        assertEq(sellerNet, 10 ether);
    }

    function test_CalculatePaymentSplit_OnlyPlatformFee() public view {
        uint256 salePrice = 10 ether;
        uint256 platformFeeBps = 250; // 2.5%
        uint256 royaltyAmount = 0;

        (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet) =
            wrapper.calculatePaymentSplit(salePrice, platformFeeBps, royaltyAmount);

        assertEq(platformFee, 0.25 ether); // 2.5% of 10 ETH
        assertEq(royaltyFee, 0);
        assertEq(sellerNet, 9.75 ether);
    }

    function test_CalculatePaymentSplit_OnlyRoyalty() public view {
        uint256 salePrice = 10 ether;
        uint256 platformFeeBps = 0;
        uint256 royaltyAmount = 0.5 ether;

        (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet) =
            wrapper.calculatePaymentSplit(salePrice, platformFeeBps, royaltyAmount);

        assertEq(platformFee, 0);
        assertEq(royaltyFee, 0.5 ether);
        assertEq(sellerNet, 9.5 ether);
    }

    function test_CalculatePaymentSplit_BothFees() public view {
        uint256 salePrice = 10 ether;
        uint256 platformFeeBps = 250; // 2.5%
        uint256 royaltyAmount = 0.5 ether; // 5%

        (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet) =
            wrapper.calculatePaymentSplit(salePrice, platformFeeBps, royaltyAmount);

        assertEq(platformFee, 0.25 ether);
        assertEq(royaltyFee, 0.5 ether);
        assertEq(sellerNet, 9.25 ether);
    }

    function test_CalculatePaymentSplit_HighFees() public view {
        uint256 salePrice = 10 ether;
        uint256 platformFeeBps = 1000; // 10%
        uint256 royaltyAmount = 1 ether; // 10%

        (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet) =
            wrapper.calculatePaymentSplit(salePrice, platformFeeBps, royaltyAmount);

        assertEq(platformFee, 1 ether);
        assertEq(royaltyFee, 1 ether);
        assertEq(sellerNet, 8 ether);
    }

    function testFuzz_CalculatePaymentSplit(
        uint256 salePrice,
        uint256 platformFeeBps,
        uint256 royaltyAmount
    )
        public
        view
    {
        // Bound inputs to reasonable ranges
        vm.assume(salePrice > 0 && salePrice <= 1000 ether);
        vm.assume(platformFeeBps <= 10_000); // Max 100%
        vm.assume(royaltyAmount <= salePrice);

        // Calculate platform fee and ensure total fees don't exceed sale price
        uint256 platformFee = (salePrice * platformFeeBps) / 10_000;
        vm.assume(platformFee + royaltyAmount <= salePrice);

        (uint256 actualPlatformFee, uint256 royaltyFee, uint256 sellerNet) =
            wrapper.calculatePaymentSplit(salePrice, platformFeeBps, royaltyAmount);

        // Verify the split adds up
        assertEq(actualPlatformFee + royaltyFee + sellerNet, salePrice);
    }

    // ============ distributePayment Tests ============

    function test_DistributePayment_AllRecipients() public {
        uint256 platformFee = 0.25 ether;
        uint256 royaltyFee = 0.5 ether;
        uint256 sellerNet = 9.25 ether;

        vm.deal(address(wrapper), platformFee + royaltyFee + sellerNet);

        wrapper.distributePayment(feeCollector, royaltyReceiver, seller, platformFee, royaltyFee, sellerNet);

        assertEq(receiver1.getBalance(), platformFee);
        assertEq(receiver2.getBalance(), royaltyFee);
        assertEq(receiver3.getBalance(), sellerNet);
    }

    function test_DistributePayment_ZeroPlatformFee() public {
        uint256 platformFee = 0;
        uint256 royaltyFee = 0.5 ether;
        uint256 sellerNet = 9.5 ether;

        vm.deal(address(wrapper), royaltyFee + sellerNet);

        wrapper.distributePayment(feeCollector, royaltyReceiver, seller, platformFee, royaltyFee, sellerNet);

        assertEq(receiver1.getBalance(), 0);
        assertEq(receiver2.getBalance(), royaltyFee);
        assertEq(receiver3.getBalance(), sellerNet);
    }

    function test_DistributePayment_ZeroRoyaltyFee() public {
        uint256 platformFee = 0.25 ether;
        uint256 royaltyFee = 0;
        uint256 sellerNet = 9.75 ether;

        vm.deal(address(wrapper), platformFee + sellerNet);

        wrapper.distributePayment(feeCollector, royaltyReceiver, seller, platformFee, royaltyFee, sellerNet);

        assertEq(receiver1.getBalance(), platformFee);
        assertEq(receiver2.getBalance(), 0);
        assertEq(receiver3.getBalance(), sellerNet);
    }

    function test_DistributePayment_ZeroRoyaltyReceiver() public {
        uint256 platformFee = 0.25 ether;
        uint256 royaltyFee = 0.5 ether;
        uint256 sellerNet = 9.25 ether;

        vm.deal(address(wrapper), platformFee + royaltyFee + sellerNet);

        wrapper.distributePayment(feeCollector, address(0), seller, platformFee, royaltyFee, sellerNet);

        assertEq(receiver1.getBalance(), platformFee);
        assertEq(receiver2.getBalance(), 0); // No royalty sent
        assertEq(receiver3.getBalance(), sellerNet);
    }

    function test_DistributePayment_AllZeroFees() public {
        uint256 platformFee = 0;
        uint256 royaltyFee = 0;
        uint256 sellerNet = 10 ether;

        vm.deal(address(wrapper), sellerNet);

        wrapper.distributePayment(feeCollector, royaltyReceiver, seller, platformFee, royaltyFee, sellerNet);

        assertEq(receiver1.getBalance(), 0);
        assertEq(receiver2.getBalance(), 0);
        assertEq(receiver3.getBalance(), sellerNet);
    }

    // ============ validatePayment Tests ============

    function test_ValidatePayment_Success() public view {
        wrapper.validatePayment(1 ether, 1 ether);
    }

    function test_ValidatePayment_ExcessPayment() public view {
        wrapper.validatePayment(1 ether, 2 ether);
    }

    function test_ValidatePayment_RevertInsufficientPayment() public {
        vm.expectRevert(abi.encodeWithSelector(PaymentUtils.InsufficientPayment.selector, 2 ether, 1 ether));
        wrapper.validatePayment(2 ether, 1 ether);
    }

    function testFuzz_ValidatePayment(uint256 required, uint256 provided) public {
        if (provided < required) {
            vm.expectRevert(abi.encodeWithSelector(PaymentUtils.InsufficientPayment.selector, required, provided));
            wrapper.validatePayment(required, provided);
        } else {
            wrapper.validatePayment(required, provided);
        }
    }

    // ============ refundExcess Tests ============

    function test_RefundExcess_WithExcess() public {
        uint256 required = 1 ether;
        uint256 provided = 2 ether;
        uint256 excess = 1 ether;

        vm.deal(address(wrapper), provided);

        uint256 balanceBefore = address(receiver1).balance;

        wrapper.refundExcess(required, provided, address(receiver1));

        assertEq(address(receiver1).balance, balanceBefore + excess);
    }

    function test_RefundExcess_NoExcess() public {
        uint256 required = 1 ether;
        uint256 provided = 1 ether;

        vm.deal(address(wrapper), provided);

        uint256 balanceBefore = address(receiver1).balance;

        wrapper.refundExcess(required, provided, address(receiver1));

        assertEq(address(receiver1).balance, balanceBefore); // No change
    }

    function test_RefundExcess_LessThanRequired() public {
        uint256 required = 2 ether;
        uint256 provided = 1 ether;

        vm.deal(address(wrapper), provided);

        uint256 balanceBefore = address(receiver1).balance;

        wrapper.refundExcess(required, provided, address(receiver1));

        assertEq(address(receiver1).balance, balanceBefore); // No change
    }

    function testFuzz_RefundExcess(uint256 required, uint256 provided) public {
        vm.assume(provided <= 100 ether);
        vm.assume(required <= 100 ether);

        vm.deal(address(wrapper), provided);

        uint256 balanceBefore = address(receiver1).balance;

        wrapper.refundExcess(required, provided, address(receiver1));

        if (provided > required) {
            assertEq(address(receiver1).balance, balanceBefore + (provided - required));
        } else {
            assertEq(address(receiver1).balance, balanceBefore);
        }
    }

    // ============ calculateAndDistribute Tests ============

    function test_CalculateAndDistribute_FullFlow() public {
        uint256 salePrice = 10 ether;
        uint256 platformFeeBps = 250; // 2.5%
        uint256 royaltyAmount = 0.5 ether;

        vm.deal(address(wrapper), salePrice);

        (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet) = wrapper.calculateAndDistribute(
            salePrice, platformFeeBps, royaltyAmount, feeCollector, royaltyReceiver, seller
        );

        // Check returned values
        assertEq(platformFee, 0.25 ether);
        assertEq(royaltyFee, 0.5 ether);
        assertEq(sellerNet, 9.25 ether);

        // Check distributions
        assertEq(receiver1.getBalance(), platformFee);
        assertEq(receiver2.getBalance(), royaltyFee);
        assertEq(receiver3.getBalance(), sellerNet);
    }

    function test_CalculateAndDistribute_NoFees() public {
        uint256 salePrice = 10 ether;
        uint256 platformFeeBps = 0;
        uint256 royaltyAmount = 0;

        vm.deal(address(wrapper), salePrice);

        (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet) = wrapper.calculateAndDistribute(
            salePrice, platformFeeBps, royaltyAmount, feeCollector, royaltyReceiver, seller
        );

        assertEq(platformFee, 0);
        assertEq(royaltyFee, 0);
        assertEq(sellerNet, 10 ether);

        assertEq(receiver1.getBalance(), 0);
        assertEq(receiver2.getBalance(), 0);
        assertEq(receiver3.getBalance(), 10 ether);
    }

    function test_CalculateAndDistribute_OnlyPlatformFee() public {
        uint256 salePrice = 10 ether;
        uint256 platformFeeBps = 250;
        uint256 royaltyAmount = 0;

        vm.deal(address(wrapper), salePrice);

        (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet) = wrapper.calculateAndDistribute(
            salePrice, platformFeeBps, royaltyAmount, feeCollector, royaltyReceiver, seller
        );

        assertEq(platformFee, 0.25 ether);
        assertEq(royaltyFee, 0);
        assertEq(sellerNet, 9.75 ether);

        assertEq(receiver1.getBalance(), 0.25 ether);
        assertEq(receiver2.getBalance(), 0);
        assertEq(receiver3.getBalance(), 9.75 ether);
    }

    function testFuzz_CalculateAndDistribute(uint256 salePrice, uint256 platformFeeBps, uint256 royaltyAmount) public {
        vm.assume(salePrice > 0 && salePrice <= 100 ether);
        vm.assume(platformFeeBps <= 10_000);
        vm.assume(royaltyAmount <= salePrice);

        // Calculate platform fee and ensure total fees don't exceed sale price
        uint256 platformFee = (salePrice * platformFeeBps) / 10_000;
        vm.assume(platformFee + royaltyAmount <= salePrice);

        vm.deal(address(wrapper), salePrice);

        uint256 collector1BalanceBefore = receiver1.getBalance();
        uint256 collector2BalanceBefore = receiver2.getBalance();
        uint256 collector3BalanceBefore = receiver3.getBalance();

        (uint256 actualPlatformFee, uint256 royaltyFee, uint256 sellerNet) = wrapper.calculateAndDistribute(
            salePrice, platformFeeBps, royaltyAmount, feeCollector, royaltyReceiver, seller
        );

        // Verify the split adds up
        assertEq(actualPlatformFee + royaltyFee + sellerNet, salePrice);

        // Verify distributions (accounting for potential zero values)
        if (actualPlatformFee > 0) {
            assertEq(receiver1.getBalance(), collector1BalanceBefore + actualPlatformFee);
        }
        if (royaltyFee > 0) {
            assertEq(receiver2.getBalance(), collector2BalanceBefore + royaltyFee);
        }
        if (sellerNet > 0) {
            assertEq(receiver3.getBalance(), collector3BalanceBefore + sellerNet);
        }
    }

    // ============ Edge Case Tests ============

    function test_EdgeCase_MaximumFees() public view {
        uint256 salePrice = 10 ether;
        uint256 platformFeeBps = 5000; // 50%
        uint256 royaltyAmount = 5 ether; // 50%

        (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet) =
            wrapper.calculatePaymentSplit(salePrice, platformFeeBps, royaltyAmount);

        assertEq(platformFee, 5 ether);
        assertEq(royaltyFee, 5 ether);
        assertEq(sellerNet, 0);
    }

    function test_EdgeCase_VerySmallAmounts() public view {
        uint256 salePrice = 1000 wei;
        uint256 platformFeeBps = 100; // 1%
        uint256 royaltyAmount = 10 wei;

        (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet) =
            wrapper.calculatePaymentSplit(salePrice, platformFeeBps, royaltyAmount);

        assertEq(platformFee, 10 wei); // 1% of 1000
        assertEq(royaltyFee, 10 wei);
        assertEq(sellerNet, 980 wei);
    }
}

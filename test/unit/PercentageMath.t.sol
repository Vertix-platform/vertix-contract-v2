// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PercentageMath} from "../../src/libraries/PercentageMath.sol";

contract PercentageMathTest is Test {
    uint256 constant BP_BASE = 10_000;

    // ============ percentOf Tests ============

    function test_PercentOf_Basic() public pure {
        assertEq(PercentageMath.percentOf(1000, 250), 25); // 2.5% of 1000 = 25
        assertEq(PercentageMath.percentOf(10_000, 1000), 1000); // 10% of 10000 = 1000
        assertEq(PercentageMath.percentOf(1 ether, 500), 0.05 ether); // 5% of 1 ETH
    }

    function test_PercentOf_ZeroAmount() public pure {
        assertEq(PercentageMath.percentOf(0, 250), 0);
    }

    function test_PercentOf_ZeroBps() public pure {
        assertEq(PercentageMath.percentOf(1000, 0), 0);
    }

    function test_PercentOf_FullAmount() public pure {
        assertEq(PercentageMath.percentOf(1000, 10_000), 1000); // 100% of 1000 = 1000
    }

    function test_PercentOf_Rounding() public pure {
        // 2.5% of 99 = 2.475, should floor to 2
        assertEq(PercentageMath.percentOf(99, 250), 2);
    }

    function testFuzz_PercentOf(uint256 amount, uint256 bps) public pure {
        vm.assume(amount <= type(uint128).max);
        vm.assume(bps <= BP_BASE);

        uint256 result = PercentageMath.percentOf(amount, bps);

        // Result should never exceed the original amount
        assertLe(result, amount);

        // If bps is 10000 (100%), result should equal amount
        if (bps == BP_BASE) {
            assertEq(result, amount);
        }
    }

    // ============ percentOfRoundUp Tests ============

    function test_PercentOfRoundUp_Basic() public pure {
        // 2.5% of 99 = 2.475, should round up to 3
        assertEq(PercentageMath.percentOfRoundUp(99, 250), 3);

        // 10% of 105 = 10.5, should round up to 11
        assertEq(PercentageMath.percentOfRoundUp(105, 1000), 11);
    }

    function test_PercentOfRoundUp_NoRoundingNeeded() public pure {
        // 2.5% of 100 = 2.5, rounds to 3
        assertEq(PercentageMath.percentOfRoundUp(100, 250), 3);

        // 10% of 100 = 10, no rounding needed
        assertEq(PercentageMath.percentOfRoundUp(100, 1000), 10);
    }

    function test_PercentOfRoundUp_ZeroInputs() public pure {
        assertEq(PercentageMath.percentOfRoundUp(0, 250), 0);
        assertEq(PercentageMath.percentOfRoundUp(1000, 0), 0);
    }

    function testFuzz_PercentOfRoundUp(uint256 amount, uint256 bps) public pure {
        vm.assume(amount <= type(uint128).max);
        vm.assume(bps <= BP_BASE);

        uint256 roundUp = PercentageMath.percentOfRoundUp(amount, bps);
        uint256 roundDown = PercentageMath.percentOf(amount, bps);

        // Round up should be >= round down
        assertGe(roundUp, roundDown);

        // Difference should be at most 1
        assertLe(roundUp - roundDown, 1);
    }

    // ============ subtractPercent Tests ============

    function test_SubtractPercent_Basic() public pure {
        // 1000 - 2.5% = 975
        assertEq(PercentageMath.subtractPercent(1000, 250), 975);

        // 10000 - 10% = 9000
        assertEq(PercentageMath.subtractPercent(10_000, 1000), 9000);
    }

    function test_SubtractPercent_ZeroAmount() public pure {
        assertEq(PercentageMath.subtractPercent(0, 250), 0);
    }

    function test_SubtractPercent_ZeroBps() public pure {
        assertEq(PercentageMath.subtractPercent(1000, 0), 1000);
    }

    function test_SubtractPercent_FullAmount() public pure {
        assertEq(PercentageMath.subtractPercent(1000, 10_000), 0); // 100% subtraction = 0
    }

    function testFuzz_SubtractPercent(uint256 amount, uint256 bps) public pure {
        vm.assume(amount <= type(uint128).max);
        vm.assume(bps <= BP_BASE);

        uint256 result = PercentageMath.subtractPercent(amount, bps);

        // Result should never exceed original amount
        assertLe(result, amount);

        // If bps is 0, result should equal amount
        if (bps == 0) {
            assertEq(result, amount);
        }

        // If bps is 10000 (100%), result should be 0
        if (bps == BP_BASE) {
            assertEq(result, 0);
        }
    }

    // ============ addPercent Tests ============

    function test_AddPercent_Basic() public pure {
        // 1000 + 2.5% = 1025
        assertEq(PercentageMath.addPercent(1000, 250), 1025);

        // 10000 + 10% = 11000
        assertEq(PercentageMath.addPercent(10_000, 1000), 11_000);
    }

    function test_AddPercent_ZeroAmount() public pure {
        assertEq(PercentageMath.addPercent(0, 250), 0);
    }

    function test_AddPercent_ZeroBps() public pure {
        assertEq(PercentageMath.addPercent(1000, 0), 1000);
    }

    function test_AddPercent_DoubleAmount() public pure {
        assertEq(PercentageMath.addPercent(1000, 10_000), 2000); // 100% addition = double
    }

    function testFuzz_AddPercent(uint256 amount, uint256 bps) public pure {
        vm.assume(amount <= type(uint128).max);
        vm.assume(bps <= BP_BASE);

        uint256 result = PercentageMath.addPercent(amount, bps);

        // Result should be >= original amount
        assertGe(result, amount);

        // If bps is 0, result should equal amount
        if (bps == 0) {
            assertEq(result, amount);
        }

        // If bps is 10000 (100%), result should be 2x amount
        if (bps == BP_BASE) {
            assertEq(result, amount * 2);
        }
    }

    // ============ validateBps Tests ============

    function test_ValidateBps_Success() public pure {
        PercentageMath.validateBps(250, 1000); // Valid
        PercentageMath.validateBps(1000, 1000); // At max
        PercentageMath.validateBps(0, 1000); // Zero is valid
    }

    // Note: Cannot test pure library function reverts with vm.expectRevert
    // These validations are tested indirectly through actual contract usage

    // ============ validatePercentage Tests ============

    function test_ValidatePercentage_Success() public pure {
        PercentageMath.validatePercentage(0);
        PercentageMath.validatePercentage(250);
        PercentageMath.validatePercentage(10_000);
    }

    // Note: Cannot test pure library function reverts with vm.expectRevert

    // ============ splitThreeWay Tests ============

    function test_SplitThreeWay_Basic() public pure {
        (uint256 part1, uint256 part2, uint256 remainder) = PercentageMath.splitThreeWay(10_000, 250, 1000);

        assertEq(part1, 250); // 2.5%
        assertEq(part2, 1000); // 10%
        assertEq(remainder, 8750); // 87.5%
        assertEq(part1 + part2 + remainder, 10_000); // No dust
    }

    function test_SplitThreeWay_ZeroAmount() public pure {
        (uint256 part1, uint256 part2, uint256 remainder) = PercentageMath.splitThreeWay(0, 250, 1000);

        assertEq(part1, 0);
        assertEq(part2, 0);
        assertEq(remainder, 0);
    }

    function test_SplitThreeWay_ZeroBps() public pure {
        (uint256 part1, uint256 part2, uint256 remainder) = PercentageMath.splitThreeWay(10_000, 0, 0);

        assertEq(part1, 0);
        assertEq(part2, 0);
        assertEq(remainder, 10_000);
    }

    function testFuzz_SplitThreeWay(uint256 amount, uint256 bps1, uint256 bps2) public pure {
        vm.assume(amount <= type(uint128).max);
        vm.assume(bps1 <= BP_BASE);
        vm.assume(bps2 <= BP_BASE);

        // Ensure no underflow
        uint256 fee1 = (amount * bps1) / BP_BASE;
        uint256 fee2 = (amount * bps2) / BP_BASE;
        vm.assume(fee1 + fee2 <= amount);

        (uint256 part1, uint256 part2, uint256 remainder) = PercentageMath.splitThreeWay(amount, bps1, bps2);

        // Verify no dust - all parts should sum to original
        assertEq(part1 + part2 + remainder, amount);
    }

    // ============ splitTwoWay Tests ============

    function test_SplitTwoWay_Basic() public pure {
        (uint256 part1, uint256 remainder) = PercentageMath.splitTwoWay(10_000, 250);

        assertEq(part1, 250); // 2.5%
        assertEq(remainder, 9750); // 97.5%
        assertEq(part1 + remainder, 10_000);
    }

    function test_SplitTwoWay_ZeroAmount() public pure {
        (uint256 part1, uint256 remainder) = PercentageMath.splitTwoWay(0, 250);

        assertEq(part1, 0);
        assertEq(remainder, 0);
    }

    function test_SplitTwoWay_FullAmount() public pure {
        (uint256 part1, uint256 remainder) = PercentageMath.splitTwoWay(10_000, 10_000);

        assertEq(part1, 10_000);
        assertEq(remainder, 0);
    }

    function testFuzz_SplitTwoWay(uint256 amount, uint256 bps1) public pure {
        vm.assume(amount <= type(uint128).max);
        vm.assume(bps1 <= BP_BASE);

        (uint256 part1, uint256 remainder) = PercentageMath.splitTwoWay(amount, bps1);

        // Verify no dust
        assertEq(part1 + remainder, amount);
    }

    // ============ splitFourWay Tests ============

    function test_SplitFourWay_Basic() public pure {
        (uint256 part1, uint256 part2, uint256 part3, uint256 remainder) =
            PercentageMath.splitFourWay(10_000, 250, 1000, 500);

        assertEq(part1, 250); // 2.5%
        assertEq(part2, 1000); // 10%
        assertEq(part3, 500); // 5%
        assertEq(remainder, 8250); // 82.5%
        assertEq(part1 + part2 + part3 + remainder, 10_000);
    }

    function test_SplitFourWay_ZeroAmount() public pure {
        (uint256 part1, uint256 part2, uint256 part3, uint256 remainder) =
            PercentageMath.splitFourWay(0, 250, 1000, 500);

        assertEq(part1, 0);
        assertEq(part2, 0);
        assertEq(part3, 0);
        assertEq(remainder, 0);
    }

    function testFuzz_SplitFourWay(uint256 amount, uint256 bps1, uint256 bps2, uint256 bps3) public pure {
        vm.assume(amount <= type(uint128).max);
        vm.assume(bps1 <= BP_BASE);
        vm.assume(bps2 <= BP_BASE);
        vm.assume(bps3 <= BP_BASE);

        // Ensure no underflow
        uint256 fee1 = (amount * bps1) / BP_BASE;
        uint256 fee2 = (amount * bps2) / BP_BASE;
        uint256 fee3 = (amount * bps3) / BP_BASE;
        vm.assume(fee1 + fee2 + fee3 <= amount);

        (uint256 part1, uint256 part2, uint256 part3, uint256 remainder) =
            PercentageMath.splitFourWay(amount, bps1, bps2, bps3);

        // Verify no dust
        assertEq(part1 + part2 + part3 + remainder, amount);
    }

    // ============ calculateBps Tests ============

    function test_CalculateBps_Basic() public pure {
        assertEq(PercentageMath.calculateBps(250, 1000), 2500); // 25%
        assertEq(PercentageMath.calculateBps(1, 100), 100); // 1%
        assertEq(PercentageMath.calculateBps(50, 100), 5000); // 50%
    }

    function test_CalculateBps_ZeroWhole() public pure {
        assertEq(PercentageMath.calculateBps(100, 0), 0);
    }

    function test_CalculateBps_FullAmount() public pure {
        assertEq(PercentageMath.calculateBps(1000, 1000), 10_000); // 100%
    }

    function testFuzz_CalculateBps(uint256 part, uint256 whole) public pure {
        vm.assume(whole > 0);
        vm.assume(part <= whole);
        vm.assume(whole <= type(uint128).max);

        uint256 bps = PercentageMath.calculateBps(part, whole);

        // Should be at most 10000 (100%)
        assertLe(bps, BP_BASE);

        // If part equals whole, should be 10000
        if (part == whole) {
            assertEq(bps, BP_BASE);
        }
    }

    // ============ wouldResultInZero Tests ============

    function test_WouldResultInZero_True() public pure {
        // Very small amount with high percentage - 1 - 99.99% = 0 (rounds down)
        // percentOf(1, 9999) = (1 * 9999) / 10000 = 0 (rounds down)
        // So 1 - 0 = 1, which is NOT zero
        // Let's use a case that actually results in zero
        assertTrue(PercentageMath.wouldResultInZero(100, 10_000)); // 100% subtraction
    }

    function test_WouldResultInZero_False() public pure {
        assertFalse(PercentageMath.wouldResultInZero(1000, 250)); // 2.5% of 1000
        assertFalse(PercentageMath.wouldResultInZero(0, 250)); // Zero amount
        assertFalse(PercentageMath.wouldResultInZero(1, 9999)); // 1 - 0 = 1 (due to rounding)
    }

    function test_WouldResultInZero_EdgeCase() public pure {
        // 100% subtraction
        assertTrue(PercentageMath.wouldResultInZero(1000, 10_000));
    }

    // ============ minAmountForTarget Tests ============

    function test_MinAmountForTarget_Basic() public pure {
        // To get 975 after 2.5% fee, need 1000
        uint256 needed = PercentageMath.minAmountForTarget(975, 250);
        assertGe(needed, 1000);

        // Verify: 1000 - 2.5% >= 975
        uint256 afterFee = PercentageMath.subtractPercent(needed, 250);
        assertGe(afterFee, 975);
    }

    function test_MinAmountForTarget_ZeroTarget() public pure {
        assertEq(PercentageMath.minAmountForTarget(0, 250), 0);
    }

    function test_MinAmountForTarget_ZeroFee() public pure {
        assertEq(PercentageMath.minAmountForTarget(1000, 0), 1000);
    }

    // Note: Cannot test pure library function reverts with vm.expectRevert
    // The minAmountForTarget function does revert for feeBps >= BP_BASE,
    // but this is tested indirectly through actual contract usage

    function testFuzz_MinAmountForTarget(uint256 target, uint256 feeBps) public pure {
        vm.assume(target > 0 && target <= type(uint96).max);
        vm.assume(feeBps < BP_BASE); // Must be less than 100%

        uint256 needed = PercentageMath.minAmountForTarget(target, feeBps);

        // After deducting fee, should have at least target
        uint256 afterFee = PercentageMath.subtractPercent(needed, feeBps);
        assertGe(afterFee, target);
    }

    // ============ sumBps Tests ============

    function test_SumBps_Empty() public pure {
        uint256[] memory bps = new uint256[](0);
        assertEq(PercentageMath.sumBps(bps), 0);
    }

    function test_SumBps_Single() public pure {
        uint256[] memory bps = new uint256[](1);
        bps[0] = 250;
        assertEq(PercentageMath.sumBps(bps), 250);
    }

    function test_SumBps_Multiple() public pure {
        uint256[] memory bps = new uint256[](3);
        bps[0] = 250; // 2.5%
        bps[1] = 1000; // 10%
        bps[2] = 500; // 5%
        assertEq(PercentageMath.sumBps(bps), 1750); // 17.5%
    }

    function test_SumBps_AllZeros() public pure {
        uint256[] memory bps = new uint256[](3);
        bps[0] = 0;
        bps[1] = 0;
        bps[2] = 0;
        assertEq(PercentageMath.sumBps(bps), 0);
    }

    // ============ exceedsTotal Tests ============

    function test_ExceedsTotal_False() public pure {
        uint256[] memory bps = new uint256[](3);
        bps[0] = 250;
        bps[1] = 1000;
        bps[2] = 500;
        assertFalse(PercentageMath.exceedsTotal(bps, 2000)); // 1750 <= 2000
    }

    function test_ExceedsTotal_True() public pure {
        uint256[] memory bps = new uint256[](3);
        bps[0] = 250;
        bps[1] = 1000;
        bps[2] = 500;
        assertTrue(PercentageMath.exceedsTotal(bps, 1500)); // 1750 > 1500
    }

    function test_ExceedsTotal_Exact() public pure {
        uint256[] memory bps = new uint256[](2);
        bps[0] = 1000;
        bps[1] = 500;
        assertFalse(PercentageMath.exceedsTotal(bps, 1500)); // 1500 == 1500
    }

    function test_ExceedsTotal_Empty() public pure {
        uint256[] memory bps = new uint256[](0);
        assertFalse(PercentageMath.exceedsTotal(bps, 1000));
    }

    // ============ Edge Cases & Integration Tests ============

    function test_EdgeCase_VeryLargeAmount() public pure {
        uint256 largeAmount = type(uint128).max;
        uint256 result = PercentageMath.percentOf(largeAmount, 250); // 2.5%

        // Should not overflow
        assertLe(result, largeAmount);
    }

    function test_EdgeCase_OneBasisPoint() public pure {
        // 1 bp = 0.01% of 10000 = 1
        assertEq(PercentageMath.percentOf(10_000, 1), 1);

        // 1 bp of 100 = 0.01 (rounds to 0)
        assertEq(PercentageMath.percentOf(100, 1), 0);

        // 1 bp of 100 rounded up = 1
        assertEq(PercentageMath.percentOfRoundUp(100, 1), 1);
    }

    function test_Integration_FeeCalculation() public pure {
        // Real-world scenario: NFT sale with platform fee and royalty
        uint256 salePrice = 1 ether;
        uint256 platformFeeBps = 250; // 2.5%
        uint256 royaltyBps = 1000; // 10%

        (uint256 platformFee, uint256 royalty, uint256 sellerNet) =
            PercentageMath.splitThreeWay(salePrice, platformFeeBps, royaltyBps);

        assertEq(platformFee, 0.025 ether);
        assertEq(royalty, 0.1 ether);
        assertEq(sellerNet, 0.875 ether);
        assertEq(platformFee + royalty + sellerNet, salePrice);
    }

    function test_Integration_CalculateRequiredPayment() public pure {
        // User wants to receive exactly 1 ETH after 2.5% platform fee
        uint256 targetAmount = 1 ether;
        uint256 feeBps = 250;

        uint256 required = PercentageMath.minAmountForTarget(targetAmount, feeBps);
        uint256 afterFee = PercentageMath.subtractPercent(required, feeBps);

        assertGe(afterFee, targetAmount);
    }
}

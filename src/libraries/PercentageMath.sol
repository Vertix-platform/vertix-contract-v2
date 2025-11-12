// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PercentageMath
 * @notice library for percentage calculations using basis points
 * @dev 1 basis point (bp) = 0.01%, 10000 bp = 100%
 *
 * Examples:
 * - 250 bp = 2.5%
 * - 1000 bp = 10%
 * - 10000 bp = 100%
 */
library PercentageMath {
    /// @notice Basis points denominator (100%)
    uint256 internal constant BP_BASE = 10_000;

    error PercentageTooHigh(uint256 provided, uint256 maximum);
    error InvalidBasisPoints(uint256 bps);
    error AmountTooSmall();

    /**
     * @notice Calculate percentage of an amount
     * @param amount The base amount
     * @param bps Percentage in basis points (250 = 2.5%)
     * @return The calculated percentage
     *
     * @dev Returns 0 if either input is 0
     * @dev Uses standard rounding (floor)
     */
    function percentOf(uint256 amount, uint256 bps) internal pure returns (uint256) {
        if (amount == 0 || bps == 0) return 0;
        return (amount * bps) / BP_BASE;
    }

    /**
     * @notice Calculate percentage with rounding up
     * @param amount The base amount
     * @param bps Percentage in basis points
     * @return The calculated percentage (rounded up)
     *
     * @dev Useful for ensuring minimum fees are collected
     */
    function percentOfRoundUp(uint256 amount, uint256 bps) internal pure returns (uint256) {
        if (amount == 0 || bps == 0) return 0;
        return (amount * bps + BP_BASE - 1) / BP_BASE;
    }

    /**
     * @notice Calculate amount after deducting percentage
     * @param amount The original amount
     * @param bps Percentage to deduct in basis points
     * @return The amount after deduction
     *
     * @dev Example: subtractPercent(1000, 250) = 975 (deducted 2.5%)
     */
    function subtractPercent(uint256 amount, uint256 bps) internal pure returns (uint256) {
        if (amount == 0 || bps == 0) return amount;
        return amount - percentOf(amount, bps);
    }

    /**
     * @notice Calculate amount after adding percentage
     * @param amount The original amount
     * @param bps Percentage to add in basis points
     * @return The amount after addition
     *
     * @dev Example: addPercent(1000, 250) = 1025 (added 2.5%)
     */
    function addPercent(uint256 amount, uint256 bps) internal pure returns (uint256) {
        if (amount == 0 || bps == 0) return amount;
        return amount + percentOf(amount, bps);
    }

    /**
     * @notice Validate basis points are within acceptable range
     * @param bps The basis points to validate
     * @param maxBps Maximum allowed basis points
     *
     * @dev Reverts if bps > maxBps or bps > BP_BASE
     */
    function validateBps(uint256 bps, uint256 maxBps) internal pure {
        if (bps > BP_BASE) revert InvalidBasisPoints(bps);
        if (bps > maxBps) revert PercentageTooHigh(bps, maxBps);
    }

    /**
     * @notice Validate percentage is reasonable
     * @param bps The basis points to validate
     *
     * @dev Only checks bps <= 10000 (100%)
     */
    function validatePercentage(uint256 bps) internal pure {
        if (bps > BP_BASE) revert InvalidBasisPoints(bps);
    }

    /**
     * @notice Split amount into three parts based on percentages
     * @param amount Total amount to split
     * @param bps1 First recipient percentage
     * @param bps2 Second recipient percentage
     * @return part1 First recipient amount
     * @return part2 Second recipient amount
     * @return remainder Amount remaining (goes to third recipient)
     *
     * @dev Ensures no dust is lost: part1 + part2 + remainder = amount
     * @dev Example: splitThreeWay(10000, 250, 1000) = (250, 1000, 8750)
     *      Platform fee: 2.5% = 250
     *      Royalty: 10% = 1000
     *      Seller: remainder = 8750
     */
    function splitThreeWay(
        uint256 amount,
        uint256 bps1,
        uint256 bps2
    )
        internal
        pure
        returns (uint256 part1, uint256 part2, uint256 remainder)
    {
        if (amount == 0) return (0, 0, 0);

        part1 = percentOf(amount, bps1);
        part2 = percentOf(amount, bps2);

        // Calculate remainder to avoid dust accumulation
        // This ensures part1 + part2 + remainder = amount exactly
        remainder = amount - part1 - part2;

        return (part1, part2, remainder);
    }

    /**
     * @notice Split amount into two parts
     * @param amount Total amount to split
     * @param bps1 First recipient percentage
     * @return part1 First recipient amount
     * @return remainder Amount remaining (goes to second recipient)
     *
     * @dev Example: splitTwoWay(10000, 250) = (250, 9750)
     */
    function splitTwoWay(uint256 amount, uint256 bps1) internal pure returns (uint256 part1, uint256 remainder) {
        if (amount == 0) return (0, 0);

        part1 = percentOf(amount, bps1);
        remainder = amount - part1;

        return (part1, remainder);
    }

    /**
     * @notice Split amount into four parts
     * @param amount Total amount to split
     * @param bps1 First recipient percentage
     * @param bps2 Second recipient percentage
     * @param bps3 Third recipient percentage
     * @return part1 First recipient amount
     * @return part2 Second recipient amount
     * @return part3 Third recipient amount
     * @return remainder Amount remaining (goes to fourth recipient)
     *
     * @dev Useful for complex fee structures with multiple recipients
     */
    function splitFourWay(
        uint256 amount,
        uint256 bps1,
        uint256 bps2,
        uint256 bps3
    )
        internal
        pure
        returns (uint256 part1, uint256 part2, uint256 part3, uint256 remainder)
    {
        if (amount == 0) return (0, 0, 0, 0);

        part1 = percentOf(amount, bps1);
        part2 = percentOf(amount, bps2);
        part3 = percentOf(amount, bps3);
        remainder = amount - part1 - part2 - part3;

        return (part1, part2, part3, remainder);
    }

    /**
     * @notice Calculate what percentage one value is of another
     * @param part The part value
     * @param whole The whole value
     * @return Basis points representing the percentage
     *
     * @dev Example: calculateBps(250, 1000) = 2500 (25%)
     * @dev Returns 0 if whole is 0
     */
    function calculateBps(uint256 part, uint256 whole) internal pure returns (uint256) {
        if (whole == 0) return 0;
        return (part * BP_BASE) / whole;
    }

    /**
     * @notice Check if deducting percentage would result in zero
     * @param amount The amount to check
     * @param bps The percentage to deduct
     * @return True if result would be zero
     */
    function wouldResultInZero(uint256 amount, uint256 bps) internal pure returns (bool) {
        return amount > 0 && subtractPercent(amount, bps) == 0;
    }

    /**
     * @notice Calculate minimum amount needed to yield target after fee
     * @param targetAmount Desired amount after fee deduction
     * @param feeBps Fee percentage in basis points
     * @return Minimum input amount needed
     *
     * @dev Example: minAmountForTarget(975, 250) = 1000
     *      To get 975 after 2.5% fee, need to start with 1000
     */
    function minAmountForTarget(uint256 targetAmount, uint256 feeBps) internal pure returns (uint256) {
        if (targetAmount == 0 || feeBps == 0) return targetAmount;
        if (feeBps >= BP_BASE) revert InvalidBasisPoints(feeBps);

        // amount = target / (1 - fee%)
        // In basis points: amount = target * BP_BASE / (BP_BASE - feeBps)
        return (targetAmount * BP_BASE + (BP_BASE - feeBps - 1)) / (BP_BASE - feeBps);
    }

    /**
     * @notice Sum multiple basis points values
     * @param bps Array of basis points
     * @return Total sum
     *
     * @dev Useful for validating total fees don't exceed 100%
     */
    function sumBps(uint256[] memory bps) internal pure returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < bps.length; i++) {
            total += bps[i];
        }
        return total;
    }

    /**
     * @notice Check if sum of percentages exceeds limit
     * @param bps Array of basis points
     * @param maxTotal Maximum allowed total
     * @return True if sum exceeds max
     */
    function exceedsTotal(uint256[] memory bps, uint256 maxTotal) internal pure returns (bool) {
        return sumBps(bps) > maxTotal;
    }
}

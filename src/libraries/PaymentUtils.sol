// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PercentageMath} from "./PercentageMath.sol";
import {AssetTypes} from "./AssetTypes.sol";

/**
 * @title PaymentUtils
 * @notice Library for safe payment transfers and fee calculations
 */
library PaymentUtils {
    using PercentageMath for uint256;

    error TransferFailed(address recipient, uint256 amount);

    error InsufficientPayment(uint256 required, uint256 provided);

    function safeTransferETH(address recipient, uint256 amount) internal {
        if (amount == 0) return;

        (bool success,) = recipient.call{value: amount}("");
        if (!success) {
            revert TransferFailed(recipient, amount);
        }
    }

    function calculatePaymentSplit(
        uint256 salePrice,
        uint256 platformFeeBps,
        uint256 royaltyAmount
    )
        internal
        pure
        returns (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet)
    {
        platformFee = salePrice.percentOf(platformFeeBps);
        royaltyFee = royaltyAmount;
        sellerNet = salePrice - platformFee - royaltyFee;

        return (platformFee, royaltyFee, sellerNet);
    }

    function distributePayment(
        address feeCollector,
        address royaltyReceiver,
        address seller,
        uint256 platformFee,
        uint256 royaltyFee,
        uint256 sellerNet
    )
        internal
    {
        if (platformFee > 0) {
            safeTransferETH(feeCollector, platformFee);
        }

        if (royaltyFee > 0 && royaltyReceiver != address(0)) {
            safeTransferETH(royaltyReceiver, royaltyFee);
        }

        if (sellerNet > 0) {
            safeTransferETH(seller, sellerNet);
        }
    }

    function validatePayment(uint256 required, uint256 provided) internal pure {
        if (provided < required) {
            revert InsufficientPayment(required, provided);
        }
    }

    function refundExcess(uint256 required, uint256 provided, address recipient) internal {
        if (provided > required) {
            uint256 excess = provided - required;
            safeTransferETH(recipient, excess);
        }
    }

    function calculateAndDistribute(
        uint256 salePrice,
        uint256 platformFeeBps,
        uint256 royaltyAmount,
        address feeCollector,
        address royaltyReceiver,
        address seller
    )
        internal
        returns (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet)
    {
        (platformFee, royaltyFee, sellerNet) = calculatePaymentSplit(salePrice, platformFeeBps, royaltyAmount);

        distributePayment(feeCollector, royaltyReceiver, seller, platformFee, royaltyFee, sellerNet);

        return (platformFee, royaltyFee, sellerNet);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IFeeDistributor {
    struct PaymentDistribution {
        uint256 platformFee;
        uint256 royaltyFee;
        uint256 sellerNet;
        address royaltyReceiver;
    }

    // ============================================
    //                 EVENTS
    // ============================================

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

    // ============================================
    //                ERRORS
    // ============================================

    error IncorrectPayment();
    error InvalidSeller();
    error InvalidRoyaltyReceiver();
    error NotFeeCollector();
    error NoFeesToWithdraw();
    error InsufficientFees();
    error RoyaltyTooHigh();
    error InvalidFeeCollector();
    error InvalidFeeBps(uint256 bps);
    error DistributionFailed(address recipient, uint256 amount);

    // ============================================
    //             FUNCTIONS
    // ============================================

    function distributeSaleProceeds(
        address seller,
        uint256 amount,
        address royaltyReceiver,
        uint256 royaltyAmount
    )
        external
        payable;

    function calculateDistribution(
        uint256 amount,
        address nftContract,
        uint256 tokenId
    )
        external
        view
        returns (PaymentDistribution memory);

    function platformFeeBps() external view returns (uint256);

    function feeCollector() external view returns (address);
}

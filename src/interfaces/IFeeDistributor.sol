// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IFeeDistributor
 * @notice Interface for payment distribution with fees and royalties
 * @dev Handles platform fees, royalties (ERC2981), and payment splits
 */
interface IFeeDistributor {
    // ============================================
    //                 STRUCTS
    // ============================================

    /**
     * @notice Payment distribution breakdown
     */
    struct PaymentDistribution {
        uint256 platformFee;
        uint256 royaltyFee;
        uint256 sellerNet;
        address royaltyReceiver;
    }

    // ============================================
    //                 EVENTS
    // ============================================

    /**
     * @notice Emitted when payment is distributed
     */
    event PaymentDistributed(
        address indexed seller,
        address indexed buyer,
        uint256 totalAmount,
        uint256 platformFee,
        uint256 royaltyFee,
        uint256 sellerNet
    );

    /**
     * @notice Emitted when platform fee is updated
     */
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);

    /**
     * @notice Emitted when fee collector is updated
     */
    event FeeCollectorUpdated(
        address indexed oldCollector,
        address indexed newCollector
    );

    /**
     * @notice Emitted when fees are received by the distributor
     */
    event FeesReceived(address indexed from, uint256 amount);

    /**
     * @notice Emitted when accumulated fees are withdrawn
     */
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
    ) external payable;

    function calculateDistribution(
        uint256 amount,
        address nftContract,
        uint256 tokenId
    ) external view returns (PaymentDistribution memory);

    function platformFeeBps() external view returns (uint256);

    function feeCollector() external view returns (address);
}

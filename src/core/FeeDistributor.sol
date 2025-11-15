// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IFeeDistributor} from "../interfaces/IFeeDistributor.sol";
import {AssetTypes} from "../libraries/AssetTypes.sol";
import {PercentageMath} from "../libraries/PercentageMath.sol";
import {Errors} from "../libraries/Errors.sol";
import {NFTOperations} from "../libraries/NFTOperations.sol";
import {PaymentUtils} from "../libraries/PaymentUtils.sol";
import {BaseMarketplaceContract} from "../base/BaseMarketplaceContract.sol";

/**
 * @title FeeDistributor
 * @notice Handles payment distribution with platform fees and royalties
 * @dev Supports ERC-2981 royalty standard and multi-recipient splits
 *
 * Payment Flow:
 * 1. Calculate platform fee (2.5% default)
 * 2. Calculate royalty (if ERC-2981 supported)
 * 3. Remaining amount goes to seller
 * 4. Distribute to all recipients
 */
contract FeeDistributor is IFeeDistributor, BaseMarketplaceContract {
    using PercentageMath for uint256;
    using ERC165Checker for address;

    // ============================================
    //             STATE VARIABLES
    // ============================================

    uint256 public platformFeeBps;

    address public feeCollector;

    uint256 public accumulatedFees;

    bytes4 private constant INTERFACE_ID_ERC2981 = 0x2a55205a;

    constructor(
        address _roleManager,
        address _feeCollector,
        uint256 _platformFeeBps
    )
        BaseMarketplaceContract(_roleManager)
    {
        if (_feeCollector == address(0)) {
            revert Errors.InvalidFeeDistributor();
        }

        PercentageMath.validateBps(_platformFeeBps, AssetTypes.MAX_FEE_BPS);

        feeCollector = _feeCollector;
        platformFeeBps = _platformFeeBps;

        emit PlatformFeeUpdated(0, _platformFeeBps);
        emit FeeCollectorUpdated(address(0), _feeCollector);
    }

    receive() external payable nonReentrant {
        accumulatedFees += msg.value;
        emit FeesReceived(msg.sender, msg.value);
    }

    /**
     * @notice Distribute sale proceeds with fees and royalties
     * @param seller Seller address
     * @param amount Total sale amount
     * @param royaltyReceiver Address to receive royalties (address(0) if none)
     * @param royaltyAmount Royalty amount (0 if none)
     * @dev Must be called with exact amount as msg.value
     */
    function distributeSaleProceeds(
        address seller,
        uint256 amount,
        address royaltyReceiver,
        uint256 royaltyAmount
    )
        external
        payable
        nonReentrant
    {
        if (msg.value != amount) {
            revert IncorrectPayment();
        }
        if (seller == address(0)) {
            revert InvalidSeller();
        }

        uint256 platformFee = amount.percentOf(platformFeeBps);

        if (royaltyAmount > 0) {
            if (royaltyReceiver == address(0)) {
                revert InvalidRoyaltyReceiver();
            }
            uint256 maxRoyalty = amount.percentOf(AssetTypes.MAX_ROYALTY_BPS);
            if (royaltyAmount > maxRoyalty) {
                revert RoyaltyTooHigh();
            }
        }

        if (platformFee + royaltyAmount > amount) {
            revert InvalidFeeBps(platformFee + royaltyAmount);
        }

        uint256 sellerNet = amount - platformFee - royaltyAmount;

        accumulatedFees += platformFee;

        if (royaltyAmount > 0) {
            PaymentUtils.safeTransferETH(royaltyReceiver, royaltyAmount);
        }

        PaymentUtils.safeTransferETH(seller, sellerNet);

        emit PaymentDistributed(seller, msg.sender, amount, platformFee, royaltyAmount, sellerNet);
    }

    /**
     * @notice Calculate payment distribution for a sale
     * @param amount Total sale amount
     * @param nftContract NFT contract address (for royalty lookup)
     * @param tokenId Token ID (for royalty lookup)
     * @return distribution PaymentDistribution struct with breakdown
     */
    function calculateDistribution(
        uint256 amount,
        address nftContract,
        uint256 tokenId
    )
        external
        view
        returns (PaymentDistribution memory distribution)
    {
        distribution.platformFee = amount.percentOf(platformFeeBps);

        (address royaltyReceiver, uint256 royaltyAmount) = NFTOperations.getRoyaltyInfo(nftContract, tokenId, amount);

        distribution.royaltyReceiver = royaltyReceiver;
        distribution.royaltyFee = royaltyAmount;

        distribution.sellerNet = amount - distribution.platformFee - distribution.royaltyFee;

        return distribution;
    }

    /**
     * @notice Update platform fee (FEE_MANAGER_ROLE only)
     * @param newFeeBps New fee in basis points
     */
    function updatePlatformFee(uint256 newFeeBps) external onlyFeeManager {
        PercentageMath.validateBps(newFeeBps, AssetTypes.MAX_FEE_BPS);

        uint256 oldFee = platformFeeBps;
        platformFeeBps = newFeeBps;

        emit PlatformFeeUpdated(oldFee, newFeeBps);
    }

    /**
     * @notice Update fee collector address (FEE_MANAGER_ROLE only)
     * @param newCollector New fee collector address
     */
    function updateFeeCollector(address newCollector) external onlyFeeManager {
        if (newCollector == address(0)) revert InvalidFeeCollector();

        address oldCollector = feeCollector;
        feeCollector = newCollector;

        emit FeeCollectorUpdated(oldCollector, newCollector);
    }

    /**
     * @notice Withdraw accumulated platform fees
     * @dev Only fee collector can withdraw
     */
    function withdrawFees() external nonReentrant {
        if (msg.sender != feeCollector) {
            revert NotFeeCollector();
        }

        uint256 amount = accumulatedFees;
        if (amount <= 0) {
            revert NoFeesToWithdraw();
        }

        accumulatedFees = 0;

        PaymentUtils.safeTransferETH(feeCollector, amount);

        emit FeesWithdrawn(feeCollector, amount);
    }

    /**
     * @notice Withdraw specific amount of fees
     * @param amount Amount to withdraw
     */
    function withdrawFeesAmount(uint256 amount) external nonReentrant {
        if (msg.sender != feeCollector) {
            revert NotFeeCollector();
        }
        if (amount <= 0) {
            revert NoFeesToWithdraw();
        }
        if (amount > accumulatedFees) {
            revert InsufficientFees();
        }

        accumulatedFees -= amount;

        PaymentUtils.safeTransferETH(feeCollector, amount);

        emit FeesWithdrawn(feeCollector, amount);
    }

    // ============================================
    //           VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Calculate platform fee for an amount
     * @param amount Sale amount
     * @return Platform fee
     */
    function calculatePlatformFee(uint256 amount) external view returns (uint256) {
        return amount.percentOf(platformFeeBps);
    }

    /**
     * @notice Calculate seller net after all fees
     * @param amount Total sale amount
     * @param royaltyAmount Royalty amount (if known)
     * @return Net amount to seller
     */
    function calculateSellerNet(uint256 amount, uint256 royaltyAmount) external view returns (uint256) {
        uint256 platformFee = amount.percentOf(platformFeeBps);
        return amount - platformFee - royaltyAmount;
    }

    /**
     * @notice Check if NFT contract supports royalties
     * @param nftContract NFT contract address
     * @return True if supports ERC-2981
     */
    function supportsRoyalties(address nftContract) external view returns (bool) {
        return NFTOperations.supportsRoyalties(nftContract);
    }
}

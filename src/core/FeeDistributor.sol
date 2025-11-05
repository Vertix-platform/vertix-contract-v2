// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IFeeDistributor} from "../interfaces/IFeeDistributor.sol";
import {AssetTypes} from "../libraries/AssetTypes.sol";
import {PercentageMath} from "../libraries/PercentageMath.sol";
import {Errors} from "../libraries/Errors.sol";
import {RoleManager} from "../access/RoleManager.sol";

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
contract FeeDistributor is IFeeDistributor, ReentrancyGuard {
    using PercentageMath for uint256;
    using ERC165Checker for address;

    // ============================================
    //             STATE VARIABLES
    // ============================================

    /// @notice Platform fee in basis points (250 = 2.5%)
    uint256 public platformFeeBps;

    /// @notice Address receiving platform fees
    address public feeCollector;

    /// @notice Reference to role manager for access control
    RoleManager public immutable roleManager;

    /// @notice Accumulated fees available for withdrawal
    uint256 public accumulatedFees;

    /// @notice ERC-2981 interface ID
    bytes4 private constant INTERFACE_ID_ERC2981 = 0x2a55205a;

    // ============================================
    //              CONSTRUCTOR
    // ============================================

    /**
     * @notice Initialize fee distributor
     * @param _roleManager Address of role manager contract
     * @param _feeCollector Address to receive platform fees
     * @param _platformFeeBps Initial platform fee in basis points
     */
    constructor(
        address _roleManager,
        address _feeCollector,
        uint256 _platformFeeBps
    ) {
        if (_roleManager == address(0)) {
            revert Errors.InvalidRoleManager();
        }
        if (_feeCollector == address(0)) {
            revert Errors.InvalidFeeDistributor();
        }

        PercentageMath.validateBps(_platformFeeBps, AssetTypes.MAX_FEE_BPS);

        roleManager = RoleManager(_roleManager);
        feeCollector = _feeCollector;
        platformFeeBps = _platformFeeBps;
    }

    receive() external payable {
        accumulatedFees += msg.value;
        emit FeesReceived(msg.sender, msg.value);
    }

    // ============================================
    //          CORE FUNCTIONS
    // ============================================

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
    ) external payable nonReentrant {
        if (msg.value != amount) {
            revert IncorrectPayment();
        }
        if (seller == address(0)) {
            revert InvalidSeller();
        }

        // Calculate platform fee
        uint256 platformFee = amount.percentOf(platformFeeBps);

        // Validate royalty amount doesn't exceed limits
        if (royaltyAmount > 0) {
            if (royaltyReceiver == address(0)) {
                revert InvalidRoyaltyReceiver();
            }
            uint256 maxRoyalty = amount.percentOf(AssetTypes.MAX_ROYALTY_BPS);
            if (royaltyAmount > maxRoyalty) {
                revert RoyaltyTooHigh();
            }
        }

        // Calculate seller net
        uint256 sellerNet = amount - platformFee - royaltyAmount;

        // Accumulate platform fee (pull pattern)
        accumulatedFees += platformFee;

        // Transfer royalty if applicable
        if (royaltyAmount > 0) {
            _safeTransfer(royaltyReceiver, royaltyAmount);
        }

        // Transfer to seller
        _safeTransfer(seller, sellerNet);

        emit PaymentDistributed(
            seller,
            msg.sender,
            amount,
            platformFee,
            royaltyAmount,
            sellerNet
        );
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
    ) external view returns (PaymentDistribution memory distribution) {
        // Calculate platform fee
        distribution.platformFee = amount.percentOf(platformFeeBps);

        // Try to get royalty info (ERC-2981)
        (address royaltyReceiver, uint256 royaltyAmount) = _getRoyaltyInfo(
            nftContract,
            tokenId,
            amount
        );

        distribution.royaltyReceiver = royaltyReceiver;
        distribution.royaltyFee = royaltyAmount;

        // Calculate seller net
        distribution.sellerNet =
            amount -
            distribution.platformFee -
            distribution.royaltyFee;

        return distribution;
    }

    // ============================================
    //          ADMIN FUNCTIONS
    // ============================================

    /**
     * @notice Update platform fee (FEE_MANAGER_ROLE only)
     * @param newFeeBps New fee in basis points
     */
    function updatePlatformFee(uint256 newFeeBps) external {
        if (!roleManager.hasRole(roleManager.FEE_MANAGER_ROLE(), msg.sender)) {
            revert Errors.NotFeeManager(msg.sender);
        }

        PercentageMath.validateBps(newFeeBps, AssetTypes.MAX_FEE_BPS);

        uint256 oldFee = platformFeeBps;
        platformFeeBps = newFeeBps;

        emit PlatformFeeUpdated(oldFee, newFeeBps);
    }

    /**
     * @notice Update fee collector address (FEE_MANAGER_ROLE only)
     * @param newCollector New fee collector address
     */
    function updateFeeCollector(address newCollector) external {
        if (!roleManager.hasRole(roleManager.FEE_MANAGER_ROLE(), msg.sender)) {
            revert Errors.NotFeeManager(msg.sender);
        }

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

        _safeTransfer(feeCollector, amount);

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

        _safeTransfer(feeCollector, amount);

        emit FeesWithdrawn(feeCollector, amount);
    }

    // ============================================
    //           INTERNAL FUNCTIONS
    // ============================================

    /**
     * @notice Get royalty info from ERC-2981 contract
     * @param nftContract NFT contract address
     * @param tokenId Token ID
     * @param salePrice Sale price
     * @return receiver Royalty receiver address
     * @return royaltyAmount Royalty amount
     * @dev Returns (address(0), 0) if contract doesn't support ERC-2981
     */
    function _getRoyaltyInfo(
        address nftContract,
        uint256 tokenId,
        uint256 salePrice
    ) internal view returns (address receiver, uint256 royaltyAmount) {
        // Check if contract supports ERC-2981
        if (!nftContract.supportsInterface(INTERFACE_ID_ERC2981)) {
            return (address(0), 0);
        }

        // Try to get royalty info
        try IERC2981(nftContract).royaltyInfo(tokenId, salePrice) returns (
            address _receiver,
            uint256 _royaltyAmount
        ) {
            // Validate royalty doesn't exceed maximum
            uint256 maxRoyalty = salePrice.percentOf(
                AssetTypes.MAX_ROYALTY_BPS
            );
            if (_royaltyAmount > maxRoyalty) {
                _royaltyAmount = maxRoyalty;
            }

            return (_receiver, _royaltyAmount);
        } catch {
            return (address(0), 0);
        }
    }

    /**
     * @notice Safe ETH transfer with proper error handling
     * @param recipient Recipient address
     * @param amount Amount to transfer
     */
    function _safeTransfer(address recipient, uint256 amount) internal {
        if (amount == 0) return;

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) revert DistributionFailed(recipient, amount);
    }

    // ============================================
    //           VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Calculate platform fee for an amount
     * @param amount Sale amount
     * @return Platform fee
     */
    function calculatePlatformFee(
        uint256 amount
    ) external view returns (uint256) {
        return amount.percentOf(platformFeeBps);
    }

    /**
     * @notice Calculate seller net after all fees
     * @param amount Total sale amount
     * @param royaltyAmount Royalty amount (if known)
     * @return Net amount to seller
     */
    function calculateSellerNet(
        uint256 amount,
        uint256 royaltyAmount
    ) external view returns (uint256) {
        uint256 platformFee = amount.percentOf(platformFeeBps);
        return amount - platformFee - royaltyAmount;
    }

    /**
     * @notice Check if NFT contract supports royalties
     * @param nftContract NFT contract address
     * @return True if supports ERC-2981
     */
    function supportsRoyalties(
        address nftContract
    ) external view returns (bool) {
        return nftContract.supportsInterface(INTERFACE_ID_ERC2981);
    }
}

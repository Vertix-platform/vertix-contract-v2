// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/IEscrowManager.sol";
import "../libraries/AssetTypes.sol";
import "../libraries/PercentageMath.sol";
import "../libraries/EscrowLogic.sol";
import "../access/RoleManager.sol";
import "../core/FeeDistributor.sol";

/**
 * @title EscrowManager
 * @notice Time-locked escrow system for off-chain digital asset sales
 * @dev Handles social media accounts, websites, domains, and other assets requiring verification
 *
 * Escrow Flow:
 * 1. Buyer creates escrow (locks payment)
 * 2. Seller transfers asset off-chain (email, credentials, etc.)
 * 3. Seller marks as delivered on-chain
 * 4. Buyer has verification period to test asset
 * 5. Buyer confirms receipt OR deadline passes → Funds released
 * 6. Either party can dispute → Admin resolution
 *
 * Security Features:
 * - Time-locked releases (7/30/60/90 day options)
 * - Buyer verification period (50% of duration)
 * - Dispute mechanism with evidence submission
 * - Admin resolution for disputes
 * - Cancellation with compensation for seller if work done
 */
contract EscrowManager is IEscrowManager, ReentrancyGuard, Pausable {
    using PercentageMath for uint256;
    using EscrowLogic for *;
    using AssetTypes for AssetTypes.AssetType;

    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Escrow counter for unique IDs
    uint256 public escrowCounter;

    /// @notice Mapping from escrow ID to escrow data
    mapping(uint256 => Escrow) public escrows;

    /// @notice Mapping from escrow ID to metadata URI
    mapping(uint256 => string) public escrowMetadata;

    /// @notice Buyer address => array of escrow IDs
    mapping(address => uint256[]) public buyerEscrows;

    /// @notice Seller address => array of escrow IDs
    mapping(address => uint256[]) public sellerEscrows;

    /// @notice Platform fee in basis points
    uint256 public platformFeeBps;

    /// @notice Reference to role manager
    RoleManager public immutable roleManager;

    /// @notice Reference to fee distributor
    FeeDistributor public immutable feeDistributor;

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /**
     * @notice Initialize escrow manager
     * @param _roleManager Address of role manager contract
     * @param _feeDistributor Address of fee distributor contract
     * @param _platformFeeBps Initial platform fee in basis points
     */
    constructor(
        address _roleManager,
        address _feeDistributor,
        uint256 _platformFeeBps
    ) {
        require(_roleManager != address(0), "Invalid role manager");
        require(_feeDistributor != address(0), "Invalid fee distributor");

        PercentageMath.validateBps(_platformFeeBps, AssetTypes.MAX_FEE_BPS);

        roleManager = RoleManager(_roleManager);
        feeDistributor = FeeDistributor(payable(_feeDistributor));
        platformFeeBps = _platformFeeBps;
    }

    // ============================================
    // CORE FUNCTIONS
    // ============================================

    /**
     * @notice Create a new escrow for digital asset purchase
     * @param seller Address of the asset seller
     * @param assetType Type of asset being sold
     * @param duration Escrow duration in seconds
     * @param assetHash Hash of asset details (verified off-chain)
     * @param metadataURI IPFS link to full asset metadata
     * @return escrowId Unique identifier for the escrow
     */
    function createEscrow(
        address seller,
        AssetTypes.AssetType assetType,
        uint256 duration,
        bytes32 assetHash,
        string calldata metadataURI
    ) external payable whenNotPaused nonReentrant returns (uint256 escrowId) {
        // Validate inputs
        EscrowLogic.validateEscrowParams(
            msg.sender,
            seller,
            msg.value,
            duration
        );
        EscrowLogic.validateHash(assetHash);
        EscrowLogic.validateMetadataURI(metadataURI);
        assetType.validateAssetType();

        // Ensure asset type requires escrow
        require(assetType.requiresEscrow(), "Asset type doesn't need escrow");

        // Validate amount is reasonable for asset type
        require(
            EscrowLogic.isReasonableAmount(msg.value, assetType),
            "Amount seems unreasonable"
        );

        // Increment counter
        escrowCounter++;
        escrowId = escrowCounter;

        // Calculate deadlines
        (
            uint256 releaseTime,
            uint256 verificationDeadline,
            uint256 disputeDeadline
        ) = EscrowLogic.calculateDeadlines(duration);

        // Create escrow (storage optimized)
        escrows[escrowId] = Escrow({
            buyer: msg.sender,
            amount: uint96(msg.value),
            seller: seller,
            paymentToken: address(0), // Native token (ETH/MATIC)
            assetType: assetType,
            state: AssetTypes.EscrowState.Active,
            createdAt: uint32(block.timestamp),
            releaseTime: uint32(releaseTime),
            verificationDeadline: uint32(verificationDeadline),
            disputeDeadline: uint32(disputeDeadline),
            buyerConfirmed: false,
            sellerDelivered: false,
            assetHash: assetHash
        });

        // Store metadata
        escrowMetadata[escrowId] = metadataURI;

        // Track escrows by user
        buyerEscrows[msg.sender].push(escrowId);
        sellerEscrows[seller].push(escrowId);

        emit EscrowCreated(
            escrowId,
            msg.sender,
            seller,
            msg.value,
            assetType,
            releaseTime,
            metadataURI
        );

        return escrowId;
    }

    /**
     * @notice Seller marks asset as delivered
     * @param escrowId Escrow identifier
     * @dev Called after seller transfers credentials/access off-chain
     */
    function markAssetDelivered(
        uint256 escrowId
    ) external whenNotPaused nonReentrant {
        Escrow storage escrow = escrows[escrowId];

        // Validate escrow exists and is active
        _validateEscrowExists(escrowId);
        _requireEscrowState(escrow, AssetTypes.EscrowState.Active);

        // Only seller can mark delivered
        if (msg.sender != escrow.seller) {
            revert UnauthorizedCaller(msg.sender, escrow.seller);
        }

        // Check not already delivered
        if (escrow.sellerDelivered) {
            revert EscrowAlreadyDelivered(escrowId);
        }

        // Update state
        escrow.state = AssetTypes.EscrowState.Delivered;
        escrow.sellerDelivered = true;

        emit AssetDelivered(escrowId, msg.sender, block.timestamp);
    }

    /**
     * @notice Buyer confirms asset received and working
     * @param escrowId Escrow identifier
     * @dev Triggers immediate release of funds to seller
     */
    function confirmAssetReceived(
        uint256 escrowId
    ) external whenNotPaused nonReentrant {
        Escrow storage escrow = escrows[escrowId];

        // Validate
        _validateEscrowExists(escrowId);
        _requireEscrowState(escrow, AssetTypes.EscrowState.Delivered);

        // Only buyer can confirm
        if (msg.sender != escrow.buyer) {
            revert UnauthorizedCaller(msg.sender, escrow.buyer);
        }

        // Check seller delivered
        if (!escrow.sellerDelivered) {
            revert EscrowNotDelivered(escrowId);
        }

        // Check not already confirmed
        if (escrow.buyerConfirmed) {
            revert EscrowAlreadyConfirmed(escrowId);
        }

        // Mark confirmed
        escrow.buyerConfirmed = true;

        emit AssetReceiptConfirmed(escrowId, msg.sender, block.timestamp);

        // Trigger release
        _releaseEscrow(escrowId);
    }

    /**
     * @notice Release escrow funds to seller
     * @param escrowId Escrow identifier
     * @dev Can be called by anyone after conditions are met
     */
    function releaseEscrow(
        uint256 escrowId
    ) external whenNotPaused nonReentrant {
        Escrow storage escrow = escrows[escrowId];

        // Validate
        _validateEscrowExists(escrowId);

        // Must be in Active or Delivered state
        require(
            escrow.state == AssetTypes.EscrowState.Active ||
                escrow.state == AssetTypes.EscrowState.Delivered,
            "Invalid state for release"
        );

        // Check not in dispute
        if (escrow.state == AssetTypes.EscrowState.Disputed) {
            revert EscrowInDispute(escrowId);
        }

        // Check if releasable
        bool canRelease = EscrowLogic.canRelease(
            escrow.buyerConfirmed,
            escrow.sellerDelivered,
            escrow.releaseTime
        );

        if (!canRelease) {
            revert EscrowNotReleasable(escrowId);
        }

        _releaseEscrow(escrowId);
    }

    /**
     * @notice Internal function to release escrow
     */
    function _releaseEscrow(uint256 escrowId) internal {
        Escrow storage escrow = escrows[escrowId];

        // Update state
        escrow.state = AssetTypes.EscrowState.Completed;

        uint256 amount = uint256(escrow.amount);

        // Calculate fees
        uint256 platformFee = amount.percentOf(platformFeeBps);
        uint256 sellerNet = amount - platformFee;

        // Transfer to seller
        (bool success, ) = escrow.seller.call{value: sellerNet}("");
        require(success, "Seller transfer failed");

        // Transfer platform fee to fee distributor (will accumulate there)
        (bool feeSuccess, ) = address(feeDistributor).call{value: platformFee}(
            ""
        );
        require(feeSuccess, "Fee transfer failed");

        emit EscrowReleased(
            escrowId,
            escrow.seller,
            amount,
            platformFee,
            sellerNet
        );
    }

    /**
     * @notice Open a dispute on an escrow
     * @param escrowId Escrow identifier
     * @param reason Description of the dispute
     */
    function openDispute(
        uint256 escrowId,
        string calldata reason
    ) external whenNotPaused nonReentrant {
        Escrow storage escrow = escrows[escrowId];

        // Validate
        _validateEscrowExists(escrowId);

        // Must be buyer or seller
        require(
            msg.sender == escrow.buyer || msg.sender == escrow.seller,
            "Not authorized to dispute"
        );

        // Must be in active state (not completed/cancelled)
        require(
            escrow.state == AssetTypes.EscrowState.Active ||
                escrow.state == AssetTypes.EscrowState.Delivered,
            "Cannot dispute in current state"
        );

        // Check dispute deadline
        require(
            block.timestamp <= escrow.disputeDeadline,
            "Dispute deadline passed"
        );

        // Update state
        EscrowLogic.validateStateTransition(
            escrow.state,
            AssetTypes.EscrowState.Disputed
        );
        escrow.state = AssetTypes.EscrowState.Disputed;

        emit DisputeOpened(escrowId, msg.sender, reason, block.timestamp);
    }

    /**
     * @notice Resolve a disputed escrow (admin only)
     * @param escrowId Escrow identifier
     * @param winner Address to receive funds
     * @param amount Amount to award (can be partial split)
     */
    function resolveDispute(
        uint256 escrowId,
        address winner,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        // Only arbitrator role can resolve
        require(
            roleManager.hasRole(roleManager.ARBITRATOR_ROLE(), msg.sender),
            "Not arbitrator"
        );

        Escrow storage escrow = escrows[escrowId];

        // Validate
        _validateEscrowExists(escrowId);
        _requireEscrowState(escrow, AssetTypes.EscrowState.Disputed);

        // Winner must be buyer or seller
        require(
            winner == escrow.buyer || winner == escrow.seller,
            "Winner must be buyer or seller"
        );

        // Amount can't exceed escrow amount
        uint256 escrowAmount = uint256(escrow.amount);
        if (amount > escrowAmount) {
            revert InvalidDisputeResolution(amount, escrowAmount);
        }

        // Update state
        if (winner == escrow.buyer) {
            escrow.state = AssetTypes.EscrowState.Refunded;
        } else {
            escrow.state = AssetTypes.EscrowState.Completed;
        }

        // Transfer to winner
        (bool success, ) = winner.call{value: amount}("");
        require(success, "Winner transfer failed");

        // If partial resolution, transfer remainder to other party
        if (amount < escrowAmount) {
            address otherParty = winner == escrow.buyer
                ? escrow.seller
                : escrow.buyer;
            uint256 remainder = escrowAmount - amount;

            (bool successOther, ) = otherParty.call{value: remainder}("");
            require(successOther, "Other party transfer failed");
        }

        emit DisputeResolved(escrowId, winner, amount, msg.sender);
    }

    /**
     * @notice Cancel escrow and refund buyer
     * @param escrowId Escrow identifier
     * @dev Only buyer can cancel, only before seller delivers
     */
    function cancelEscrow(
        uint256 escrowId
    ) external whenNotPaused nonReentrant {
        Escrow storage escrow = escrows[escrowId];

        // Validate
        _validateEscrowExists(escrowId);
        _requireEscrowState(escrow, AssetTypes.EscrowState.Active);

        // Check if can cancel
        bool canCancel = EscrowLogic.canCancel(
            escrow.sellerDelivered,
            msg.sender,
            escrow.buyer
        );

        require(canCancel, "Cannot cancel escrow");

        // Calculate refund amounts
        uint256 escrowAmount = uint256(escrow.amount);
        (uint256 buyerRefund, uint256 sellerCompensation) = EscrowLogic
            .calculateCancellationFees(escrowAmount, escrow.sellerDelivered);

        // Update state
        escrow.state = AssetTypes.EscrowState.Cancelled;

        // Transfer compensation to seller if delivered
        if (sellerCompensation > 0) {
            (bool successSeller, ) = escrow.seller.call{
                value: sellerCompensation
            }("");
            require(successSeller, "Seller compensation failed");
        }

        // Refund buyer
        (bool successBuyer, ) = escrow.buyer.call{value: buyerRefund}("");
        require(successBuyer, "Buyer refund failed");

        emit EscrowCancelled(
            escrowId,
            escrow.buyer,
            buyerRefund,
            sellerCompensation
        );
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    /**
     * @notice Update platform fee (FEE_MANAGER_ROLE only)
     * @param newFeeBps New fee in basis points
     */
    function updatePlatformFee(uint256 newFeeBps) external {
        require(
            roleManager.hasRole(roleManager.FEE_MANAGER_ROLE(), msg.sender),
            "Not fee manager"
        );

        PercentageMath.validateBps(newFeeBps, AssetTypes.MAX_FEE_BPS);

        uint256 oldFee = platformFeeBps;
        platformFeeBps = newFeeBps;

        emit PlatformFeeUpdated(oldFee, newFeeBps, msg.sender);
    }

    /**
     * @notice Pause contract (PAUSER_ROLE only)
     */
    function pause() external {
        require(
            roleManager.hasRole(roleManager.PAUSER_ROLE(), msg.sender),
            "Not pauser"
        );
        _pause();
    }

    /**
     * @notice Unpause contract (ADMIN_ROLE only)
     */
    function unpause() external {
        require(
            roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender),
            "Not admin"
        );
        _unpause();
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get escrow details
     */
    function getEscrow(uint256 escrowId) external view returns (Escrow memory) {
        _validateEscrowExists(escrowId);
        return escrows[escrowId];
    }

    /**
     * @notice Get all escrows for a buyer
     */
    function getBuyerEscrows(
        address buyer
    ) external view returns (uint256[] memory) {
        return buyerEscrows[buyer];
    }

    /**
     * @notice Get all escrows for a seller
     */
    function getSellerEscrows(
        address seller
    ) external view returns (uint256[] memory) {
        return sellerEscrows[seller];
    }

    /**
     * @notice Check if escrow can be released
     */
    function canReleaseEscrow(uint256 escrowId) external view returns (bool) {
        if (escrowId == 0 || escrowId > escrowCounter) return false;

        Escrow memory escrow = escrows[escrowId];

        if (
            escrow.state != AssetTypes.EscrowState.Active &&
            escrow.state != AssetTypes.EscrowState.Delivered
        ) {
            return false;
        }

        return
            EscrowLogic.canRelease(
                escrow.buyerConfirmed,
                escrow.sellerDelivered,
                escrow.releaseTime
            );
    }

    /**
     * @notice Check if escrow can be cancelled
     */
    function canCancelEscrow(
        uint256 escrowId,
        address caller
    ) external view returns (bool) {
        if (escrowId == 0 || escrowId > escrowCounter) return false;

        Escrow memory escrow = escrows[escrowId];

        if (escrow.state != AssetTypes.EscrowState.Active) return false;

        return
            EscrowLogic.canCancel(escrow.sellerDelivered, caller, escrow.buyer);
    }

    /**
     * @notice Get escrow metadata URI
     */
    function getEscrowMetadata(
        uint256 escrowId
    ) external view returns (string memory) {
        _validateEscrowExists(escrowId);
        return escrowMetadata[escrowId];
    }

    // ============================================
    // INTERNAL HELPERS
    // ============================================

    function _validateEscrowExists(uint256 escrowId) internal view {
        if (escrowId == 0 || escrowId > escrowCounter) {
            revert InvalidEscrowId(escrowId);
        }
    }

    function _requireEscrowState(
        Escrow memory escrow,
        AssetTypes.EscrowState requiredState
    ) internal pure {
        if (escrow.state != requiredState) {
            revert EscrowNotActive(0, escrow.state);
        }
    }
}

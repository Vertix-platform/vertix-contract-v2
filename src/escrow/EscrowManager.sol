// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEscrowManager} from "../interfaces/IEscrowManager.sol";
import {AssetTypes} from "../libraries/AssetTypes.sol";
import {PercentageMath} from "../libraries/PercentageMath.sol";
import {EscrowLogic} from "../libraries/EscrowLogic.sol";
import {Errors} from "../libraries/Errors.sol";
import {PaymentUtils} from "../libraries/PaymentUtils.sol";
import {FeeDistributor} from "../core/FeeDistributor.sol";
import {BaseMarketplaceContract} from "../base/BaseMarketplaceContract.sol";

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
 */
contract EscrowManager is IEscrowManager, BaseMarketplaceContract {
    using PercentageMath for uint256;
    using EscrowLogic for *;
    using AssetTypes for AssetTypes.AssetType;

    // ============================================
    //              STATE VARIABLES
    // ============================================

    uint256 public escrowCounter;

    /// @notice Mapping from escrow ID to escrow data
    mapping(uint256 => Escrow) public escrows;

    /// @notice Mapping from escrow ID to metadata URI
    mapping(uint256 => string) public escrowMetadata;

    /// @notice Buyer address => array of escrow IDs
    mapping(address => uint256[]) public buyerEscrows;

    /// @notice Seller address => array of escrow IDs
    mapping(address => uint256[]) public sellerEscrows;

    uint256 public platformFeeBps;

    /// @notice Authorized marketplace contracts that can create escrows on behalf of buyers
    mapping(address => bool) public authorizedMarketplaces;

    FeeDistributor public immutable feeDistributor;

    constructor(
        address _roleManager,
        address _feeDistributor,
        uint256 _platformFeeBps
    )
        BaseMarketplaceContract(_roleManager)
    {
        if (_feeDistributor == address(0)) {
            revert Errors.InvalidFeeDistributor();
        }

        PercentageMath.validateBps(_platformFeeBps, AssetTypes.MAX_FEE_BPS);

        feeDistributor = FeeDistributor(payable(_feeDistributor));
        platformFeeBps = _platformFeeBps;
    }

    /**
     * @notice Create a new escrow for digital asset purchase
     * @param buyer Address of the asset buyer (explicitly passed for marketplace integrations)
     * @param seller Address of the asset seller
     * @param assetType Type of asset being sold
     * @param duration Escrow duration in seconds
     * @param assetHash Hash of asset details (verified off-chain)
     * @param metadataURI IPFS link to full asset metadata
     * @return escrowId Unique identifier for the escrow
     */
    function createEscrow(
        address buyer,
        address seller,
        AssetTypes.AssetType assetType,
        uint256 duration,
        bytes32 assetHash,
        string calldata metadataURI
    )
        external
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 escrowId)
    {
        if (buyer == seller) revert Errors.BuyerCannotBeSeller();

        if (msg.sender != buyer && !authorizedMarketplaces[msg.sender]) {
            revert Errors.UnauthorizedEscrowCreation(msg.sender, buyer);
        }

        EscrowLogic.validateEscrowParams(buyer, seller, msg.value, duration);
        EscrowLogic.validateHash(assetHash);
        EscrowLogic.validateMetadataURI(metadataURI);
        assetType.validateAssetType();

        if (!assetType.requiresEscrow()) {
            revert Errors.AssetTypeDoesNotRequireEscrow();
        }

        if (!EscrowLogic.isReasonableAmount(msg.value, assetType)) {
            revert Errors.InsufficientPayment(msg.value, 0);
        }

        escrowCounter++;
        escrowId = escrowCounter;

        (uint256 releaseTime, uint256 verificationDeadline, uint256 disputeDeadline) =
            EscrowLogic.calculateDeadlines(duration);

        escrows[escrowId] = Escrow({
            buyer: buyer,
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

        escrowMetadata[escrowId] = metadataURI;

        buyerEscrows[buyer].push(escrowId);
        sellerEscrows[seller].push(escrowId);

        emit EscrowCreated(escrowId, msg.sender, seller, msg.value, assetType, releaseTime, metadataURI);

        return escrowId;
    }

    /**
     * @notice Seller marks asset as delivered
     * @param escrowId Escrow identifier
     * @dev Called after seller transfers credentials/access off-chain
     */
    function markAssetDelivered(uint256 escrowId) external whenNotPaused nonReentrant {
        Escrow storage escrow = escrows[escrowId];

        _validateEscrowExists(escrowId);
        _requireEscrowState(escrow, AssetTypes.EscrowState.Active);

        if (msg.sender != escrow.seller) {
            revert UnauthorizedCaller(msg.sender, escrow.seller);
        }

        if (escrow.sellerDelivered) {
            revert EscrowAlreadyDelivered(escrowId);
        }

        escrow.state = AssetTypes.EscrowState.Delivered;
        escrow.sellerDelivered = true;

        emit AssetDelivered(escrowId, msg.sender, block.timestamp);
    }

    /**
     * @notice Buyer confirms asset received and working
     * @param escrowId Escrow identifier
     * @dev Triggers immediate release of funds to seller
     */
    function confirmAssetReceived(uint256 escrowId) external whenNotPaused nonReentrant {
        Escrow storage escrow = escrows[escrowId];

        _validateEscrowExists(escrowId);
        _requireEscrowState(escrow, AssetTypes.EscrowState.Delivered);

        if (msg.sender != escrow.buyer) {
            revert UnauthorizedCaller(msg.sender, escrow.buyer);
        }

        if (!escrow.sellerDelivered) {
            revert EscrowNotDelivered(escrowId);
        }

        if (escrow.buyerConfirmed) {
            revert EscrowAlreadyConfirmed(escrowId);
        }

        escrow.buyerConfirmed = true;

        emit AssetReceiptConfirmed(escrowId, msg.sender, block.timestamp);

        _releaseEscrow(escrowId);
    }

    /**
     * @notice Release escrow funds to seller
     * @param escrowId Escrow identifier
     * @dev Can be called by anyone after conditions are met
     */
    function releaseEscrow(uint256 escrowId) external whenNotPaused nonReentrant {
        Escrow storage escrow = escrows[escrowId];

        _validateEscrowExists(escrowId);

        if (escrow.state != AssetTypes.EscrowState.Active && escrow.state != AssetTypes.EscrowState.Delivered) {
            revert EscrowNotActive(escrowId, escrow.state);
        }

        if (escrow.state == AssetTypes.EscrowState.Disputed) {
            revert EscrowInDispute(escrowId);
        }

        bool canRelease = EscrowLogic.canRelease(escrow.buyerConfirmed, escrow.sellerDelivered, escrow.releaseTime);

        if (!canRelease) {
            revert EscrowNotReleasable(escrowId);
        }

        _releaseEscrow(escrowId);
    }

    function _releaseEscrow(uint256 escrowId) internal {
        Escrow storage escrow = escrows[escrowId];

        escrow.state = AssetTypes.EscrowState.Completed;

        uint256 amount = uint256(escrow.amount);

        uint256 platformFee = amount.percentOf(platformFeeBps);
        uint256 sellerNet = amount - platformFee;

        (bool success,) = escrow.seller.call{value: sellerNet}("");
        if (!success) revert Errors.SellerTransferFailed();

        (bool feeSuccess,) = address(feeDistributor).call{value: platformFee}("");
        if (!feeSuccess) revert Errors.FeeTransferFailed();

        emit EscrowReleased(escrowId, escrow.seller, amount, platformFee, sellerNet);
    }

    /**
     * @notice Open a dispute on an escrow
     * @param escrowId Escrow identifier
     * @param reason Description of the dispute
     */
    function openDispute(uint256 escrowId, string calldata reason) external whenNotPaused nonReentrant {
        Escrow storage escrow = escrows[escrowId];

        _validateEscrowExists(escrowId);

        if (msg.sender != escrow.buyer && msg.sender != escrow.seller) {
            revert Errors.NotAuthorized(msg.sender);
        }

        if (escrow.state != AssetTypes.EscrowState.Active && escrow.state != AssetTypes.EscrowState.Delivered) {
            revert EscrowNotActive(escrowId, escrow.state);
        }

        if (block.timestamp > escrow.disputeDeadline) {
            revert DisputeDeadlinePassed(escrowId);
        }

        EscrowLogic.validateStateTransition(escrow.state, AssetTypes.EscrowState.Disputed);
        escrow.state = AssetTypes.EscrowState.Disputed;

        emit DisputeOpened(escrowId, msg.sender, reason, block.timestamp);
    }

    /**
     * @notice Resolve a disputed escrow (admin only)
     * @param escrowId Escrow identifier
     * @param winner Address to receive funds
     * @param amount Amount to award (can be partial split)
     */
    function resolveDispute(uint256 escrowId, address winner, uint256 amount) external whenNotPaused nonReentrant {
        if (!roleManager.hasRole(roleManager.ARBITRATOR_ROLE(), msg.sender)) {
            revert Errors.NotAuthorized(msg.sender);
        }

        Escrow storage escrow = escrows[escrowId];

        _validateEscrowExists(escrowId);
        _requireEscrowState(escrow, AssetTypes.EscrowState.Disputed);

        if (winner != escrow.buyer && winner != escrow.seller) {
            revert Errors.NotAuthorized(winner);
        }

        uint256 escrowAmount = uint256(escrow.amount);
        if (amount > escrowAmount) {
            revert InvalidDisputeResolution(amount, escrowAmount);
        }

        if (winner == escrow.buyer) {
            escrow.state = AssetTypes.EscrowState.Refunded;
        } else {
            escrow.state = AssetTypes.EscrowState.Completed;
        }

        (bool success,) = winner.call{value: amount}("");
        if (!success) revert Errors.WinnerTransferFailed();

        if (amount < escrowAmount) {
            address otherParty = winner == escrow.buyer ? escrow.seller : escrow.buyer;
            uint256 remainder = escrowAmount - amount;

            (bool successOther,) = otherParty.call{value: remainder}("");
            if (!successOther) revert Errors.OtherPartyTransferFailed();
        }

        emit DisputeResolved(escrowId, winner, amount, msg.sender);
    }

    /**
     * @notice Cancel escrow and refund buyer
     * @param escrowId Escrow identifier
     * @dev Only buyer can cancel, only before seller delivers
     */
    function cancelEscrow(uint256 escrowId) external whenNotPaused nonReentrant {
        Escrow storage escrow = escrows[escrowId];

        _validateEscrowExists(escrowId);
        _requireEscrowState(escrow, AssetTypes.EscrowState.Active);

        bool canCancel = EscrowLogic.canCancel(escrow.sellerDelivered, msg.sender, escrow.buyer);

        if (!canCancel) revert Errors.CannotCancelEscrow();

        uint256 escrowAmount = uint256(escrow.amount);
        (uint256 buyerRefund, uint256 sellerCompensation) =
            EscrowLogic.calculateCancellationFees(escrowAmount, escrow.sellerDelivered);

        escrow.state = AssetTypes.EscrowState.Cancelled;

        if (sellerCompensation > 0) {
            (bool successSeller,) = escrow.seller.call{value: sellerCompensation}("");
            if (!successSeller) revert Errors.SellerCompensationFailed();
        }

        (bool successBuyer,) = escrow.buyer.call{value: buyerRefund}("");
        if (!successBuyer) revert Errors.BuyerRefundFailed();

        emit EscrowCancelled(escrowId, escrow.buyer, buyerRefund, sellerCompensation);
    }

    /**
     * @notice Update platform fee (FEE_MANAGER_ROLE only)
     * @param newFeeBps New fee in basis points
     */
    function updatePlatformFee(uint256 newFeeBps) external onlyFeeManager {
        PercentageMath.validateBps(newFeeBps, AssetTypes.MAX_FEE_BPS);

        uint256 oldFee = platformFeeBps;
        platformFeeBps = newFeeBps;

        emit PlatformFeeUpdated(oldFee, newFeeBps, msg.sender);
    }

    /**
     * @notice Add authorized marketplace contract
     * @param marketplace Address of marketplace contract to authorize
     * @dev Only admin can authorize marketplaces to create escrows on behalf of buyers
     */
    function addAuthorizedMarketplace(address marketplace) external onlyAdmin {
        if (marketplace == address(0)) {
            revert Errors.ZeroAddress();
        }
        if (authorizedMarketplaces[marketplace]) {
            revert Errors.AlreadyAuthorized(marketplace);
        }

        authorizedMarketplaces[marketplace] = true;

        emit MarketplaceAuthorized(marketplace, msg.sender);
    }

    /**
     * @notice Remove authorized marketplace contract
     * @param marketplace Address of marketplace contract to deauthorize
     * @dev Only admin can remove marketplace authorization
     */
    function removeAuthorizedMarketplace(address marketplace) external onlyAdmin {
        if (!authorizedMarketplaces[marketplace]) {
            revert Errors.NotAuthorized(marketplace);
        }

        authorizedMarketplaces[marketplace] = false;

        emit MarketplaceDeauthorized(marketplace, msg.sender);
    }

    // ============================================
    //             INTERNAL FUNCTIONS
    // ============================================

    function _validateEscrowExists(uint256 escrowId) internal view {
        if (escrowId == 0 || escrowId > escrowCounter) {
            revert InvalidEscrowId(escrowId);
        }
    }

    function _requireEscrowState(Escrow memory escrow, AssetTypes.EscrowState requiredState) internal pure {
        if (escrow.state != requiredState) {
            revert EscrowNotActive(0, escrow.state);
        }
    }

    // ============================================
    //              VIEW FUNCTIONS
    // ============================================

    function isAuthorizedMarketplace(address marketplace) external view returns (bool) {
        return authorizedMarketplaces[marketplace];
    }

    function getEscrow(uint256 escrowId) external view returns (Escrow memory) {
        _validateEscrowExists(escrowId);
        return escrows[escrowId];
    }

    function getBuyerEscrows(address buyer) external view returns (uint256[] memory) {
        return buyerEscrows[buyer];
    }

    function getSellerEscrows(address seller) external view returns (uint256[] memory) {
        return sellerEscrows[seller];
    }
}

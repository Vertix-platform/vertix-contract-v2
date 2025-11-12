// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetTypes} from "../libraries/AssetTypes.sol";

interface IEscrowManager {
    struct Escrow {
        address buyer;
        uint96 amount; // (up to 79B ETH)
        address seller; //
        address paymentToken;
        // (address(0) for native)
        AssetTypes.AssetType assetType;
        AssetTypes.EscrowState state;
        uint32 createdAt;
        uint32 releaseTime;
        uint32 verificationDeadline;
        uint32 disputeDeadline;
        bool buyerConfirmed;
        bool sellerDelivered;
        bytes32 assetHash;
    }

    // ============================================
    //            EVENTS
    // ============================================

    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed buyer,
        address indexed seller,
        uint256 amount,
        AssetTypes.AssetType assetType,
        uint256 releaseTime,
        string metadataURI
    );

    event AssetDelivered(uint256 indexed escrowId, address indexed seller, uint256 deliveryTimestamp);

    event AssetReceiptConfirmed(uint256 indexed escrowId, address indexed buyer, uint256 confirmationTimestamp);

    event EscrowReleased(
        uint256 indexed escrowId, address indexed seller, uint256 amount, uint256 platformFee, uint256 sellerNet
    );

    event DisputeOpened(uint256 indexed escrowId, address indexed disputedBy, string reason, uint256 timestamp);

    event DisputeResolved(uint256 indexed escrowId, address indexed winner, uint256 amount, address resolver);

    event EscrowCancelled(
        uint256 indexed escrowId, address indexed buyer, uint256 refundAmount, uint256 sellerCompensation
    );

    event PlatformFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps, address updatedBy);

    event MarketplaceAuthorized(address indexed marketplace, address indexed authorizedBy);

    /**
     * @notice Emitted when marketplace authorization is revoked
     * @param marketplace Address of deauthorized marketplace
     * @param deauthorizedBy Admin who deauthorized
     */
    event MarketplaceDeauthorized(address indexed marketplace, address indexed deauthorizedBy);

    // ============================================
    //              ERRORS
    // ============================================

    error InvalidEscrowId(uint256 escrowId);
    error UnauthorizedCaller(address caller, address required);
    error EscrowNotActive(uint256 escrowId, AssetTypes.EscrowState currentState);
    error EscrowAlreadyDelivered(uint256 escrowId);
    error EscrowNotDelivered(uint256 escrowId);
    error EscrowAlreadyConfirmed(uint256 escrowId);
    error EscrowNotReleasable(uint256 escrowId);
    error EscrowInDispute(uint256 escrowId);
    error EscrowNotDisputed(uint256 escrowId);
    error DisputeDeadlinePassed(uint256 escrowId);
    error InvalidDisputeResolution(uint256 amount, uint256 escrowAmount);
    error InsufficientPayment(uint256 provided, uint256 required);
    error InvalidFee(uint256 feeBps);

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
        returns (uint256 escrowId);

    function markAssetDelivered(uint256 escrowId) external;

    function confirmAssetReceived(uint256 escrowId) external;

    /**
     * @notice Release escrow funds to seller
     * @param escrowId Escrow identifier
     * @dev Can be called by anyone after conditions met:
     *      - Buyer confirmed, OR
     *      - Release time passed AND seller delivered
     */
    function releaseEscrow(uint256 escrowId) external;

    function openDispute(uint256 escrowId, string calldata reason) external;

    function resolveDispute(uint256 escrowId, address winner, uint256 amount) external;

    function cancelEscrow(uint256 escrowId) external;

    function getEscrow(uint256 escrowId) external view returns (Escrow memory);

    function getBuyerEscrows(address buyer) external view returns (uint256[] memory);

    function getSellerEscrows(address seller) external view returns (uint256[] memory);

    function platformFeeBps() external view returns (uint256);

    function escrowCounter() external view returns (uint256);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IEscrowManager} from "../../src/interfaces/IEscrowManager.sol";
import {AssetTypes} from "../../src/libraries/AssetTypes.sol";

/**
 * @title MockEscrowManager
 * @notice Mock escrow manager for testing OfferManager
 */
contract MockEscrowManager is IEscrowManager {
    uint256 public escrowCounter;
    mapping(uint256 => Escrow) public escrows;

    event EscrowCreatedMock(
        uint256 escrowId, address buyer, address seller, uint256 amount, AssetTypes.AssetType assetType
    );

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
        returns (uint256)
    {
        escrowCounter++;
        uint256 escrowId = escrowCounter;

        escrows[escrowId] = Escrow({
            buyer: buyer,
            amount: uint96(msg.value),
            seller: seller,
            paymentToken: address(0),
            assetType: assetType,
            state: AssetTypes.EscrowState.Active,
            createdAt: uint32(block.timestamp),
            releaseTime: uint32(block.timestamp + duration),
            verificationDeadline: uint32(block.timestamp + duration),
            disputeDeadline: uint32(block.timestamp + duration + 7 days),
            buyerConfirmed: false,
            sellerDelivered: false,
            assetHash: assetHash
        });

        emit EscrowCreatedMock(escrowId, buyer, seller, msg.value, assetType);
        emit EscrowCreated(escrowId, buyer, seller, msg.value, assetType, block.timestamp + duration, metadataURI);

        return escrowId;
    }

    function getEscrow(uint256 escrowId) external view returns (Escrow memory) {
        return escrows[escrowId];
    }

    // Unimplemented interface functions
    function markAssetDelivered(uint256) external pure {
        revert("Not implemented");
    }

    function confirmAssetReceived(uint256) external pure {
        revert("Not implemented");
    }

    function releaseEscrow(uint256) external pure {
        revert("Not implemented");
    }

    function cancelEscrow(uint256) external pure {
        revert("Not implemented");
    }

    function openDispute(uint256, string calldata) external pure {
        revert("Not implemented");
    }

    function resolveDispute(uint256, address, uint256) external pure {
        revert("Not implemented");
    }

    function getBuyerEscrows(address) external pure returns (uint256[] memory) {
        revert("Not implemented");
    }

    function getSellerEscrows(address) external pure returns (uint256[] memory) {
        revert("Not implemented");
    }

    function platformFeeBps() external pure returns (uint256) {
        revert("Not implemented");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetTypes} from "./AssetTypes.sol";
import {Errors} from "./Errors.sol";

/**
 * @title RoyaltyValidator
 * @notice Library for validating royalty-related inputs
 * @dev Provides common validation logic for NFT contracts
 */
library RoyaltyValidator {
    function validateRoyaltyFee(uint96 feeBps) internal pure {
        if (feeBps > AssetTypes.MAX_ROYALTY_BPS) {
            revert Errors.RoyaltyTooHigh(feeBps, AssetTypes.MAX_ROYALTY_BPS);
        }
    }

    function validateCreator(address creator) internal pure {
        if (creator == address(0)) {
            revert Errors.InvalidCreator();
        }
    }

    function validateRoyaltyReceiver(address receiver, uint96 feeBps) internal pure {
        if (feeBps > 0 && receiver == address(0)) {
            revert Errors.InvalidRoyaltyReceiver();
        }
    }

    function validateInitialization(address creator, address royaltyReceiver, uint96 royaltyFeeBps) internal pure {
        validateCreator(creator);
        validateRoyaltyFee(royaltyFeeBps);
        validateRoyaltyReceiver(royaltyReceiver, royaltyFeeBps);
    }
}

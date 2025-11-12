// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title MockNFT
 * @notice Mock NFT contract for testing ERC-2981 royalty functionality
 * @dev Implements IERC165 and royaltyInfo function for testing FeeDistributor
 */
contract MockNFT {
    bool private supportsRoyalty;
    address private receiver;
    uint256 private amount;

    constructor(bool _supportsRoyalty, address _receiver, uint256 _amount) {
        supportsRoyalty = _supportsRoyalty;
        receiver = _receiver;
        amount = _amount;
    }

    function royaltyInfo(uint256, uint256) external view returns (address, uint256) {
        return (receiver, amount);
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        if (interfaceId == 0x2a55205a) {
            return supportsRoyalty;
        }
        return interfaceId == type(IERC165).interfaceId;
    }
}

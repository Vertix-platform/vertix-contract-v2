// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title MockNFTRevert
 * @notice Mock NFT contract that reverts when royaltyInfo is called
 * @dev Used to test error handling in FeeDistributor when royalty queries fail
 */
contract MockNFTRevert {
    function royaltyInfo(uint256, uint256) external pure returns (address, uint256) {
        revert("Royalty error");
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x2a55205a || interfaceId == type(IERC165).interfaceId;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {AssetTypes} from "./AssetTypes.sol";
import {PercentageMath} from "./PercentageMath.sol";

/**
 * @title NFTOperations
 * @notice Library for common NFT operations across the marketplace
 * @dev Consolidates NFT transfer, validation, and royalty logic
 */
library NFTOperations {
    using PercentageMath for uint256;

    error NFTTransferFailed(address nftContract, address from, address to, uint256 tokenId);

    error InvalidNFTOwner(address nftContract, uint256 tokenId, address expected, address actual);

    error NFTNotApproved(address nftContract, address owner, address operator);

    function transferNFT(
        address nftContract,
        address from,
        address to,
        uint256 tokenId,
        uint256 quantity,
        AssetTypes.TokenStandard standard
    )
        internal
    {
        if (standard == AssetTypes.TokenStandard.ERC721) {
            try IERC721(nftContract).safeTransferFrom(from, to, tokenId) {
                // Transfer successful
            } catch {
                revert NFTTransferFailed(nftContract, from, to, tokenId);
            }
        } else {
            try IERC1155(nftContract).safeTransferFrom(from, to, tokenId, quantity, "") {
                // Transfer successful
            } catch {
                revert NFTTransferFailed(nftContract, from, to, tokenId);
            }
        }
    }

    function getRoyaltyInfo(
        address nftContract,
        uint256 tokenId,
        uint256 salePrice
    )
        internal
        view
        returns (address receiver, uint256 royaltyAmount)
    {
        try IERC2981(nftContract).royaltyInfo(tokenId, salePrice) returns (address _receiver, uint256 _amount) {
            uint256 maxRoyalty = salePrice.percentOf(AssetTypes.MAX_ROYALTY_BPS);
            if (_amount > maxRoyalty) {
                _amount = maxRoyalty;
            }
            return (_receiver, _amount);
        } catch {
            return (address(0), 0);
        }
    }

    function validateOwnership(
        address nftContract,
        uint256 tokenId,
        address expectedOwner,
        uint256 quantity,
        AssetTypes.TokenStandard standard
    )
        internal
        view
    {
        if (standard == AssetTypes.TokenStandard.ERC721) {
            address actualOwner = IERC721(nftContract).ownerOf(tokenId);
            if (actualOwner != expectedOwner) {
                revert InvalidNFTOwner(nftContract, tokenId, expectedOwner, actualOwner);
            }
        } else {
            // Must be ERC1155
            uint256 balance = IERC1155(nftContract).balanceOf(expectedOwner, tokenId);
            if (balance < quantity) {
                revert InvalidNFTOwner(nftContract, tokenId, expectedOwner, address(0));
            }
        }
    }

    function validateApproval(
        address nftContract,
        address owner,
        address operator,
        AssetTypes.TokenStandard standard
    )
        internal
        view
    {
        bool isApproved;

        if (standard == AssetTypes.TokenStandard.ERC721) {
            isApproved = IERC721(nftContract).isApprovedForAll(owner, operator);
        } else {
            isApproved = IERC1155(nftContract).isApprovedForAll(owner, operator);
        }

        if (!isApproved) {
            revert NFTNotApproved(nftContract, owner, operator);
        }
    }

    function validateApprovalWithTokenId(
        address nftContract,
        address owner,
        address operator,
        uint256 tokenId,
        AssetTypes.TokenStandard standard
    )
        internal
        view
    {
        bool isApproved;

        if (standard == AssetTypes.TokenStandard.ERC721) {
            // Check both approvalForAll and individual token approval
            isApproved = IERC721(nftContract).isApprovedForAll(owner, operator)
                || IERC721(nftContract).getApproved(tokenId) == operator;
        } else {
            // Must be ERC1155
            isApproved = IERC1155(nftContract).isApprovedForAll(owner, operator);
        }

        if (!isApproved) {
            revert NFTNotApproved(nftContract, owner, operator);
        }
    }

    function supportsRoyalties(address nftContract) internal view returns (bool) {
        try IERC2981(nftContract).supportsInterface(type(IERC2981).interfaceId) returns (bool supported) {
            return supported;
        } catch {
            return false;
        }
    }
}

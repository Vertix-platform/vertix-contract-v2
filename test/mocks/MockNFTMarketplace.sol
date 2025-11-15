// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {INFTMarketplace} from "../../src/interfaces/INFTMarketplace.sol";
import {AssetTypes} from "../../src/libraries/AssetTypes.sol";

/**
 * @title MockNFTMarketplace
 * @notice Mock NFT marketplace for testing MarketplaceCore
 */
contract MockNFTMarketplace is INFTMarketplace {
    bool public executePurchaseCalled;
    address public lastBuyer;
    address public lastSeller;

    function executePurchase(
        address buyer,
        address seller,
        address, /* nftContract */
        uint256, /* tokenId */
        uint256, /* quantity */
        AssetTypes.TokenStandard /* standard */
    )
        external
        payable
    {
        executePurchaseCalled = true;
        lastBuyer = buyer;
        lastSeller = seller;
    }

    function calculatePaymentDistribution(
        address, /* nftContract */
        uint256, /* tokenId */
        uint256 salePrice
    )
        external
        pure
        returns (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet, address royaltyReceiver)
    {
        return (0, 0, salePrice, address(0));
    }

    function marketplaceCore() external pure returns (address) {
        return address(0);
    }

    function platformFeeBps() external pure returns (uint256) {
        return 250;
    }
}

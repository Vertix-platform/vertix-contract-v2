// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../interfaces/INFTMarketplace.sol";
import "../libraries/AssetTypes.sol";
import "../libraries/PercentageMath.sol";
import "../core/FeeDistributor.sol";
import "../access/RoleManager.sol";

/**
 * @title NFTMarketplace
 * @notice Marketplace for instant NFT trading with atomic swaps
 * @dev No escrow needed - trustless via smart contract execution
 *
 * Flow:
 * 1. Seller approves marketplace contract
 * 2. Seller creates listing
 * 3. Buyer sends payment
 * 4. Single transaction: NFT transferred + payment distributed
 * 5. Platform fee + royalty deducted, seller receives net
 */
contract NFTMarketplace is INFTMarketplace, ReentrancyGuard, Pausable {
    using PercentageMath for uint256;

    // ============================================
    // STATE VARIABLES
    // ============================================

    uint256 public listingCounter;
    uint256 public platformFeeBps;

    mapping(uint256 => Listing) public listings;
    mapping(address => uint256[]) public sellerListings;
    mapping(address => mapping(uint256 => uint256)) public nftToListing; // nftContract => tokenId => listingId

    RoleManager public immutable roleManager;
    FeeDistributor public immutable feeDistributor;

    // ============================================
    // CONSTRUCTOR
    // ============================================

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
    // LISTING FUNCTIONS
    // ============================================

    function createListing(
        address nftContract,
        uint256 tokenId,
        uint256 quantity,
        uint256 price,
        AssetTypes.TokenStandard standard
    ) external whenNotPaused nonReentrant returns (uint256 listingId) {
        require(
            price > 0 && price <= AssetTypes.MAX_LISTING_PRICE,
            "Invalid price"
        );
        require(nftContract != address(0), "Invalid NFT contract");

        // Verify ownership and approval
        if (standard == AssetTypes.TokenStandard.ERC721) {
            require(quantity == 1, "ERC721 quantity must be 1");
            require(
                IERC721(nftContract).ownerOf(tokenId) == msg.sender,
                "Not owner"
            );
            require(
                IERC721(nftContract).getApproved(tokenId) == address(this) ||
                    IERC721(nftContract).isApprovedForAll(
                        msg.sender,
                        address(this)
                    ),
                "Not approved"
            );
        } else {
            require(quantity > 0, "Quantity must be > 0");
            require(
                IERC1155(nftContract).balanceOf(msg.sender, tokenId) >=
                    quantity,
                "Insufficient balance"
            );
            require(
                IERC1155(nftContract).isApprovedForAll(
                    msg.sender,
                    address(this)
                ),
                "Not approved"
            );
        }

        listingCounter++;
        listingId = listingCounter;

        listings[listingId] = Listing({
            seller: msg.sender,
            price: uint96(price),
            nftContract: nftContract,
            tokenId: uint64(tokenId),
            quantity: uint16(quantity),
            standard: standard,
            active: true
        });

        sellerListings[msg.sender].push(listingId);
        nftToListing[nftContract][tokenId] = listingId;

        emit ListingCreated(
            listingId,
            msg.sender,
            nftContract,
            tokenId,
            quantity,
            price,
            standard
        );

        return listingId;
    }

    function buyNFT(
        uint256 listingId
    ) external payable whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];

        require(listing.active, "Listing not active");
        require(msg.value == listing.price, "Incorrect payment");
        require(msg.sender != listing.seller, "Cannot buy own NFT");

        listing.active = false;

        uint256 price = uint256(listing.price);

        // Calculate royalty
        (address royaltyReceiver, uint256 royaltyAmount) = _getRoyaltyInfo(
            listing.nftContract,
            listing.tokenId,
            price
        );

        // Calculate fees
        uint256 platformFee = price.percentOf(platformFeeBps);
        uint256 sellerNet = price - platformFee - royaltyAmount;

        // Transfer NFT first (Checks-Effects-Interactions)
        if (listing.standard == AssetTypes.TokenStandard.ERC721) {
            IERC721(listing.nftContract).safeTransferFrom(
                listing.seller,
                msg.sender,
                listing.tokenId
            );
        } else {
            IERC1155(listing.nftContract).safeTransferFrom(
                listing.seller,
                msg.sender,
                listing.tokenId,
                listing.quantity,
                ""
            );
        }

        // Distribute payments
        _sendPayment(listing.seller, sellerNet);
        _sendPayment(address(feeDistributor), platformFee);
        if (royaltyAmount > 0) {
            _sendPayment(royaltyReceiver, royaltyAmount);
        }

        // Clear listing mapping
        delete nftToListing[listing.nftContract][listing.tokenId];

        emit NFTSold(
            listingId,
            msg.sender,
            listing.seller,
            listing.nftContract,
            listing.tokenId,
            listing.quantity,
            price,
            platformFee,
            royaltyAmount,
            sellerNet
        );
    }

    function cancelListing(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];

        require(listing.seller == msg.sender, "Not seller");
        require(listing.active, "Already inactive");

        listing.active = false;
        delete nftToListing[listing.nftContract][listing.tokenId];

        emit ListingCancelled(
            listingId,
            msg.sender,
            listing.nftContract,
            listing.tokenId
        );
    }

    function updateListingPrice(uint256 listingId, uint256 newPrice) external {
        Listing storage listing = listings[listingId];

        require(listing.seller == msg.sender, "Not seller");
        require(listing.active, "Listing not active");
        require(
            newPrice > 0 && newPrice <= AssetTypes.MAX_LISTING_PRICE,
            "Invalid price"
        );

        uint256 oldPrice = listing.price;
        listing.price = uint96(newPrice);

        emit ListingPriceUpdated(listingId, oldPrice, newPrice);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    function getListing(
        uint256 listingId
    ) external view returns (Listing memory) {
        return listings[listingId];
    }

    function isListingActive(uint256 listingId) external view returns (bool) {
        return listings[listingId].active;
    }

    function getSellerListings(
        address seller
    ) external view returns (uint256[] memory) {
        return sellerListings[seller];
    }

    function getListingByNFT(
        address nftContract,
        uint256 tokenId
    ) external view returns (uint256) {
        return nftToListing[nftContract][tokenId];
    }

    function calculatePaymentDistribution(
        uint256 listingId
    )
        external
        view
        returns (
            uint256 platformFee,
            uint256 royaltyFee,
            uint256 sellerNet,
            address royaltyReceiver
        )
    {
        Listing memory listing = listings[listingId];
        uint256 price = uint256(listing.price);

        platformFee = price.percentOf(platformFeeBps);
        (royaltyReceiver, royaltyFee) = _getRoyaltyInfo(
            listing.nftContract,
            listing.tokenId,
            price
        );
        sellerNet = price - platformFee - royaltyFee;

        return (platformFee, royaltyFee, sellerNet, royaltyReceiver);
    }

    // ============================================
    // INTERNAL FUNCTIONS
    // ============================================

    function _getRoyaltyInfo(
        address nftContract,
        uint256 tokenId,
        uint256 salePrice
    ) internal view returns (address receiver, uint256 royaltyAmount) {
        try IERC2981(nftContract).royaltyInfo(tokenId, salePrice) returns (
            address _receiver,
            uint256 _amount
        ) {
            uint256 maxRoyalty = salePrice.percentOf(
                AssetTypes.MAX_ROYALTY_BPS
            );
            if (_amount > maxRoyalty) _amount = maxRoyalty;
            return (_receiver, _amount);
        } catch {
            return (address(0), 0);
        }
    }

    function _sendPayment(address recipient, uint256 amount) internal {
        if (amount == 0) return;
        (bool success, ) = recipient.call{value: amount}("");
        if (!success) revert TransferFailed(recipient, amount);
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    function updatePlatformFee(uint256 newFeeBps) external {
        require(
            roleManager.hasRole(roleManager.FEE_MANAGER_ROLE(), msg.sender),
            "Not fee manager"
        );
        PercentageMath.validateBps(newFeeBps, AssetTypes.MAX_FEE_BPS);
        platformFeeBps = newFeeBps;
    }

    function pause() external {
        require(
            roleManager.hasRole(roleManager.PAUSER_ROLE(), msg.sender),
            "Not pauser"
        );
        _pause();
    }

    function unpause() external {
        require(
            roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender),
            "Not admin"
        );
        _unpause();
    }
}

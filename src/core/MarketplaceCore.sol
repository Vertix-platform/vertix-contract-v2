// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IMarketplace} from "../interfaces/IMarketplace.sol";
import {IEscrowManager} from "../interfaces/IEscrowManager.sol";
import {INFTMarketplace} from "../interfaces/INFTMarketplace.sol";
import {AssetTypes} from "../libraries/AssetTypes.sol";
import {Errors} from "../libraries/Errors.sol";
import {RoleManager} from "../access/RoleManager.sol";

/**
 * @title MarketplaceCore
 * @notice Unified marketplace router for all asset types
 * @dev Single entry point routing to specialized handlers
 *
 *
 * Architecture:
 * - NFTs (ERC721/1155) → NFTMarketplace.executePurchase()
 * - Off-chain assets → EscrowManager.createEscrow()
 */
contract MarketplaceCore is IMarketplace, ReentrancyGuard, Pausable {
    using AssetTypes for AssetTypes.AssetType;

    // ============================================
    //          STORAGE STRUCTS
    // ============================================

    /**
     * @notice NFT-specific data
     * @dev Only populated for NFT listings, packed into 1 slot
     */
    struct NFTDetails {
        address nftContract;
        uint64 tokenId;
        uint16 quantity;
        AssetTypes.TokenStandard standard;
    }

    // ============================================
    //          STATE VARIABLES
    // ============================================

    uint256 public listingCounter;

    mapping(uint256 => Listing) public listings;
    mapping(uint256 => NFTDetails) public nftDetails;
    mapping(address => uint256[]) public sellerListings;

    RoleManager public immutable roleManager;
    IEscrowManager public immutable escrowManager;
    INFTMarketplace public immutable nftMarketplace;

    // ============================================
    // EVENTS
    // ============================================

    event NFTListingCreated(
        uint256 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 quantity,
        uint256 price
    );

    event PriceUpdated(
        uint256 indexed listingId,
        uint256 oldPrice,
        uint256 newPrice
    );

    // ============================================
    //              ERRORS
    // ============================================

    error InvalidPrice();
    error NotOwner();
    error NotApproved();
    error InsufficientBalance();
    error ListingNotActive();
    error IncorrectPayment();
    error CannotBuyOwnListing();
    error NotSeller();
    error InvalidNFTParameters();

    // ============================================
    //           CONSTRUCTOR
    // ============================================

    constructor(
        address _roleManager,
        address _escrowManager,
        address _nftMarketplace
    ) {
        if (_roleManager == address(0)) revert Errors.InvalidRoleManager();
        if (_escrowManager == address(0)) revert Errors.InvalidEscrowManager();
        if (_nftMarketplace == address(0))
            revert Errors.InvalidNFTMarketplace();

        roleManager = RoleManager(_roleManager);
        escrowManager = IEscrowManager(_escrowManager);
        nftMarketplace = INFTMarketplace(_nftMarketplace);
    }

    // ============================================
    // LISTING FUNCTIONS
    // ============================================

    /**
     * @notice Create NFT listing
     * @param nftContract NFT contract address
     * @param tokenId Token ID
     * @param quantity Quantity (1 for ERC721, >1 for ERC1155)
     * @param price Listing price
     * @param standard Token standard
     * @return listingId Unique listing ID
     */
    function createNFTListing(
        address nftContract,
        uint256 tokenId,
        uint256 quantity,
        uint256 price,
        AssetTypes.TokenStandard standard
    ) external whenNotPaused nonReentrant returns (uint256 listingId) {
        if (price == 0 || price > AssetTypes.MAX_LISTING_PRICE) {
            revert InvalidPrice();
        }
        if (nftContract == address(0)) {
            revert InvalidNFTParameters();
        }

        // Verify ownership and approval
        if (standard == AssetTypes.TokenStandard.ERC721) {
            if (quantity != 1) revert InvalidNFTParameters();
            if (IERC721(nftContract).ownerOf(tokenId) != msg.sender) {
                revert NotOwner();
            }
            address approved = IERC721(nftContract).getApproved(tokenId);
            bool isApprovedForAll = IERC721(nftContract).isApprovedForAll(
                msg.sender,
                address(this)
            );
            if (approved != address(this) && !isApprovedForAll) {
                revert NotApproved();
            }
        } else {
            if (quantity == 0) revert InvalidNFTParameters();
            uint256 balance = IERC1155(nftContract).balanceOf(
                msg.sender,
                tokenId
            );
            if (balance < quantity) revert InsufficientBalance();
            if (
                !IERC1155(nftContract).isApprovedForAll(
                    msg.sender,
                    address(this)
                )
            ) {
                revert NotApproved();
            }
        }

        listingCounter++;
        listingId = listingCounter;

        // Determine asset type
        AssetTypes.AssetType assetType = standard ==
            AssetTypes.TokenStandard.ERC721
            ? AssetTypes.AssetType.NFT721
            : AssetTypes.AssetType.NFT1155;

        // Create listing
        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            assetType: assetType,
            price: price,
            status: AssetTypes.ListingStatus.Active,
            createdAt: block.timestamp,
            assetHash: bytes32(0),
            metadataURI: ""
        });

        // Store NFT details
        nftDetails[listingId] = NFTDetails({
            nftContract: nftContract,
            tokenId: uint64(tokenId),
            quantity: uint16(quantity),
            standard: standard
        });

        sellerListings[msg.sender].push(listingId);

        emit NFTListingCreated(
            listingId,
            msg.sender,
            nftContract,
            tokenId,
            quantity,
            price
        );

        return listingId;
    }

    /**
     * @notice Create off-chain asset listing
     * @param assetType Type of off-chain asset
     * @param price Listing price
     * @param assetHash Hash of asset details
     * @param metadataURI IPFS link to metadata
     * @return listingId Unique listing ID
     */
    function createOffChainListing(
        AssetTypes.AssetType assetType,
        uint256 price,
        bytes32 assetHash,
        string calldata metadataURI
    ) external whenNotPaused nonReentrant returns (uint256 listingId) {
        if (price == 0) revert InvalidPrice();
        assetType.validateAssetType();
        if (assetType.isNFTType()) revert Errors.UseCreateNFTListing();
        if (assetHash == bytes32(0)) revert Errors.AssetHashRequired();
        if (bytes(metadataURI).length == 0) revert Errors.MetadataURIRequired();

        listingCounter++;
        listingId = listingCounter;

        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            assetType: assetType,
            price: price,
            status: AssetTypes.ListingStatus.Active,
            createdAt: block.timestamp,
            assetHash: assetHash,
            metadataURI: metadataURI
        });

        sellerListings[msg.sender].push(listingId);

        emit ListingCreated(listingId, msg.sender, assetType, price);

        return listingId;
    }

    /**
     * @notice Purchase any asset (NFT or off-chain)
     * @param listingId Listing ID
     * @dev Automatically routes to appropriate handler
     */
    function purchaseAsset(
        uint256 listingId
    ) external payable whenNotPaused nonReentrant {
        Listing storage listing = listings[listingId];

        if (listing.status != AssetTypes.ListingStatus.Active) {
            revert ListingNotActive();
        }
        if (msg.value != listing.price) revert IncorrectPayment();
        if (msg.sender == listing.seller) revert CannotBuyOwnListing();

        // Mark as sold
        listing.status = AssetTypes.ListingStatus.Sold;

        // Route to appropriate handler
        if (listing.assetType.isNFTType()) {
            // NFT - delegate to NFTMarketplace
            NFTDetails memory nft = nftDetails[listingId];

            nftMarketplace.executePurchase{value: msg.value}(
                msg.sender,
                listing.seller,
                nft.nftContract,
                nft.tokenId,
                nft.quantity,
                nft.standard
            );
        } else {
            // Off-chain asset - create escrow
            uint256 duration = listing.assetType.recommendedEscrowDuration();

            escrowManager.createEscrow{value: msg.value}(
                msg.sender,
                listing.seller,
                listing.assetType,
                duration,
                listing.assetHash,
                listing.metadataURI
            );
        }

        emit ListingSold(listingId, msg.sender, listing.seller, listing.price);
    }

    /**
     * @notice Cancel a listing
     * @param listingId Listing ID
     */
    function cancelListing(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];

        if (listing.seller != msg.sender) revert NotSeller();
        if (listing.status != AssetTypes.ListingStatus.Active) {
            revert ListingNotActive();
        }

        listing.status = AssetTypes.ListingStatus.Cancelled;

        emit ListingCancelled(listingId, msg.sender);
    }

    /**
     * @notice Update listing price
     * @param listingId Listing ID
     * @param newPrice New price
     */
    function updatePrice(uint256 listingId, uint256 newPrice) external {
        Listing storage listing = listings[listingId];

        if (listing.seller != msg.sender) revert NotSeller();
        if (listing.status != AssetTypes.ListingStatus.Active) {
            revert ListingNotActive();
        }
        if (newPrice == 0 || newPrice > AssetTypes.MAX_LISTING_PRICE) {
            revert InvalidPrice();
        }

        uint256 oldPrice = listing.price;
        listing.price = newPrice;

        emit PriceUpdated(listingId, oldPrice, newPrice);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    function getListing(
        uint256 listingId
    ) external view returns (Listing memory) {
        return listings[listingId];
    }

    function getNFTDetails(
        uint256 listingId
    ) external view returns (NFTDetails memory) {
        return nftDetails[listingId];
    }

    function getSellerListings(
        address seller
    ) external view returns (uint256[] memory) {
        return sellerListings[seller];
    }

    function isNFTListing(uint256 listingId) external view returns (bool) {
        return listings[listingId].assetType.isNFTType();
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    function pause() external {
        if (!roleManager.hasRole(roleManager.PAUSER_ROLE(), msg.sender)) {
            revert Errors.NotPauser(msg.sender);
        }
        _pause();
    }

    function unpause() external {
        if (!roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender)) {
            revert Errors.NotAdmin(msg.sender);
        }
        _unpause();
    }
}

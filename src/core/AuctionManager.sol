// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAuctionManager} from "../interfaces/IAuctionManager.sol";
import {IEscrowManager} from "../interfaces/IEscrowManager.sol";
import {AssetTypes} from "../libraries/AssetTypes.sol";
import {AuctionLogic} from "../libraries/AuctionLogic.sol";
import {PercentageMath} from "../libraries/PercentageMath.sol";
import {Errors} from "../libraries/Errors.sol";
import {NFTOperations} from "../libraries/NFTOperations.sol";
import {PaymentUtils} from "../libraries/PaymentUtils.sol";
import {FeeDistributor} from "../core/FeeDistributor.sol";
import {BaseMarketplaceContract} from "../base/BaseMarketplaceContract.sol";

/**
 * @title AuctionManager all asset types
 * @notice Manages English auctions (ascending bid) for NFTs on Vertix marketplace
 * @dev Handles auction creation, bidding, settlement, and cancellation with security focus
 *
 * Features:
 * - Support for NFTs (instant transfer) and off-chain assets (via escrow)
 * - English auction (ascending bid only)
 * - Reserve price support (optional minimum winning bid)
 * - Configurable bid increment (default 5%)
 * - Automatic auction extension if bid near end (anti-sniping)
 * - Pull-over-push refund pattern (prevents DoS)
 * - Emergency withdrawal mechanism and EscrowManager
 *
 * Asset Types:
 * - NFTs: Instant atomic transfer when auction ends
 * - Off-chain assets: Automatic escrow creation buyer/seller
 */
contract AuctionManager is IAuctionManager, BaseMarketplaceContract, IERC721Receiver, IERC1155Receiver {
    using PercentageMath for uint256;
    using AuctionLogic for *;

    // ============================================
    //            STATE VARIABLES
    // ============================================

    uint256 public auctionCounter;

    uint256 public platformFeeBps;

    /// @notice Mapping from auction ID to auction data
    mapping(uint256 => Auction) public auctions;

    /// @notice Mapping seller => array of auction IDs
    mapping(address => uint256[]) public sellerAuctions;

    /// @notice Mapping bidder => array of auction IDs where they're highest bidder
    mapping(address => uint256[]) public bidderAuctions;

    /// @notice Mapping bidder => auctionId => tracked status
    mapping(address => mapping(uint256 => bool)) private bidderAuctionTracked;

    /// @notice Mapping of pending withdrawal amounts for outbid users (pull-over-push pattern)
    mapping(address => uint256) public pendingWithdrawals;

    FeeDistributor public immutable feeDistributor;
    IEscrowManager public immutable escrowManager;

    uint256 public constant EMERGENCY_WITHDRAWAL_DELAY = 7 days;

    constructor(
        address _roleManager,
        address _feeDistributor,
        address _escrowManager,
        uint256 _platformFeeBps
    )
        BaseMarketplaceContract(_roleManager)
    {
        if (_feeDistributor == address(0)) {
            revert Errors.InvalidFeeDistributor();
        }
        if (_escrowManager == address(0)) {
            revert Errors.InvalidEscrowManager();
        }

        PercentageMath.validateBps(_platformFeeBps, AssetTypes.MAX_FEE_BPS);

        feeDistributor = FeeDistributor(payable(_feeDistributor));
        escrowManager = IEscrowManager(_escrowManager);
        platformFeeBps = _platformFeeBps;
    }

    /**
     * @notice Create a new auction for any asset type
     * @param assetType Type of asset being auctioned
     * @param nftContract NFT contract address (only for NFTs, address(0) otherwise)
     * @param tokenId Token ID to auction (only for NFTs, 0 otherwise)
     * @param quantity Quantity (for ERC1155, must be 1 for ERC721, 0 for off-chain)
     * @param reservePrice Minimum winning bid (0 = no reserve)
     * @param duration Auction duration in seconds
     * @param bidIncrementBps Minimum bid increment in basis points
     * @param standard Token standard (ERC721 or ERC1155, only for NFTs)
     * @param assetHash Hash of asset details (for off-chain assets)
     * @param metadataURI IPFS link to asset metadata
     * @return auctionId Unique auction identifier
     */
    function createAuction(
        AssetTypes.AssetType assetType,
        address nftContract,
        uint256 tokenId,
        uint256 quantity,
        uint256 reservePrice,
        uint256 duration,
        uint256 bidIncrementBps,
        AssetTypes.TokenStandard standard,
        bytes32 assetHash,
        string calldata metadataURI
    )
        external
        whenNotPaused
        nonReentrant
        returns (uint256 auctionId)
    {
        AuctionLogic.validateAuctionParams(msg.sender, reservePrice, duration, bidIncrementBps);

        AssetTypes.validateAssetType(assetType);

        if (AssetTypes.isNFTType(assetType)) {
            if (nftContract == address(0)) {
                revert InvalidNFTContract(nftContract);
            }

            if (standard == AssetTypes.TokenStandard.ERC721) {
                if (quantity != 1) {
                    revert ERC721QuantityMustBe1();
                }

                address owner = IERC721(nftContract).ownerOf(tokenId);
                if (owner != msg.sender) {
                    revert NotNFTOwner(msg.sender, owner);
                }

                bool approved = IERC721(nftContract).getApproved(tokenId) == address(this)
                    || IERC721(nftContract).isApprovedForAll(msg.sender, address(this));

                if (!approved) {
                    revert NFTNotApproved(nftContract, tokenId);
                }
            } else {
                if (quantity <= 0) {
                    revert QuantityMustBeGreaterThan0();
                }

                uint256 balance = IERC1155(nftContract).balanceOf(msg.sender, tokenId);
                if (balance < quantity) {
                    revert InsufficientBalance();
                }

                bool approved = IERC1155(nftContract).isApprovedForAll(msg.sender, address(this));
                if (!approved) {
                    revert NFTNotApproved(nftContract, tokenId);
                }
            }
        } else {
            // Off-chain asset validation
            if (nftContract != address(0)) {
                revert NFTContractShouldBeZeroForOffChain();
            }
            if (tokenId != 0) {
                revert TokenIDShouldBeZeroForOffChain();
            }
            if (quantity != 0) {
                revert QuantityShouldBeZeroForOffChain();
            }

            if (assetHash == bytes32(0)) {
                revert AssetHashRequiredForOffChain();
            }
            if (bytes(metadataURI).length == 0) {
                revert MetadataURIRequiredForOffChain();
            }
        }

        auctionCounter++;
        auctionId = auctionCounter;

        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + duration;

        auctions[auctionId] = Auction({
            seller: msg.sender,
            reservePrice: uint96(reservePrice),
            nftContract: nftContract,
            highestBid: 0,
            highestBidder: address(0),
            bidIncrementBps: uint16(bidIncrementBps),
            tokenId: uint64(tokenId),
            startTime: uint32(startTime),
            endTime: uint32(endTime),
            assetType: assetType,
            standard: standard,
            active: true,
            settled: false,
            quantity: uint16(quantity),
            assetHash: assetHash,
            metadataURI: metadataURI
        });

        sellerAuctions[msg.sender].push(auctionId);

        // Escrow NFT into contract to prevent seller from revoking approval or transferring
        if (AssetTypes.isNFTType(assetType)) {
            NFTOperations.transferNFT(nftContract, msg.sender, address(this), tokenId, quantity, standard);

            emit NFTEscrowed(auctionId, nftContract, tokenId, quantity, standard);
        }

        emit AuctionCreated(
            auctionId, msg.sender, assetType, nftContract, tokenId, reservePrice, startTime, endTime, bidIncrementBps
        );

        return auctionId;
    }

    /**
     * @notice Place a bid on an auction
     * @param auctionId Auction identifier
     * @dev Bid amount is msg.value
     */
    function placeBid(uint256 auctionId) external payable whenNotPaused nonReentrant {
        Auction storage auction = auctions[auctionId];

        _validateAuctionExists(auctionId);
        if (!auction.active) {
            revert AuctionNotActive(auctionId);
        }

        if (auction.reservePrice > 0 && msg.value < auction.reservePrice) {
            revert BidBelowReserve(msg.value, auction.reservePrice);
        }

        AuctionLogic.validateBid(
            msg.sender,
            auction.seller,
            msg.value,
            auction.highestBid,
            auction.bidIncrementBps,
            auction.startTime,
            auction.endTime
        );

        // Store previous bidder for refund
        address previousBidder = auction.highestBidder;
        uint256 previousBid = auction.highestBid;

        // Update auction with new highest bid
        auction.highestBid = uint96(msg.value);
        auction.highestBidder = msg.sender;

        uint256 newEndTime = AuctionLogic.calculateExtendedEndTime(auction.endTime, block.timestamp);

        if (newEndTime != auction.endTime) {
            auction.endTime = uint32(newEndTime);
        }

        // Refund previous bidder
        if (previousBidder != address(0) && previousBid > 0) {
            // Try to refund immediately, but queue if it fails
            (bool success,) = previousBidder.call{value: previousBid, gas: 10_000}("");

            if (success) {
                emit BidRefunded(auctionId, previousBidder, previousBid);
            } else {
                pendingWithdrawals[previousBidder] += previousBid;
                emit BidRefundQueued(auctionId, previousBidder, previousBid);
            }
        }

        if (!bidderAuctionTracked[msg.sender][auctionId]) {
            bidderAuctions[msg.sender].push(auctionId);
            bidderAuctionTracked[msg.sender][auctionId] = true;
        }

        emit BidPlaced(auctionId, msg.sender, msg.value, newEndTime);
    }

    /**
     * @notice End auction and settle (transfer NFT, distribute payment)
     * @param auctionId Auction identifier
     */
    function endAuction(uint256 auctionId) external whenNotPaused nonReentrant {
        Auction storage auction = auctions[auctionId];

        _validateAuctionExists(auctionId);
        if (!auction.active) {
            revert AuctionNotActive(auctionId);
        }
        if (auction.settled) {
            revert AuctionAlreadySettled(auctionId);
        }

        AuctionLogic.validateCanEnd(auctionId, auction.endTime);

        auction.active = false;
        auction.settled = true;

        if (!AuctionLogic.hasBids(auction.highestBid, auction.highestBidder)) {
            // No bids - auction failed, return NFT to seller
            if (AssetTypes.isNFTType(auction.assetType)) {
                NFTOperations.transferNFT(
                    auction.nftContract,
                    address(this),
                    auction.seller,
                    auction.tokenId,
                    auction.quantity,
                    auction.standard
                );
            }
            emit AuctionCancelled(auctionId, auction.seller, "No bids received");
            return;
        }

        if (!AuctionLogic.isReserveMet(auction.highestBid, auction.reservePrice)) {
            // Reserve not met - refund bidder, return NFT to seller
            if (AssetTypes.isNFTType(auction.assetType)) {
                NFTOperations.transferNFT(
                    auction.nftContract,
                    address(this),
                    auction.seller,
                    auction.tokenId,
                    auction.quantity,
                    auction.standard
                );
            }
            PaymentUtils.safeTransferETH(auction.highestBidder, auction.highestBid);

            emit AuctionFailedReserveNotMet(auctionId, auction.highestBid, auction.reservePrice);
            emit BidRefunded(auctionId, auction.highestBidder, auction.highestBid);
            return;
        }

        if (AssetTypes.isNFTType(auction.assetType)) {
            _handleNFTAuctionEnd(auctionId, auction);
        } else {
            _handleOffChainAuctionEnd(auctionId, auction);
        }
    }

    /**
     * @notice Cancel auction (only if no bids)
     * @param auctionId Auction identifier
     * @dev Only seller can cancel, only before first bid
     */
    function cancelAuction(uint256 auctionId) external nonReentrant {
        Auction storage auction = auctions[auctionId];

        _validateAuctionExists(auctionId);
        if (msg.sender != auction.seller) {
            revert UnauthorizedSeller(msg.sender, auction.seller);
        }
        if (!auction.active) {
            revert AuctionNotActive(auctionId);
        }

        if (!AuctionLogic.canCancel(auction.highestBid)) {
            revert CannotCancelWithBids(auctionId);
        }

        auction.active = false;
        auction.settled = true;

        if (AssetTypes.isNFTType(auction.assetType)) {
            NFTOperations.transferNFT(
                auction.nftContract, address(this), auction.seller, auction.tokenId, auction.quantity, auction.standard
            );
        }

        emit AuctionCancelled(auctionId, msg.sender, "Cancelled by seller");
    }

    /**
     * @notice Emergency withdrawal if auction ended but not settled
     * @param auctionId Auction identifier
     * @dev Allows recovery after extended period
     */
    function emergencyWithdraw(uint256 auctionId) external nonReentrant {
        Auction storage auction = auctions[auctionId];

        _validateAuctionExists(auctionId);

        uint256 availableAfter = auction.endTime + EMERGENCY_WITHDRAWAL_DELAY;
        if (block.timestamp < availableAfter) {
            revert EmergencyWithdrawalTooEarly(auctionId, block.timestamp, availableAfter);
        }

        if (auction.settled) {
            revert EmergencyWithdrawalAlreadySettled(auctionId);
        }

        if (msg.sender != auction.seller && msg.sender != auction.highestBidder) {
            revert EmergencyWithdrawalNotAuthorized(msg.sender, auction.seller, auction.highestBidder);
        }

        auction.settled = true;

        if (auction.highestBidder != address(0) && auction.highestBid > 0) {
            PaymentUtils.safeTransferETH(auction.highestBidder, auction.highestBid);
            emit BidRefunded(auctionId, auction.highestBidder, auction.highestBid);
        }

        if (AssetTypes.isNFTType(auction.assetType)) {
            NFTOperations.transferNFT(
                auction.nftContract, address(this), auction.seller, auction.tokenId, auction.quantity, auction.standard
            );
        }

        emit AuctionCancelled(auctionId, auction.seller, "Emergency withdrawal");
    }

    /**
     * @notice Withdraw pending refunds (pull-over-push pattern)
     * @dev Allows users to withdraw funds that couldn't be automatically refunded
     */
    function withdraw() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NoPendingWithdrawal();

        pendingWithdrawals[msg.sender] = 0;

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) {
            pendingWithdrawals[msg.sender] = amount;
            revert WithdrawalFailed(msg.sender, amount);
        }

        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Update platform fee (FEE_MANAGER_ROLE only)
     * @param newFeeBps New fee in basis points
     */
    function updatePlatformFee(uint256 newFeeBps) external onlyFeeManager {
        PercentageMath.validateBps(newFeeBps, AssetTypes.MAX_FEE_BPS);
        platformFeeBps = newFeeBps;
    }

    // ============================================
    //         INTERNAL FUNCTIONS
    // ============================================

    function _calculateAndDistributePayment(
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        address seller
    )
        internal
        returns (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet, address royaltyReceiver)
    {
        platformFee = amount.percentOf(platformFeeBps);

        (royaltyReceiver, royaltyFee) = NFTOperations.getRoyaltyInfo(nftContract, tokenId, amount);

        sellerNet = amount - platformFee - royaltyFee;

        PaymentUtils.safeTransferETH(address(feeDistributor), platformFee);

        if (royaltyFee > 0 && royaltyReceiver != address(0)) {
            PaymentUtils.safeTransferETH(royaltyReceiver, royaltyFee);
        }

        PaymentUtils.safeTransferETH(seller, sellerNet);

        return (platformFee, royaltyFee, sellerNet, royaltyReceiver);
    }

    /**
     * @notice Handle NFT auction end (instant transfer + payment)
     * @param auctionId Auction identifier
     * @param auction Auction data
     */
    function _handleNFTAuctionEnd(uint256 auctionId, Auction memory auction) internal {
        NFTOperations.transferNFT(
            auction.nftContract,
            address(this),
            auction.highestBidder,
            auction.tokenId,
            auction.quantity,
            auction.standard
        );

        (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet, address royaltyReceiver) =
            _calculateAndDistributePayment(auction.nftContract, auction.tokenId, auction.highestBid, auction.seller);

        emit AuctionEnded(
            auctionId,
            auction.highestBidder,
            auction.seller,
            auction.highestBid,
            platformFee,
            royaltyFee,
            sellerNet,
            royaltyReceiver
        );
    }

    /**
     * @notice Handle off-chain asset auction end (create escrow)
     * @param auctionId Auction identifier
     * @param auction Auction data
     */
    function _handleOffChainAuctionEnd(uint256 auctionId, Auction memory auction) internal {
        uint256 escrowDuration = AssetTypes.recommendedEscrowDuration(auction.assetType);

        // Create escrow with winner as buyer, seller remains seller
        // Winner's funds (highest bid) are transferred to escrow
        escrowManager.createEscrow{value: auction.highestBid}(
            auction.highestBidder, // Explicit buyer (auction winner)
            auction.seller,
            auction.assetType,
            escrowDuration,
            auction.assetHash,
            auction.metadataURI
        );

        emit AuctionEnded(
            auctionId,
            auction.highestBidder,
            auction.seller,
            auction.highestBid,
            0, // platformFee - handled in escrow
            0, // royaltyFee - N/A for off-chain
            0, // sellerNet - handled in escrow
            address(0)
        );
    }

    /**
     * @notice Validate auction exists
     */
    function _validateAuctionExists(uint256 auctionId) internal view {
        if (auctionId == 0 || auctionId > auctionCounter) {
            revert InvalidAuctionId(auctionId);
        }
    }

    // ============================================
    //        VIEW FUNCTIONS
    // ============================================

    function getAuction(uint256 auctionId) external view returns (Auction memory) {
        _validateAuctionExists(auctionId);
        return auctions[auctionId];
    }

    function getMinimumBid(uint256 auctionId) external view returns (uint256) {
        _validateAuctionExists(auctionId);
        Auction memory auction = auctions[auctionId];

        if (auction.highestBid == 0) {
            return auction.reservePrice;
        }

        return AuctionLogic.calculateMinimumBid(auction.highestBid, auction.bidIncrementBps);
    }

    function isAuctionActive(uint256 auctionId) external view returns (bool) {
        if (auctionId == 0 || auctionId > auctionCounter) return false;

        Auction memory auction = auctions[auctionId];
        return auction.active && AuctionLogic.isActive(auction.startTime, auction.endTime);
    }

    function hasAuctionEnded(uint256 auctionId) external view returns (bool) {
        if (auctionId == 0 || auctionId > auctionCounter) return false;

        Auction memory auction = auctions[auctionId];
        return AuctionLogic.hasEnded(auction.endTime);
    }

    function getSellerAuctions(address seller) external view returns (uint256[] memory) {
        return sellerAuctions[seller];
    }

    function getBidderAuctions(address bidder) external view returns (uint256[] memory) {
        return bidderAuctions[bidder];
    }

    /**
     * @notice Verify off-chain asset details match stored hash
     * @param auctionId Auction identifier
     * @param assetDetails String representation of asset details to verify
     * @return isValid True if hash matches
     * @return expectedHash Stored hash in auction
     * @return actualHash Computed hash from provided details
     * @dev Useful for buyers to verify asset authenticity before/after auction
     */
    function verifyAssetHash(
        uint256 auctionId,
        string calldata assetDetails
    )
        external
        view
        returns (bool isValid, bytes32 expectedHash, bytes32 actualHash)
    {
        _validateAuctionExists(auctionId);
        Auction memory auction = auctions[auctionId];

        expectedHash = auction.assetHash;
        actualHash = keccak256(abi.encodePacked(assetDetails));
        isValid = (expectedHash == actualHash);
    }

    function calculatePaymentDistribution(uint256 auctionId)
        external
        view
        returns (uint256 platformFee, uint256 royaltyFee, uint256 sellerNet, address royaltyReceiver)
    {
        _validateAuctionExists(auctionId);
        Auction memory auction = auctions[auctionId];

        uint256 amount = auction.highestBid;
        platformFee = amount.percentOf(platformFeeBps);

        (royaltyReceiver, royaltyFee) = NFTOperations.getRoyaltyInfo(auction.nftContract, auction.tokenId, amount);

        sellerNet = amount - platformFee - royaltyFee;

        return (platformFee, royaltyFee, sellerNet, royaltyReceiver);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    )
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    )
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId;
    }
}

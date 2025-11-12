// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721URIStorageUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {ERC721BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import {ERC2981Upgradeable} from "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AssetTypes} from "../libraries/AssetTypes.sol";
import {PercentageMath} from "../libraries/PercentageMath.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title VertixNFT721
 * @notice ERC-721 collection template with royalties and batch minting
 * @dev Used by NFTFactory to deploy user collections via minimal proxy pattern
 *
 * Features:
 * - ERC-721 standard compliance
 * - ERC-2981 royalty support (up to 10%)
 * - Batch minting (gas efficient)
 * - URI storage per token
 * - Burnable tokens
 * - Pausable transfers
 * - Max supply enforcement
 * - Creator ownership
 */
contract VertixNFT721 is
    Initializable,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    ERC721BurnableUpgradeable,
    ERC2981Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    using PercentageMath for uint256;

    // ============================================
    //           ERRORS
    // ============================================

    error MaxSupplyReached();
    error InvalidRoyalty(uint256 bps);
    error InvalidMaxSupply(uint256 supply);
    error ExceedsMaxSupply(uint256 requested, uint256 available);
    error EmptyBatch();
    error BatchSizeTooLarge(uint256 provided, uint256 maximum);

    // ============================================
    //          STATE VARIABLES
    // ============================================

    /// @notice Current token ID counter
    uint256 private _tokenIdCounter;

    /// @notice Maximum supply (0 = unlimited)
    uint256 public maxSupply;

    /// @notice Total minted count
    uint256 public totalMinted;

    /// @notice Base URI for token metadata
    string private _baseTokenURI;

    /// @notice Collection creator
    address public creator;

    /// @notice Maximum batch mint size to prevent gas limit issues
    uint256 public constant MAX_BATCH_MINT_SIZE = 100;

    /**
     * @dev Gap for future storage variables to prevent storage collisions
     * This allows adding new state variables in future upgrades without breaking storage layout
     * 50 slots reserved (current usage: 5 slots above)
     */
    uint256[44] private __gap;

    // ============================================
    //             EVENTS
    // ============================================

    event BatchMinted(address indexed to, uint256 startTokenId, uint256 quantity);
    event RoyaltyUpdated(address indexed receiver, uint96 feeBps);
    event MaxSupplyUpdated(uint256 newMaxSupply);
    event BaseURIUpdated(string newBaseURI);

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize NFT collection (called by factory after cloning)
     * @param name_ Collection name
     * @param symbol_ Collection symbol
     * @param creator_ Collection creator address
     * @param royaltyReceiver_ Address to receive royalties
     * @param royaltyFeeBps_ Royalty fee in basis points (max 1000 = 10%)
     * @param maxSupply_ Maximum supply (0 = unlimited)
     * @param baseURI_ Base URI for token metadata
     * @dev Can only be called once per clone due to initializer modifier
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        address creator_,
        address royaltyReceiver_,
        uint96 royaltyFeeBps_,
        uint256 maxSupply_,
        string memory baseURI_
    )
        external
        initializer
    {
        // Validate creator
        if (creator_ == address(0)) revert Errors.InvalidCreator();

        // Initialize parent contracts
        __ERC721_init(name_, symbol_);
        __ERC721URIStorage_init();
        __ERC721Burnable_init();
        __ERC2981_init();
        __Ownable_init(creator_);
        __Pausable_init();

        // Validate and set royalty
        if (royaltyFeeBps_ > AssetTypes.MAX_ROYALTY_BPS) {
            revert InvalidRoyalty(royaltyFeeBps_);
        }

        if (royaltyFeeBps_ > 0) {
            if (royaltyReceiver_ == address(0)) {
                revert Errors.InvalidRoyaltyReceiver();
            }
            _setDefaultRoyalty(royaltyReceiver_, royaltyFeeBps_);
        }

        // Set state variables
        creator = creator_;
        maxSupply = maxSupply_;
        _baseTokenURI = baseURI_;
    }

    // ============================================
    //         EXTERNAL FUNCTIONS
    // ============================================

    /**
     * @notice Mint a single NFT
     * @param to Recipient address
     * @param uri Token URI
     * @return tokenId Minted token ID
     */
    function mint(address to, string memory uri) external onlyOwner whenNotPaused returns (uint256 tokenId) {
        // Check max supply
        if (maxSupply > 0 && totalMinted >= maxSupply) {
            revert MaxSupplyReached();
        }

        tokenId = ++_tokenIdCounter;
        ++totalMinted;

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);

        return tokenId;
    }

    /**
     * @notice Batch mint multiple NFTs
     * @param to Recipient address
     * @param uris Array of token URIs
     * @return startTokenId First token ID in batch
     */
    function batchMint(
        address to,
        string[] memory uris
    )
        external
        onlyOwner
        whenNotPaused
        returns (uint256 startTokenId)
    {
        uint256 quantity = uris.length;
        if (quantity == 0) revert EmptyBatch();
        if (quantity > MAX_BATCH_MINT_SIZE) {
            revert BatchSizeTooLarge(quantity, MAX_BATCH_MINT_SIZE);
        }

        // Check max supply
        if (maxSupply > 0) {
            uint256 available = maxSupply - totalMinted;
            if (quantity > available) {
                revert ExceedsMaxSupply(quantity, available);
            }
        }

        startTokenId = _tokenIdCounter;

        for (uint256 i = 0; i < quantity; ++i) {
            uint256 tokenId = ++_tokenIdCounter;
            _safeMint(to, tokenId);
            _setTokenURI(tokenId, uris[i]);
        }

        totalMinted += quantity;

        emit BatchMinted(to, startTokenId, quantity);

        return startTokenId;
    }

    /**
     * @notice Set default royalty for all tokens
     * @param receiver Royalty receiver address
     * @param feeBps Fee in basis points (max 1000 = 10%)
     */
    function setDefaultRoyalty(address receiver, uint96 feeBps) external onlyOwner {
        if (feeBps > AssetTypes.MAX_ROYALTY_BPS) {
            revert InvalidRoyalty(feeBps);
        }

        _setDefaultRoyalty(receiver, feeBps);

        emit RoyaltyUpdated(receiver, feeBps);
    }

    /**
     * @notice Set royalty for specific token
     * @param tokenId Token ID
     * @param receiver Royalty receiver address
     * @param feeBps Fee in basis points
     */
    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeBps) external onlyOwner {
        if (feeBps > AssetTypes.MAX_ROYALTY_BPS) {
            revert InvalidRoyalty(feeBps);
        }

        _setTokenRoyalty(tokenId, receiver, feeBps);
    }

    /**
     * @notice Delete default royalty
     */
    function deleteDefaultRoyalty() external onlyOwner {
        _deleteDefaultRoyalty();
    }

    /**
     * @notice Reset royalty for specific token to default
     * @param tokenId Token ID
     */
    function resetTokenRoyalty(uint256 tokenId) external onlyOwner {
        _resetTokenRoyalty(tokenId);
    }

    /**
     * @notice Update max supply
     * @param newMaxSupply New maximum supply (must be >= total minted)
     */
    function setMaxSupply(uint256 newMaxSupply) external onlyOwner {
        if (newMaxSupply < totalMinted) {
            revert InvalidMaxSupply(newMaxSupply);
        }

        maxSupply = newMaxSupply;

        emit MaxSupplyUpdated(newMaxSupply);
    }

    /**
     * @notice Update base URI
     * @param newBaseURI New base URI
     */
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
    }

    /**
     * @notice Pause all token transfers
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause token transfers
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function _update(address to, uint256 tokenId, address auth) internal override whenNotPaused returns (address) {
        return super._update(to, tokenId, auth);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

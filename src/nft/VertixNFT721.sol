// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../libraries/AssetTypes.sol";
import "../libraries/PercentageMath.sol";

/**
 * @title VertixNFT721
 * @notice ERC-721 collection template with royalties and batch minting
 * @dev Used by NFTFactory to deploy user collections
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
    ERC721,
    ERC721URIStorage,
    ERC721Burnable,
    ERC2981,
    Ownable,
    Pausable
{
    using PercentageMath for uint256;

    // ============================================
    // STATE VARIABLES
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

    // ============================================
    // EVENTS
    // ============================================

    event BatchMinted(
        address indexed to,
        uint256 startTokenId,
        uint256 quantity
    );
    event RoyaltyUpdated(address indexed receiver, uint96 feeBps);
    event MaxSupplyUpdated(uint256 newMaxSupply);
    event BaseURIUpdated(string newBaseURI);

    // ============================================
    // ERRORS
    // ============================================

    error MaxSupplyReached();
    error InvalidRoyalty(uint256 bps);
    error InvalidMaxSupply(uint256 supply);
    error ExceedsMaxSupply(uint256 requested, uint256 available);
    error EmptyBatch();

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /**
     * @notice Initialize NFT collection
     * @param name_ Collection name
     * @param symbol_ Collection symbol
     * @param creator_ Collection creator address
     * @param royaltyReceiver_ Address to receive royalties
     * @param royaltyFeeBps_ Royalty fee in basis points (max 1000 = 10%)
     * @param maxSupply_ Maximum supply (0 = unlimited)
     * @param baseURI_ Base URI for token metadata
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address creator_,
        address royaltyReceiver_,
        uint96 royaltyFeeBps_,
        uint256 maxSupply_,
        string memory baseURI_
    ) ERC721(name_, symbol_) Ownable(creator_) {
        require(creator_ != address(0), "Invalid creator");

        // Validate and set royalty
        if (royaltyFeeBps_ > AssetTypes.MAX_ROYALTY_BPS) {
            revert InvalidRoyalty(royaltyFeeBps_);
        }

        if (royaltyFeeBps_ > 0) {
            require(royaltyReceiver_ != address(0), "Invalid royalty receiver");
            _setDefaultRoyalty(royaltyReceiver_, royaltyFeeBps_);
        }

        creator = creator_;
        maxSupply = maxSupply_;
        _baseTokenURI = baseURI_;
    }

    // ============================================
    // MINTING FUNCTIONS
    // ============================================

    /**
     * @notice Mint a single NFT
     * @param to Recipient address
     * @param uri Token URI
     * @return tokenId Minted token ID
     */
    function mint(
        address to,
        string memory uri
    ) external onlyOwner whenNotPaused returns (uint256 tokenId) {
        // Check max supply
        if (maxSupply > 0 && totalMinted >= maxSupply) {
            revert MaxSupplyReached();
        }

        tokenId = _tokenIdCounter++;
        totalMinted++;

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
    ) external onlyOwner whenNotPaused returns (uint256 startTokenId) {
        uint256 quantity = uris.length;
        if (quantity == 0) revert EmptyBatch();

        // Check max supply
        if (maxSupply > 0) {
            uint256 available = maxSupply - totalMinted;
            if (quantity > available) {
                revert ExceedsMaxSupply(quantity, available);
            }
        }

        startTokenId = _tokenIdCounter;

        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _tokenIdCounter++;
            _safeMint(to, tokenId);
            _setTokenURI(tokenId, uris[i]);
        }

        totalMinted += quantity;

        emit BatchMinted(to, startTokenId, quantity);

        return startTokenId;
    }

    /**
     * @notice Batch mint with same URI (cheaper)
     * @param to Recipient address
     * @param quantity Number of tokens to mint
     * @param baseUri Base URI (will append tokenId)
     * @return startTokenId First token ID in batch
     */
    function batchMintSameURI(
        address to,
        uint256 quantity,
        string memory baseUri
    ) external onlyOwner whenNotPaused returns (uint256 startTokenId) {
        if (quantity == 0) revert EmptyBatch();

        // Check max supply
        if (maxSupply > 0) {
            uint256 available = maxSupply - totalMinted;
            if (quantity > available) {
                revert ExceedsMaxSupply(quantity, available);
            }
        }

        startTokenId = _tokenIdCounter;

        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _tokenIdCounter++;
            _safeMint(to, tokenId);
            // Note: Using base URI, frontend can construct full URI
        }

        totalMinted += quantity;

        emit BatchMinted(to, startTokenId, quantity);

        return startTokenId;
    }

    // ============================================
    // ROYALTY FUNCTIONS
    // ============================================

    /**
     * @notice Set default royalty for all tokens
     * @param receiver Royalty receiver address
     * @param feeBps Fee in basis points (max 1000 = 10%)
     */
    function setDefaultRoyalty(
        address receiver,
        uint96 feeBps
    ) external onlyOwner {
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
    function setTokenRoyalty(
        uint256 tokenId,
        address receiver,
        uint96 feeBps
    ) external onlyOwner {
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

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

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

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get next token ID to be minted
     */
    function nextTokenId() external view returns (uint256) {
        return _tokenIdCounter;
    }

    /**
     * @notice Check if max supply reached
     */
    function isMaxSupplyReached() external view returns (bool) {
        return maxSupply > 0 && totalMinted >= maxSupply;
    }

    /**
     * @notice Get remaining supply
     */
    function remainingSupply() external view returns (uint256) {
        if (maxSupply == 0) return type(uint256).max; // Unlimited
        return maxSupply - totalMinted;
    }

    // ============================================
    // OVERRIDES
    // ============================================

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override whenNotPaused returns (address) {
        return super._update(to, tokenId, auth);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721URIStorage, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

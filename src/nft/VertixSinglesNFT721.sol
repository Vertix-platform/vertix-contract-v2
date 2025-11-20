// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721URIStorageUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {ERC721BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title VertixSinglesNFT721
 * @notice Shared ERC-721 collection for users who want to mint single NFTs without creating a collection
 */
contract VertixSinglesNFT721 is
    Initializable,
    ERC721Upgradeable,
    ERC721URIStorageUpgradeable,
    ERC721BurnableUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    uint256 private _tokenIdCounter;
    uint256 public totalMinted;

    /// Mapping from token ID to minter (original creator)
    mapping(uint256 => address) public tokenMinter;

    uint256[47] private __gap;

    event SingleNFTMinted(address indexed minter, uint256 indexed tokenId, string uri);

    function initialize(string memory name_, string memory symbol_, address owner_) external initializer {
        if (owner_ == address(0)) revert Errors.ZeroAddress();

        __ERC721_init(name_, symbol_);
        __ERC721URIStorage_init();
        __ERC721Burnable_init();
        __Ownable_init(owner_);
        __Pausable_init();
    }

    /**
     * @notice Mint a single NFT to the shared collection
     * @param uri Token metadata URI (e.g., "ipfs://...")
     * @return tokenId Minted token ID
     */
    function mintPublic(string memory uri) external whenNotPaused returns (uint256 tokenId) {
        tokenId = ++_tokenIdCounter;
        ++totalMinted;

        tokenMinter[tokenId] = msg.sender;

        _mint(msg.sender, tokenId); // Use _mint instead of _safeMint for helper contract compatibility
        _setTokenURI(tokenId, uri);

        emit SingleNFTMinted(msg.sender, tokenId, uri);

        return tokenId;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ============================================
    //         VIEW FUNCTIONS
    // ============================================

    function getMinter(uint256 tokenId) external view returns (address) {
        return tokenMinter[tokenId];
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721URIStorageUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

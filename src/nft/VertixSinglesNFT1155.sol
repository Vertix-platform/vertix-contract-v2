// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import {ERC1155SupplyUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title VertixSinglesNFT1155
 * @notice Shared ERC-1155 collection for users who want to mint NFT editions without creating a collection
 */
contract VertixSinglesNFT1155 is
    Initializable,
    ERC1155Upgradeable,
    ERC1155BurnableUpgradeable,
    ERC1155SupplyUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    string public name;
    string public symbol;
    uint256 private _tokenIdCounter;
    uint256 public totalTokens;

    ///Mapping from token ID to token URI
    mapping(uint256 => string) private _tokenURIs;

    ///Mapping from token ID to minter (original creator)
    mapping(uint256 => address) public tokenMinter;

    /// Mapping from token ID to max supply (0 = unlimited)
    mapping(uint256 => uint256) public tokenMaxSupply;

    uint256[44] private __gap;

    event SingleEditionMinted(
        address indexed minter, uint256 indexed tokenId, uint256 amount, uint256 maxSupply, string uri
    );

    function initialize(
        string memory name_,
        string memory symbol_,
        string memory uri_,
        address owner_
    )
        external
        initializer
    {
        if (owner_ == address(0)) revert Errors.ZeroAddress();

        __ERC1155_init(uri_);
        __ERC1155Burnable_init();
        __ERC1155Supply_init();
        __Ownable_init(owner_);
        __Pausable_init();

        name = name_;
        symbol = symbol_;
    }

    /**
     * @notice Mint a new token with multiple editions to the shared collection (PUBLIC)
     * @param amount Number of editions to mint
     * @param maxSupply Maximum supply for this token (0 = unlimited)
     * @param tokenURI Token metadata URI
     * @param data Additional data
     * @return tokenId Minted token ID
     */
    function mintPublic(
        uint256 amount,
        uint256 maxSupply,
        string memory tokenURI,
        bytes memory data
    )
        external
        whenNotPaused
        returns (uint256 tokenId)
    {
        if (amount == 0) revert Errors.InvalidAmount();

        tokenId = ++_tokenIdCounter;
        ++totalTokens;

        tokenMinter[tokenId] = msg.sender;
        tokenMaxSupply[tokenId] = maxSupply;
        _tokenURIs[tokenId] = tokenURI;

        _mint(msg.sender, tokenId, amount, data);

        emit SingleEditionMinted(msg.sender, tokenId, amount, maxSupply, tokenURI);

        return tokenId;
    }

    /**
     * @notice Mint additional editions of an existing token
     * @param tokenId Token ID to mint more of
     * @param amount Number of additional editions
     * @param data Additional data
     */
    function mintMore(uint256 tokenId, uint256 amount, bytes memory data) external whenNotPaused {
        if (tokenMinter[tokenId] != msg.sender) {
            revert Errors.UnauthorizedCaller(msg.sender);
        }
        if (amount == 0) revert Errors.InvalidAmount();

        // Check max supply if set
        uint256 maxSupply = tokenMaxSupply[tokenId];
        if (maxSupply > 0) {
            uint256 currentSupply = totalSupply(tokenId);
            if (currentSupply + amount > maxSupply) {
                revert Errors.ExceedsMaxSupply();
            }
        }

        _mint(msg.sender, tokenId, amount, data);
    }

    /**
     * @notice Batch mint multiple new tokens with editions
     * @param amounts Array of edition counts
     * @param maxSupplies Array of max supplies
     * @param tokenURIs Array of token URIs
     * @param data Additional data
     * @return startTokenId First token ID in the batch
     */
    function batchMintPublic(
        uint256[] memory amounts,
        uint256[] memory maxSupplies,
        string[] memory tokenURIs,
        bytes memory data
    )
        external
        whenNotPaused
        returns (uint256 startTokenId)
    {
        uint256 quantity = amounts.length;
        if (quantity == 0) revert Errors.EmptyArray();
        if (quantity != maxSupplies.length || quantity != tokenURIs.length) {
            revert Errors.ArrayLengthMismatch();
        }
        if (quantity > 100) revert Errors.ArrayTooLarge(quantity, 100);

        startTokenId = _tokenIdCounter + 1;

        for (uint256 i = 0; i < quantity; ++i) {
            if (amounts[i] == 0) revert Errors.InvalidAmount();

            uint256 tokenId = ++_tokenIdCounter;
            ++totalTokens;

            tokenMinter[tokenId] = msg.sender;
            tokenMaxSupply[tokenId] = maxSupplies[i];
            _tokenURIs[tokenId] = tokenURIs[i];

            _mint(msg.sender, tokenId, amounts[i], data);

            emit SingleEditionMinted(msg.sender, tokenId, amounts[i], maxSupplies[i], tokenURIs[i]);
        }

        return startTokenId;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Update base URI
     * @param newuri New base URI
     */
    function setURI(string memory newuri) external onlyOwner {
        _setURI(newuri);
    }

    // ============================================
    //         VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get token URI
     * @param tokenId Token ID
     * @return Token metadata URI
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        return _tokenURIs[tokenId];
    }

    function getMinter(uint256 tokenId) external view returns (address) {
        return tokenMinter[tokenId];
    }

    function canMintMore(uint256 tokenId) external view returns (bool canMint, uint256 available) {
        uint256 maxSupply = tokenMaxSupply[tokenId];
        if (maxSupply == 0) {
            return (true, 0); // Unlimited
        }

        uint256 currentSupply = totalSupply(tokenId);
        if (currentSupply >= maxSupply) {
            return (false, 0);
        }

        return (true, maxSupply - currentSupply);
    }

    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    )
        internal
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
    {
        super._update(from, to, ids, values);
    }
}

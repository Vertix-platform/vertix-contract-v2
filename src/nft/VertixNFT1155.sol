// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import {ERC1155SupplyUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";
import {ERC2981Upgradeable} from "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AssetTypes} from "../libraries/AssetTypes.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title VertixNFT1155
 * @notice ERC-1155 multi-edition NFT template with royalties
 * @dev Used for gaming items, limited editions, fractional ownership
 */
contract VertixNFT1155 is
    Initializable,
    ERC1155Upgradeable,
    ERC1155BurnableUpgradeable,
    ERC1155SupplyUpgradeable,
    ERC2981Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    // ============================================
    //       STATE VARIABLES
    // ============================================

    string public name;
    string public symbol;
    uint256 private _tokenIdCounter;

    mapping(uint256 => string) public tokenURIs;
    mapping(uint256 => uint256) public tokenMaxSupply;

    /**
     * @dev Gap for future storage variables to prevent storage collisions
     * This allows adding new state variables in future upgrades without breaking storage layout
     * 50 slots reserved (current usage: 3 slots + 2 mappings above)
     */
    uint256[47] private __gap;

    // ============================================
    //         CONSTRUCTOR & INITIALIZER
    // ============================================

    /**
     * @notice Constructor for implementation contract (called once)
     * @dev Disables initializers to prevent implementation from being initialized
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize NFT collection (called by factory after cloning)
     * @dev Can only be called once per clone due to initializer modifier
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        string memory uri_,
        address creator_,
        address royaltyReceiver_,
        uint96 royaltyFeeBps_
    )
        external
        initializer
    {
        // Initialize parent contracts
        __ERC1155_init(uri_);
        __ERC1155Burnable_init();
        __ERC1155Supply_init();
        __ERC2981_init();
        __Ownable_init(creator_);
        __Pausable_init();

        // Set state variables
        name = name_;
        symbol = symbol_;

        if (royaltyFeeBps_ > 0) {
            _setDefaultRoyalty(royaltyReceiver_, royaltyFeeBps_);
        }
    }

    // ============================================
    //            MINTING
    // ============================================

    function create(
        uint256 initialSupply,
        string memory tokenURI,
        uint256 maxSupply_
    )
        external
        onlyOwner
        returns (uint256 tokenId)
    {
        tokenId = ++_tokenIdCounter;

        tokenURIs[tokenId] = tokenURI;
        tokenMaxSupply[tokenId] = maxSupply_;

        if (initialSupply > 0) {
            _mint(msg.sender, tokenId, initialSupply, "");
        }

        return tokenId;
    }

    function mint(address to, uint256 tokenId, uint256 amount) external onlyOwner whenNotPaused {
        if (tokenId >= _tokenIdCounter) {
            revert Errors.TokenDoesNotExist(tokenId);
        }

        uint256 maxSupply_ = tokenMaxSupply[tokenId];
        if (maxSupply_ > 0) {
            uint256 currentSupply = totalSupply(tokenId);
            if (currentSupply + amount > maxSupply_) {
                revert Errors.MaxSupplyReached(currentSupply, maxSupply_);
            }
        }

        _mint(to, tokenId, amount, "");
    }

    function mintBatch(
        address to,
        uint256[] memory tokenIds,
        uint256[] memory amounts
    )
        external
        onlyOwner
        whenNotPaused
    {
        _mintBatch(to, tokenIds, amounts, "");
    }

    function setURI(uint256 tokenId, string memory newuri) external onlyOwner {
        tokenURIs[tokenId] = newuri;
    }

    // ============================================
    //             ROYALTY
    // ============================================

    function setDefaultRoyalty(address receiver, uint96 feeBps) external onlyOwner {
        if (feeBps > AssetTypes.MAX_ROYALTY_BPS) {
            revert Errors.RoyaltyTooHigh(feeBps, AssetTypes.MAX_ROYALTY_BPS);
        }
        _setDefaultRoyalty(receiver, feeBps);
    }

    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeBps) external onlyOwner {
        if (feeBps > AssetTypes.MAX_ROYALTY_BPS) {
            revert Errors.RoyaltyTooHigh(feeBps, AssetTypes.MAX_ROYALTY_BPS);
        }
        _setTokenRoyalty(tokenId, receiver, feeBps);
    }

    // ============================================
    //              ADMIN
    // ============================================

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ============================================
    //             OVERRIDES
    // ============================================

    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    )
        internal
        override(ERC1155Upgradeable, ERC1155SupplyUpgradeable)
        whenNotPaused
    {
        super._update(from, to, ids, values);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155Upgradeable, ERC2981Upgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        return tokenURIs[tokenId];
    }
}

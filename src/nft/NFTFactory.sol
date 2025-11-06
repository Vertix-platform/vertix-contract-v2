// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {VertixNFT721} from "./VertixNFT721.sol";
import {VertixNFT1155} from "./VertixNFT1155.sol";
import {RoleManager} from "../access/RoleManager.sol";
import {AssetTypes} from "../libraries/AssetTypes.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title NFTFactory
 * @notice Factory for deploying NFT collections via minimal proxies (EIP-1167)
 * @dev 10x cheaper deployment using clone pattern
 *
 */
contract NFTFactory is ReentrancyGuard {
    using Clones for address;

    // ============================================
    //            STATE VARIABLES
    // ============================================

    /// @notice ERC-721 implementation contract
    address public immutable nft721Implementation;

    /// @notice ERC-1155 implementation contract
    address public immutable nft1155Implementation;

    /// @notice Role manager reference
    RoleManager public immutable roleManager;

    /// @notice Creation fee (optional)
    uint256 public creationFee;

    /// @notice All deployed collections
    address[] public allCollections;

    /// @notice Creator => their collections
    mapping(address => address[]) public creatorCollections;

    /// @notice Collection address => is Vertix collection
    mapping(address => bool) public isVertixCollection;

    // ============================================
    //                EVENTS
    // ============================================

    event Collection721Created(address indexed collection, address indexed creator, string name, string symbol);

    event Collection1155Created(address indexed collection, address indexed creator, string name, string symbol);

    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);

    // ============================================
    //           CONSTRUCTOR
    // ============================================

    constructor(address _roleManager) {
        if (_roleManager == address(0)) revert Errors.InvalidRoleManager();
        roleManager = RoleManager(_roleManager);

        // Deploy implementation contracts
        // Note: These will have _disableInitializers() called in their constructors
        // to prevent the implementation from being initialized
        nft721Implementation = address(new VertixNFT721());
        nft1155Implementation = address(new VertixNFT1155());
    }

    // ============================================
    //          COLLECTION CREATION
    // ============================================

    /**
     * @notice Create ERC-721 collection
     */
    function createCollection721(
        string memory name,
        string memory symbol,
        address royaltyReceiver,
        uint96 royaltyFeeBps,
        uint256 maxSupply,
        string memory baseURI
    )
        external
        payable
        nonReentrant
        returns (address collection)
    {
        if (msg.value < creationFee) {
            revert Errors.InsufficientPayment(msg.value, creationFee);
        }
        if (bytes(name).length == 0) revert Errors.EmptyString("name");
        if (bytes(symbol).length == 0) revert Errors.EmptyString("symbol");

        // Clone implementation
        collection = nft721Implementation.clone();

        // Initialize the clone with provided parameters
        VertixNFT721(collection).initialize(
            name,
            symbol,
            msg.sender, // creator
            royaltyReceiver,
            royaltyFeeBps,
            maxSupply,
            baseURI
        );

        // Track collection
        allCollections.push(collection);
        creatorCollections[msg.sender].push(collection);
        isVertixCollection[collection] = true;

        emit Collection721Created(collection, msg.sender, name, symbol);

        return collection;
    }

    /**
     * @notice Create ERC-1155 collection
     */
    function createCollection1155(
        string memory name,
        string memory symbol,
        string memory uri,
        address royaltyReceiver,
        uint96 royaltyFeeBps
    )
        external
        payable
        nonReentrant
        returns (address collection)
    {
        if (msg.value < creationFee) {
            revert Errors.InsufficientPayment(msg.value, creationFee);
        }
        if (bytes(name).length == 0) revert Errors.EmptyString("name");

        // Clone implementation
        collection = nft1155Implementation.clone();

        // Initialize the clone with provided parameters
        VertixNFT1155(collection).initialize(
            name,
            symbol,
            uri,
            msg.sender, // creator
            royaltyReceiver,
            royaltyFeeBps
        );

        // Track collection
        allCollections.push(collection);
        creatorCollections[msg.sender].push(collection);
        isVertixCollection[collection] = true;

        emit Collection1155Created(collection, msg.sender, name, symbol);

        return collection;
    }

    // ============================================
    //              ADMIN
    // ============================================

    function setCreationFee(uint256 newFee) external {
        if (!roleManager.hasRole(roleManager.FEE_MANAGER_ROLE(), msg.sender)) {
            revert Errors.NotFeeManager(msg.sender);
        }

        uint256 oldFee = creationFee;
        creationFee = newFee;

        emit CreationFeeUpdated(oldFee, newFee);
    }

    function withdrawFees() external {
        if (!roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender)) {
            revert Errors.NotAdmin(msg.sender);
        }

        uint256 balance = address(this).balance;
        if (balance == 0) revert Errors.NoFeesToWithdraw();

        (bool success,) = msg.sender.call{value: balance}("");
        if (!success) revert Errors.TransferFailed(msg.sender, balance);
    }
}

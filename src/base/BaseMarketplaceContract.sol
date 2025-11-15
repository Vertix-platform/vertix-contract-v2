// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {RoleManager} from "../access/RoleManager.sol";
import {Errors} from "../libraries/Errors.sol";

/**
 * @title BaseMarketplaceContract
 * @notice Abstract base contract for all marketplace contracts
 */
abstract contract BaseMarketplaceContract is ReentrancyGuard, Pausable {
    RoleManager public immutable roleManager;

    constructor(address _roleManager) {
        if (_roleManager == address(0)) revert Errors.InvalidRoleManager();
        roleManager = RoleManager(_roleManager);
    }

    modifier onlyAdmin() {
        if (!roleManager.hasRole(roleManager.ADMIN_ROLE(), msg.sender)) {
            revert Errors.NotAdmin(msg.sender);
        }
        _;
    }

    modifier onlyFeeManager() {
        if (!roleManager.hasRole(roleManager.FEE_MANAGER_ROLE(), msg.sender)) {
            revert Errors.NotFeeManager(msg.sender);
        }
        _;
    }

    modifier onlyPauser() {
        if (!roleManager.hasRole(roleManager.PAUSER_ROLE(), msg.sender)) {
            revert Errors.NotPauser(msg.sender);
        }
        _;
    }

    modifier onlyVerifier() {
        if (!roleManager.hasRole(roleManager.VERIFIER_ROLE(), msg.sender)) {
            revert Errors.NotVerifier(msg.sender);
        }
        _;
    }

    function pause() external onlyPauser {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title RoleManager
 * @notice Centralized role-based access control for Vertix marketplace
 * @dev Manages all privileged roles across the platform with hierarchical structure
 *
 * Role Hierarchy:
 * - DEFAULT_ADMIN_ROLE: Super admin (can grant/revoke all roles)
 * - ADMIN_ROLE: Platform administrators
 * - VERIFIER_ROLE: Can add verification proofs
 * - ARBITRATOR_ROLE: Can resolve disputes
 * - PAUSER_ROLE: Can pause contracts in emergency
 * - FEE_MANAGER_ROLE: Can update platform fees
 */
contract RoleManager is AccessControl, Pausable {
    // ============================================
    //                ERRORS
    // ============================================

    error TimelockNotExpired(uint256 currentTime, uint256 executeAfter);
    error NoScheduledGrant(bytes32 role, address account);
    error InvalidRole(bytes32 role);
    error CannotRevokeLastAdmin();
    error InvalidAddress(address account);
    error AlreadyHasRole(bytes32 role, address account);
    error LengthMismatch(uint256 rolesLength, uint256 accountsLength);

    // ============================================
    //             ROLES
    // ============================================

    /// @notice General admin role for day-to-day operations
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Can add verification proofs for off-chain assets
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    /// @notice Can resolve disputed escrows
    bytes32 public constant ARBITRATOR_ROLE = keccak256("ARBITRATOR_ROLE");

    /// @notice Can pause contracts in emergencies
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Can update platform fees and fee collector
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    // ============================================
    //           STATE VARIABLES
    // ============================================

    /// @notice Timelock duration for sensitive role changes (24 hours)
    uint256 public constant ROLE_CHANGE_TIMELOCK = 24 hours;

    /// @notice Track pending role grants with timelock
    mapping(bytes32 => mapping(address => uint256)) public pendingRoleGrants;

    /// @notice Track role grant history for audit trail
    mapping(bytes32 => address[]) private roleMembers;

    // ============================================
    //                 EVENTS
    // ============================================

    /**
     * @notice Emitted when a role grant is scheduled
     */
    event RoleGrantScheduled(
        bytes32 indexed role, address indexed account, address indexed scheduler, uint256 executeAfter
    );

    /**
     * @notice Emitted when a scheduled role grant is executed
     */
    event RoleGrantExecuted(bytes32 indexed role, address indexed account, address indexed executor);

    /**
     * @notice Emitted when a scheduled role grant is cancelled
     */
    event RoleGrantCancelled(bytes32 indexed role, address indexed account, address indexed canceller);

    /**
     * @notice Emitted when contract is paused
     */
    event EmergencyPaused(address indexed pauser, string reason);

    /**
     * @notice Emitted when contract is unpaused
     */
    event EmergencyUnpaused(address indexed unpauser);

    // ============================================
    //             CONSTRUCTOR
    // ============================================

    /**
     * @notice Initialize role manager
     * @param initialAdmin Address to receive DEFAULT_ADMIN_ROLE
     * @dev Grants all roles to initial admin for initial setup
     */
    constructor(address initialAdmin) {
        if (initialAdmin == address(0)) {
            revert InvalidAddress(initialAdmin);
        }

        // Grant super admin role
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);

        // Grant all other roles to initial admin for setup
        _grantRole(ADMIN_ROLE, initialAdmin);
        _grantRole(PAUSER_ROLE, initialAdmin);
        _grantRole(FEE_MANAGER_ROLE, initialAdmin);

        // Track members
        roleMembers[DEFAULT_ADMIN_ROLE].push(initialAdmin);
        roleMembers[ADMIN_ROLE].push(initialAdmin);
        roleMembers[PAUSER_ROLE].push(initialAdmin);
        roleMembers[FEE_MANAGER_ROLE].push(initialAdmin);
    }

    // ============================================
    //        ROLE MANAGEMENT WITH TIMELOCK
    // ============================================

    /**
     * @notice Schedule a role grant with timelock (for sensitive roles)
     * @param role Role identifier
     * @param account Address to receive role
     * @dev Requires DEFAULT_ADMIN_ROLE
     * @dev Timelock only applies to ADMIN_ROLE and DEFAULT_ADMIN_ROLE
     */
    function scheduleRoleGrant(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == address(0)) {
            revert InvalidAddress(account);
        }

        if (hasRole(role, account)) {
            revert AlreadyHasRole(role, account);
        }

        // Only sensitive roles require timelock
        bool requiresTimelock = (role == DEFAULT_ADMIN_ROLE || role == ADMIN_ROLE);

        if (requiresTimelock) {
            uint256 executeAfter = block.timestamp + ROLE_CHANGE_TIMELOCK;
            pendingRoleGrants[role][account] = executeAfter;

            emit RoleGrantScheduled(role, account, msg.sender, executeAfter);
        } else {
            // Non-sensitive roles can be granted immediately
            _grantRoleInternal(role, account);

            emit RoleGrantExecuted(role, account, msg.sender);
        }
    }

    /**
     * @notice Execute a scheduled role grant after timelock
     * @param role Role identifier
     * @param account Address to receive role
     */
    function executeRoleGrant(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 executeAfter = pendingRoleGrants[role][account];

        if (executeAfter == 0) {
            revert NoScheduledGrant(role, account);
        }

        if (block.timestamp < executeAfter) {
            revert TimelockNotExpired(block.timestamp, executeAfter);
        }

        // Clear pending grant
        delete pendingRoleGrants[role][account];

        // Grant role
        _grantRoleInternal(role, account);

        emit RoleGrantExecuted(role, account, msg.sender);
    }

    /**
     * @notice Cancel a scheduled role grant
     * @param role Role identifier
     * @param account Address
     */
    function cancelRoleGrant(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (pendingRoleGrants[role][account] == 0) {
            revert NoScheduledGrant(role, account);
        }

        delete pendingRoleGrants[role][account];

        emit RoleGrantCancelled(role, account, msg.sender);
    }

    /**
     * @notice Grant role immediately (for non-sensitive roles)
     * @param role Role identifier
     * @param account Address to receive role
     * @dev Internal function with member tracking
     */
    function _grantRoleInternal(bytes32 role, address account) internal {
        _grantRole(role, account);
        roleMembers[role].push(account);
    }

    /**
     * @notice Revoke a role from an account
     * @param role Role identifier
     * @param account Address to revoke from
     * @dev Prevents revoking last admin to avoid lockout
     */
    function revokeRoleWithCheck(bytes32 role, address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Prevent removing last admin
        if (role == DEFAULT_ADMIN_ROLE) {
            uint256 adminCount = getRoleMemberCount(DEFAULT_ADMIN_ROLE);
            if (adminCount <= 1) {
                revert CannotRevokeLastAdmin();
            }
        }

        _revokeRole(role, account);
        _removeFromRoleMembers(role, account);
    }

    /**
     * @notice Remove address from role members array
     */
    function _removeFromRoleMembers(bytes32 role, address account) internal {
        address[] storage members = roleMembers[role];
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i] == account) {
                members[i] = members[members.length - 1];
                members.pop();
                break;
            }
        }
    }

    // ============================================
    //        EMERGENCY CONTROLS
    // ============================================

    /**
     * @notice Pause all marketplace operations
     * @param reason Reason for pausing
     * @dev Can only be called by PAUSER_ROLE
     */
    function pause(string calldata reason) external onlyRole(PAUSER_ROLE) {
        _pause();
        emit EmergencyPaused(msg.sender, reason);
    }

    /**
     * @notice Unpause marketplace operations
     * @dev Requires ADMIN_ROLE (higher authority than pauser)
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
        emit EmergencyUnpaused(msg.sender);
    }

    // ============================================
    //         VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get all members of a role
     * @param role Role identifier
     * @return Array of addresses
     */
    function getRoleMembers(bytes32 role) external view returns (address[] memory) {
        return roleMembers[role];
    }

    /**
     * @notice Get count of role members
     * @param role Role identifier
     * @return Member count
     */
    function getRoleMemberCount(bytes32 role) public view returns (uint256) {
        return roleMembers[role].length;
    }

    /**
     * @notice Check if role grant is pending
     * @param role Role identifier
     * @param account Address
     * @return executeAfter Timestamp when grant can be executed (0 if not pending)
     */
    function getPendingRoleGrant(bytes32 role, address account) external view returns (uint256 executeAfter) {
        return pendingRoleGrants[role][account];
    }

    /**
     * @notice Check if role grant is ready to execute
     * @param role Role identifier
     * @param account Address
     * @return True if timelock expired and can be executed
     */
    function canExecuteRoleGrant(bytes32 role, address account) external view returns (bool) {
        uint256 executeAfter = pendingRoleGrants[role][account];
        return executeAfter > 0 && block.timestamp >= executeAfter;
    }

    /**
     * @notice Check if address has any admin role
     * @param account Address to check
     * @return True if has DEFAULT_ADMIN_ROLE or ADMIN_ROLE
     */
    function isAdmin(address account) external view returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, account) || hasRole(ADMIN_ROLE, account);
    }

    /**
     * @notice Check if marketplace is currently paused
     * @return True if paused
     */
    function isPaused() external view returns (bool) {
        return paused();
    }

    // ============================================
    //          UTILITY FUNCTIONS
    // ============================================

    /**
     * @notice Batch grant roles to multiple addresses
     * @param roles Array of role identifiers
     * @param accounts Array of addresses (must match roles length)
     * @dev For initial setup, skips timelock
     */
    function batchGrantRoles(bytes32[] calldata roles, address[] calldata accounts)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (roles.length != accounts.length) {
            revert LengthMismatch(roles.length, accounts.length);
        }

        for (uint256 i = 0; i < roles.length; i++) {
            if (!hasRole(roles[i], accounts[i])) {
                _grantRoleInternal(roles[i], accounts[i]);
            }
        }
    }

    /**
     * @notice Check if account has multiple roles
     * @param account Address to check
     * @param rolesToCheck Array of roles to check
     * @return hasAllRoles True if account has all specified roles
     */
    function hasAllRoles(address account, bytes32[] calldata rolesToCheck) external view returns (bool) {
        for (uint256 i = 0; i < rolesToCheck.length; i++) {
            if (!hasRole(rolesToCheck[i], account)) {
                return false;
            }
        }
        return true;
    }

    /**
     * @notice Check if account has any of the specified roles
     * @param account Address to check
     * @param rolesToCheck Array of roles to check
     * @return hasAnyRole True if account has at least one role
     */
    function hasAnyRole(address account, bytes32[] calldata rolesToCheck) external view returns (bool) {
        for (uint256 i = 0; i < rolesToCheck.length; i++) {
            if (hasRole(rolesToCheck[i], account)) {
                return true;
            }
        }
        return false;
    }
}

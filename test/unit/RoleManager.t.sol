// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RoleManager} from "../../src/access/RoleManager.sol";

contract RoleManagerTest is Test {
    RoleManager public roleManager;

    address public admin;
    address public user1;
    address public user2;
    address public user3;

    // Role constants
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant ARBITRATOR_ROLE = keccak256("ARBITRATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    // Events
    event RoleGrantScheduled(
        bytes32 indexed role, address indexed account, address indexed scheduler, uint256 executeAfter
    );
    event RoleGrantExecuted(bytes32 indexed role, address indexed account, address indexed executor);
    event RoleGrantCancelled(bytes32 indexed role, address indexed account, address indexed canceller);
    event EmergencyPaused(address indexed pauser, string reason);
    event EmergencyUnpaused(address indexed unpauser);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    // Errors
    error InvalidAddress(address account);
    error TimelockNotExpired(uint256 currentTime, uint256 executeAfter);
    error NoScheduledGrant(bytes32 role, address account);
    error CannotRevokeLastAdmin();
    error AlreadyHasRole(bytes32 role, address account);
    error LengthMismatch(uint256 rolesLength, uint256 accountsLength);

    function setUp() public {
        admin = makeAddr("admin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        roleManager = new RoleManager(admin);
    }

    // ============================================
    //          CONSTRUCTOR TESTS
    // ============================================

    function test_Constructor_GrantsInitialRoles() public view {
        assertTrue(roleManager.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(roleManager.hasRole(ADMIN_ROLE, admin));
        assertTrue(roleManager.hasRole(PAUSER_ROLE, admin));
        assertTrue(roleManager.hasRole(FEE_MANAGER_ROLE, admin));
    }

    function test_Constructor_TracksRoleMembers() public view {
        address[] memory defaultAdmins = roleManager.getRoleMembers(DEFAULT_ADMIN_ROLE);
        address[] memory admins = roleManager.getRoleMembers(ADMIN_ROLE);
        address[] memory pausers = roleManager.getRoleMembers(PAUSER_ROLE);
        address[] memory feeManagers = roleManager.getRoleMembers(FEE_MANAGER_ROLE);

        assertEq(defaultAdmins.length, 1);
        assertEq(defaultAdmins[0], admin);
        assertEq(admins.length, 1);
        assertEq(admins[0], admin);
        assertEq(pausers.length, 1);
        assertEq(pausers[0], admin);
        assertEq(feeManagers.length, 1);
        assertEq(feeManagers[0], admin);
    }

    function test_Constructor_RevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector, address(0)));
        new RoleManager(address(0));
    }

    // ============================================
    //       SCHEDULE ROLE GRANT TESTS
    // ============================================

    function test_ScheduleRoleGrant_AdminRole_CreatesTimelock() public {
        vm.startPrank(admin);

        uint256 expectedExecuteAfter = block.timestamp + roleManager.ROLE_CHANGE_TIMELOCK();

        vm.expectEmit(true, true, true, true);
        emit RoleGrantScheduled(ADMIN_ROLE, user1, admin, expectedExecuteAfter);

        roleManager.scheduleRoleGrant(ADMIN_ROLE, user1);

        uint256 actualExecuteAfter = roleManager.getPendingRoleGrant(ADMIN_ROLE, user1);
        assertEq(actualExecuteAfter, expectedExecuteAfter);

        vm.stopPrank();
    }

    function test_ScheduleRoleGrant_DefaultAdminRole_CreatesTimelock() public {
        vm.startPrank(admin);

        uint256 expectedExecuteAfter = block.timestamp + roleManager.ROLE_CHANGE_TIMELOCK();

        vm.expectEmit(true, true, true, true);
        emit RoleGrantScheduled(DEFAULT_ADMIN_ROLE, user1, admin, expectedExecuteAfter);

        roleManager.scheduleRoleGrant(DEFAULT_ADMIN_ROLE, user1);

        uint256 actualExecuteAfter = roleManager.getPendingRoleGrant(DEFAULT_ADMIN_ROLE, user1);
        assertEq(actualExecuteAfter, expectedExecuteAfter);

        vm.stopPrank();
    }

    function test_ScheduleRoleGrant_NonSensitiveRole_GrantsImmediately() public {
        vm.startPrank(admin);

        vm.expectEmit(true, true, true, true);
        emit RoleGrantExecuted(VERIFIER_ROLE, user1, admin);

        roleManager.scheduleRoleGrant(VERIFIER_ROLE, user1);

        assertTrue(roleManager.hasRole(VERIFIER_ROLE, user1));
        assertEq(roleManager.getPendingRoleGrant(VERIFIER_ROLE, user1), 0);

        vm.stopPrank();
    }

    function test_ScheduleRoleGrant_NonSensitiveRoles_AllGrantedImmediately() public {
        vm.startPrank(admin);

        // Test ARBITRATOR_ROLE
        roleManager.scheduleRoleGrant(ARBITRATOR_ROLE, user1);
        assertTrue(roleManager.hasRole(ARBITRATOR_ROLE, user1));

        // Test PAUSER_ROLE
        roleManager.scheduleRoleGrant(PAUSER_ROLE, user2);
        assertTrue(roleManager.hasRole(PAUSER_ROLE, user2));

        // Test FEE_MANAGER_ROLE
        roleManager.scheduleRoleGrant(FEE_MANAGER_ROLE, user3);
        assertTrue(roleManager.hasRole(FEE_MANAGER_ROLE, user3));

        vm.stopPrank();
    }

    function test_ScheduleRoleGrant_RevertsOnZeroAddress() public {
        vm.startPrank(admin);

        vm.expectRevert(abi.encodeWithSelector(InvalidAddress.selector, address(0)));
        roleManager.scheduleRoleGrant(ADMIN_ROLE, address(0));

        vm.stopPrank();
    }

    function test_ScheduleRoleGrant_RevertsIfAlreadyHasRole() public {
        vm.startPrank(admin);

        // Admin already has ADMIN_ROLE
        vm.expectRevert(abi.encodeWithSelector(AlreadyHasRole.selector, ADMIN_ROLE, admin));
        roleManager.scheduleRoleGrant(ADMIN_ROLE, admin);

        vm.stopPrank();
    }

    function test_ScheduleRoleGrant_RevertsIfNotDefaultAdmin() public {
        vm.startPrank(user1);

        vm.expectRevert();
        roleManager.scheduleRoleGrant(ADMIN_ROLE, user2);

        vm.stopPrank();
    }

    // ============================================
    //       EXECUTE ROLE GRANT TESTS
    // ============================================

    function test_ExecuteRoleGrant_SucceedsAfterTimelock() public {
        vm.startPrank(admin);

        // Schedule role grant
        roleManager.scheduleRoleGrant(ADMIN_ROLE, user1);

        // Fast forward past timelock
        vm.warp(block.timestamp + roleManager.ROLE_CHANGE_TIMELOCK() + 1);

        vm.expectEmit(true, true, true, true);
        emit RoleGrantExecuted(ADMIN_ROLE, user1, admin);

        roleManager.executeRoleGrant(ADMIN_ROLE, user1);

        assertTrue(roleManager.hasRole(ADMIN_ROLE, user1));
        assertEq(roleManager.getPendingRoleGrant(ADMIN_ROLE, user1), 0);

        vm.stopPrank();
    }

    function test_ExecuteRoleGrant_UpdatesRoleMembers() public {
        vm.startPrank(admin);

        // Schedule and execute
        roleManager.scheduleRoleGrant(ADMIN_ROLE, user1);
        vm.warp(block.timestamp + roleManager.ROLE_CHANGE_TIMELOCK() + 1);
        roleManager.executeRoleGrant(ADMIN_ROLE, user1);

        address[] memory admins = roleManager.getRoleMembers(ADMIN_ROLE);
        assertEq(admins.length, 2);
        assertTrue(admins[0] == admin || admins[1] == admin);
        assertTrue(admins[0] == user1 || admins[1] == user1);

        vm.stopPrank();
    }

    function test_ExecuteRoleGrant_RevertsIfNotScheduled() public {
        vm.startPrank(admin);

        vm.expectRevert(abi.encodeWithSelector(NoScheduledGrant.selector, ADMIN_ROLE, user1));
        roleManager.executeRoleGrant(ADMIN_ROLE, user1);

        vm.stopPrank();
    }

    function test_ExecuteRoleGrant_RevertsIfTimelockNotExpired() public {
        vm.startPrank(admin);

        // Schedule role grant
        roleManager.scheduleRoleGrant(ADMIN_ROLE, user1);

        uint256 executeAfter = roleManager.getPendingRoleGrant(ADMIN_ROLE, user1);

        // Try to execute before timelock expires
        vm.expectRevert(abi.encodeWithSelector(TimelockNotExpired.selector, block.timestamp, executeAfter));
        roleManager.executeRoleGrant(ADMIN_ROLE, user1);

        vm.stopPrank();
    }

    function test_ExecuteRoleGrant_RevertsIfNotDefaultAdmin() public {
        vm.startPrank(admin);
        roleManager.scheduleRoleGrant(ADMIN_ROLE, user1);
        vm.stopPrank();

        vm.warp(block.timestamp + roleManager.ROLE_CHANGE_TIMELOCK() + 1);

        vm.startPrank(user2);
        vm.expectRevert();
        roleManager.executeRoleGrant(ADMIN_ROLE, user1);
        vm.stopPrank();
    }

    // ============================================
    //       CANCEL ROLE GRANT TESTS
    // ============================================

    function test_CancelRoleGrant_RemovesPendingGrant() public {
        vm.startPrank(admin);

        // Schedule role grant
        roleManager.scheduleRoleGrant(ADMIN_ROLE, user1);

        vm.expectEmit(true, true, true, true);
        emit RoleGrantCancelled(ADMIN_ROLE, user1, admin);

        roleManager.cancelRoleGrant(ADMIN_ROLE, user1);

        assertEq(roleManager.getPendingRoleGrant(ADMIN_ROLE, user1), 0);
        assertFalse(roleManager.hasRole(ADMIN_ROLE, user1));

        vm.stopPrank();
    }

    function test_CancelRoleGrant_RevertsIfNotScheduled() public {
        vm.startPrank(admin);

        vm.expectRevert(abi.encodeWithSelector(NoScheduledGrant.selector, ADMIN_ROLE, user1));
        roleManager.cancelRoleGrant(ADMIN_ROLE, user1);

        vm.stopPrank();
    }

    function test_CancelRoleGrant_RevertsIfNotDefaultAdmin() public {
        vm.startPrank(admin);
        roleManager.scheduleRoleGrant(ADMIN_ROLE, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert();
        roleManager.cancelRoleGrant(ADMIN_ROLE, user1);
        vm.stopPrank();
    }

    // ============================================
    //          REVOKE ROLE TESTS
    // ============================================

    function test_RevokeRoleWithCheck_SucceedsForNonLastAdmin() public {
        vm.startPrank(admin);

        // Grant ADMIN_ROLE to user1
        roleManager.scheduleRoleGrant(ADMIN_ROLE, user1);
        vm.warp(block.timestamp + roleManager.ROLE_CHANGE_TIMELOCK() + 1);
        roleManager.executeRoleGrant(ADMIN_ROLE, user1);

        // Now revoke from original admin (not the last one)
        vm.expectEmit(true, true, true, true);
        emit RoleRevoked(ADMIN_ROLE, user1, admin);

        roleManager.revokeRoleWithCheck(ADMIN_ROLE, user1);

        assertFalse(roleManager.hasRole(ADMIN_ROLE, user1));

        vm.stopPrank();
    }

    function test_RevokeRoleWithCheck_UpdatesRoleMembers() public {
        vm.startPrank(admin);

        // Grant VERIFIER_ROLE to user1
        roleManager.scheduleRoleGrant(VERIFIER_ROLE, user1);

        assertEq(roleManager.getRoleMemberCount(VERIFIER_ROLE), 1);

        // Revoke the role
        roleManager.revokeRoleWithCheck(VERIFIER_ROLE, user1);

        assertEq(roleManager.getRoleMemberCount(VERIFIER_ROLE), 0);

        vm.stopPrank();
    }

    function test_RevokeRoleWithCheck_RevertsIfLastDefaultAdmin() public {
        vm.startPrank(admin);

        // Try to revoke DEFAULT_ADMIN_ROLE from the last admin
        vm.expectRevert(abi.encodeWithSelector(CannotRevokeLastAdmin.selector));
        roleManager.revokeRoleWithCheck(DEFAULT_ADMIN_ROLE, admin);

        vm.stopPrank();
    }

    function test_RevokeRoleWithCheck_AllowsRevokingLastDefaultAdminIfMultipleExist() public {
        vm.startPrank(admin);

        // Grant DEFAULT_ADMIN_ROLE to user1
        roleManager.scheduleRoleGrant(DEFAULT_ADMIN_ROLE, user1);
        vm.warp(block.timestamp + roleManager.ROLE_CHANGE_TIMELOCK() + 1);
        roleManager.executeRoleGrant(DEFAULT_ADMIN_ROLE, user1);

        // Now we can revoke from original admin
        roleManager.revokeRoleWithCheck(DEFAULT_ADMIN_ROLE, admin);

        assertFalse(roleManager.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(roleManager.hasRole(DEFAULT_ADMIN_ROLE, user1));

        vm.stopPrank();
    }

    function test_RevokeRoleWithCheck_RevertsIfNotDefaultAdmin() public {
        vm.startPrank(user1);

        vm.expectRevert();
        roleManager.revokeRoleWithCheck(VERIFIER_ROLE, admin);

        vm.stopPrank();
    }

    // ============================================
    //          PAUSE/UNPAUSE TESTS
    // ============================================

    function test_Pause_SucceedsWithPauserRole() public {
        vm.startPrank(admin);

        string memory reason = "Security incident detected";

        vm.expectEmit(true, false, false, true);
        emit EmergencyPaused(admin, reason);

        roleManager.pause(reason);

        assertTrue(roleManager.isPaused());

        vm.stopPrank();
    }

    function test_Pause_RevertsIfNotPauser() public {
        vm.startPrank(user1);

        vm.expectRevert();
        roleManager.pause("test");

        vm.stopPrank();
    }

    function test_Unpause_SucceedsWithAdminRole() public {
        vm.startPrank(admin);

        // First pause
        roleManager.pause("test");
        assertTrue(roleManager.isPaused());

        // Then unpause
        vm.expectEmit(true, false, false, false);
        emit EmergencyUnpaused(admin);

        roleManager.unpause();

        assertFalse(roleManager.isPaused());

        vm.stopPrank();
    }

    function test_Unpause_RevertsIfNotAdmin() public {
        vm.startPrank(admin);
        roleManager.pause("test");
        vm.stopPrank();

        vm.startPrank(user1);

        vm.expectRevert();
        roleManager.unpause();

        vm.stopPrank();
    }

    // ============================================
    //          BATCH GRANT ROLES TESTS
    // ============================================

    function test_BatchGrantRoles_SucceedsWithMultipleRoles() public {
        vm.startPrank(admin);

        bytes32[] memory roles = new bytes32[](3);
        roles[0] = VERIFIER_ROLE;
        roles[1] = ARBITRATOR_ROLE;
        roles[2] = FEE_MANAGER_ROLE;

        address[] memory accounts = new address[](3);
        accounts[0] = user1;
        accounts[1] = user2;
        accounts[2] = user3;

        roleManager.batchGrantRoles(roles, accounts);

        assertTrue(roleManager.hasRole(VERIFIER_ROLE, user1));
        assertTrue(roleManager.hasRole(ARBITRATOR_ROLE, user2));
        assertTrue(roleManager.hasRole(FEE_MANAGER_ROLE, user3));

        vm.stopPrank();
    }

    function test_BatchGrantRoles_SkipsIfAlreadyHasRole() public {
        vm.startPrank(admin);

        // Grant role first
        roleManager.scheduleRoleGrant(VERIFIER_ROLE, user1);

        bytes32[] memory roles = new bytes32[](2);
        roles[0] = VERIFIER_ROLE;
        roles[1] = ARBITRATOR_ROLE;

        address[] memory accounts = new address[](2);
        accounts[0] = user1;
        accounts[1] = user1;

        // Should not revert, just skip the already granted role
        roleManager.batchGrantRoles(roles, accounts);

        assertTrue(roleManager.hasRole(VERIFIER_ROLE, user1));
        assertTrue(roleManager.hasRole(ARBITRATOR_ROLE, user1));

        vm.stopPrank();
    }

    function test_BatchGrantRoles_RevertsOnLengthMismatch() public {
        vm.startPrank(admin);

        bytes32[] memory roles = new bytes32[](2);
        roles[0] = VERIFIER_ROLE;
        roles[1] = ARBITRATOR_ROLE;

        address[] memory accounts = new address[](3);
        accounts[0] = user1;
        accounts[1] = user2;
        accounts[2] = user3;

        vm.expectRevert(abi.encodeWithSelector(LengthMismatch.selector, 2, 3));
        roleManager.batchGrantRoles(roles, accounts);

        vm.stopPrank();
    }

    function test_BatchGrantRoles_RevertsIfNotDefaultAdmin() public {
        vm.startPrank(user1);

        bytes32[] memory roles = new bytes32[](1);
        roles[0] = VERIFIER_ROLE;

        address[] memory accounts = new address[](1);
        accounts[0] = user2;

        vm.expectRevert();
        roleManager.batchGrantRoles(roles, accounts);

        vm.stopPrank();
    }

    // ============================================
    //          VIEW FUNCTION TESTS
    // ============================================

    function test_GetRoleMembers_ReturnsCorrectMembers() public {
        vm.startPrank(admin);

        // Grant roles to multiple users
        roleManager.scheduleRoleGrant(VERIFIER_ROLE, user1);
        roleManager.scheduleRoleGrant(VERIFIER_ROLE, user2);

        address[] memory members = roleManager.getRoleMembers(VERIFIER_ROLE);

        assertEq(members.length, 2);
        assertTrue(members[0] == user1 || members[1] == user1);
        assertTrue(members[0] == user2 || members[1] == user2);

        vm.stopPrank();
    }

    function test_GetRoleMemberCount_ReturnsCorrectCount() public view {
        assertEq(roleManager.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
        assertEq(roleManager.getRoleMemberCount(ADMIN_ROLE), 1);
        assertEq(roleManager.getRoleMemberCount(VERIFIER_ROLE), 0);
    }

    function test_CanExecuteRoleGrant_ReturnsFalseWhenNotScheduled() public view {
        assertFalse(roleManager.canExecuteRoleGrant(ADMIN_ROLE, user1));
    }

    function test_CanExecuteRoleGrant_ReturnsFalseBeforeTimelock() public {
        vm.startPrank(admin);
        roleManager.scheduleRoleGrant(ADMIN_ROLE, user1);
        vm.stopPrank();

        assertFalse(roleManager.canExecuteRoleGrant(ADMIN_ROLE, user1));
    }

    function test_CanExecuteRoleGrant_ReturnsTrueAfterTimelock() public {
        vm.startPrank(admin);
        roleManager.scheduleRoleGrant(ADMIN_ROLE, user1);
        vm.stopPrank();

        vm.warp(block.timestamp + roleManager.ROLE_CHANGE_TIMELOCK() + 1);

        assertTrue(roleManager.canExecuteRoleGrant(ADMIN_ROLE, user1));
    }

    function test_IsAdmin_ReturnsTrueForDefaultAdmin() public view {
        assertTrue(roleManager.isAdmin(admin));
    }

    function test_IsAdmin_ReturnsTrueForAdminRole() public {
        vm.prank(admin);
        roleManager.scheduleRoleGrant(ADMIN_ROLE, user1);
        vm.warp(block.timestamp + roleManager.ROLE_CHANGE_TIMELOCK() + 1);
        vm.prank(admin);
        roleManager.executeRoleGrant(ADMIN_ROLE, user1);

        assertTrue(roleManager.isAdmin(user1));
    }

    function test_IsAdmin_ReturnsFalseForNonAdmin() public view {
        assertFalse(roleManager.isAdmin(user1));
    }

    function test_HasAllRoles_ReturnsTrueWhenHasAllRoles() public {
        vm.startPrank(admin);

        roleManager.scheduleRoleGrant(VERIFIER_ROLE, user1);
        roleManager.scheduleRoleGrant(ARBITRATOR_ROLE, user1);

        bytes32[] memory roles = new bytes32[](2);
        roles[0] = VERIFIER_ROLE;
        roles[1] = ARBITRATOR_ROLE;

        assertTrue(roleManager.hasAllRoles(user1, roles));

        vm.stopPrank();
    }

    function test_HasAllRoles_ReturnsFalseWhenMissingRole() public {
        vm.startPrank(admin);

        roleManager.scheduleRoleGrant(VERIFIER_ROLE, user1);

        bytes32[] memory roles = new bytes32[](2);
        roles[0] = VERIFIER_ROLE;
        roles[1] = ARBITRATOR_ROLE;

        assertFalse(roleManager.hasAllRoles(user1, roles));

        vm.stopPrank();
    }

    function test_HasAnyRole_ReturnsTrueWhenHasOneRole() public {
        vm.startPrank(admin);

        roleManager.scheduleRoleGrant(VERIFIER_ROLE, user1);

        bytes32[] memory roles = new bytes32[](2);
        roles[0] = VERIFIER_ROLE;
        roles[1] = ARBITRATOR_ROLE;

        assertTrue(roleManager.hasAnyRole(user1, roles));

        vm.stopPrank();
    }

    function test_HasAnyRole_ReturnsFalseWhenHasNoRoles() public view {
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = VERIFIER_ROLE;
        roles[1] = ARBITRATOR_ROLE;

        assertFalse(roleManager.hasAnyRole(user1, roles));
    }

    // ============================================
    //          ROLE CONSTANT TESTS
    // ============================================

    function test_RoleConstants_MatchExpectedValues() public view {
        assertEq(roleManager.ADMIN_ROLE(), keccak256("ADMIN_ROLE"));
        assertEq(roleManager.VERIFIER_ROLE(), keccak256("VERIFIER_ROLE"));
        assertEq(roleManager.ARBITRATOR_ROLE(), keccak256("ARBITRATOR_ROLE"));
        assertEq(roleManager.PAUSER_ROLE(), keccak256("PAUSER_ROLE"));
        assertEq(roleManager.FEE_MANAGER_ROLE(), keccak256("FEE_MANAGER_ROLE"));
    }

    function test_TimelockConstant_Is24Hours() public view {
        assertEq(roleManager.ROLE_CHANGE_TIMELOCK(), 24 hours);
    }

    // ============================================
    //          EDGE CASE TESTS
    // ============================================

    function test_MultipleScheduledGrants_WorkIndependently() public {
        vm.startPrank(admin);

        // Schedule multiple grants
        roleManager.scheduleRoleGrant(ADMIN_ROLE, user1);
        roleManager.scheduleRoleGrant(ADMIN_ROLE, user2);

        uint256 executeAfter1 = roleManager.getPendingRoleGrant(ADMIN_ROLE, user1);
        uint256 executeAfter2 = roleManager.getPendingRoleGrant(ADMIN_ROLE, user2);

        assertEq(executeAfter1, executeAfter2);

        // Fast forward and execute first grant
        vm.warp(block.timestamp + roleManager.ROLE_CHANGE_TIMELOCK() + 1);
        roleManager.executeRoleGrant(ADMIN_ROLE, user1);

        // Second grant should still be pending
        assertTrue(roleManager.canExecuteRoleGrant(ADMIN_ROLE, user2));

        vm.stopPrank();
    }

    function test_GrantAndRevoke_MultipleRounds() public {
        vm.startPrank(admin);

        // Round 1: Grant
        roleManager.scheduleRoleGrant(VERIFIER_ROLE, user1);
        assertTrue(roleManager.hasRole(VERIFIER_ROLE, user1));

        // Round 1: Revoke
        roleManager.revokeRoleWithCheck(VERIFIER_ROLE, user1);
        assertFalse(roleManager.hasRole(VERIFIER_ROLE, user1));

        // Round 2: Grant again
        roleManager.scheduleRoleGrant(VERIFIER_ROLE, user1);
        assertTrue(roleManager.hasRole(VERIFIER_ROLE, user1));

        vm.stopPrank();
    }

    function test_PauseUnpause_MultipleCycles() public {
        vm.startPrank(admin);

        // Cycle 1
        roleManager.pause("incident 1");
        assertTrue(roleManager.isPaused());
        roleManager.unpause();
        assertFalse(roleManager.isPaused());

        // Cycle 2
        roleManager.pause("incident 2");
        assertTrue(roleManager.isPaused());
        roleManager.unpause();
        assertFalse(roleManager.isPaused());

        vm.stopPrank();
    }

    function test_RoleMembers_AfterMultipleOperations() public {
        vm.startPrank(admin);

        // Grant to multiple users
        roleManager.scheduleRoleGrant(VERIFIER_ROLE, user1);
        roleManager.scheduleRoleGrant(VERIFIER_ROLE, user2);
        roleManager.scheduleRoleGrant(VERIFIER_ROLE, user3);

        assertEq(roleManager.getRoleMemberCount(VERIFIER_ROLE), 3);

        // Revoke from middle user
        roleManager.revokeRoleWithCheck(VERIFIER_ROLE, user2);

        assertEq(roleManager.getRoleMemberCount(VERIFIER_ROLE), 2);

        address[] memory members = roleManager.getRoleMembers(VERIFIER_ROLE);
        assertTrue(members[0] == user1 || members[0] == user3);
        assertTrue(members[1] == user1 || members[1] == user3);

        vm.stopPrank();
    }

    // ============================================
    //          FUZZ TESTS
    // ============================================

    function testFuzz_ScheduleRoleGrant_NonSensitiveRole(address account) public {
        vm.assume(account != address(0));
        vm.assume(!roleManager.hasRole(VERIFIER_ROLE, account));

        vm.prank(admin);
        roleManager.scheduleRoleGrant(VERIFIER_ROLE, account);

        assertTrue(roleManager.hasRole(VERIFIER_ROLE, account));
    }

    function testFuzz_ScheduleAndExecuteRoleGrant_SensitiveRole(address account) public {
        vm.assume(account != address(0));
        vm.assume(!roleManager.hasRole(ADMIN_ROLE, account));

        vm.startPrank(admin);

        // Schedule
        roleManager.scheduleRoleGrant(ADMIN_ROLE, account);

        // Fast forward
        vm.warp(block.timestamp + roleManager.ROLE_CHANGE_TIMELOCK() + 1);

        // Execute
        roleManager.executeRoleGrant(ADMIN_ROLE, account);

        assertTrue(roleManager.hasRole(ADMIN_ROLE, account));

        vm.stopPrank();
    }

    function testFuzz_PauseWithReason(string calldata reason) public {
        vm.prank(admin);
        roleManager.pause(reason);

        assertTrue(roleManager.isPaused());
    }
}

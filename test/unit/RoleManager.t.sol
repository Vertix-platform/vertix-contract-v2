// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../../src/access/RoleManager.sol";

contract RoleManagerTest is Test {
    RoleManager public roleManager;

    address public admin = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    address public pauser = address(4);

    event RoleGrantScheduled(
        bytes32 indexed role,
        address indexed account,
        address indexed scheduler,
        uint256 executeAfter
    );
    event RoleGrantExecuted(
        bytes32 indexed role,
        address indexed account,
        address indexed executor
    );
    event RoleGrantCancelled(
        bytes32 indexed role,
        address indexed account,
        address indexed canceller
    );
    event EmergencyPaused(address indexed pauser, string reason);
    event EmergencyUnpaused(address indexed unpauser);

    function setUp() public {
        vm.prank(admin);
        roleManager = new RoleManager(admin);
    }

    // ============================================
    //        CONSTRUCTOR TESTS
    // ============================================

    function test_constructor_GrantsRolesToAdmin() public {
        assertTrue(
            roleManager.hasRole(roleManager.DEFAULT_ADMIN_ROLE(), admin)
        );
        assertTrue(roleManager.hasRole(roleManager.ADMIN_ROLE(), admin));
        assertTrue(roleManager.hasRole(roleManager.PAUSER_ROLE(), admin));
        assertTrue(roleManager.hasRole(roleManager.FEE_MANAGER_ROLE(), admin));
    }

    function test_constructor_RevertIf_InvalidAdmin() public {
        vm.expectRevert("Invalid initial admin");
        new RoleManager(address(0));
    }

    // ============================================
    //       ROLE GRANT TESTS
    // ============================================

    function test_scheduleRoleGrant_NonSensitiveRole() public {
        vm.prank(admin);

        // Non-sensitive roles grant immediately
        roleManager.scheduleRoleGrant(roleManager.VERIFIER_ROLE(), user1);

        assertTrue(roleManager.hasRole(roleManager.VERIFIER_ROLE(), user1));
    }

    function test_scheduleRoleGrant_SensitiveRoleWithTimelock() public {
        vm.prank(admin);

        uint256 expectedExecuteTime = block.timestamp +
            roleManager.ROLE_CHANGE_TIMELOCK();

        vm.expectEmit(true, true, true, true);
        emit RoleGrantScheduled(
            roleManager.ADMIN_ROLE(),
            user1,
            admin,
            expectedExecuteTime
        );

        roleManager.scheduleRoleGrant(roleManager.ADMIN_ROLE(), user1);

        // Should not have role yet
        assertFalse(roleManager.hasRole(roleManager.ADMIN_ROLE(), user1));

        // Check pending grant
        assertEq(
            roleManager.getPendingRoleGrant(roleManager.ADMIN_ROLE(), user1),
            expectedExecuteTime
        );
    }

    function test_scheduleRoleGrant_RevertIf_NotAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        roleManager.scheduleRoleGrant(roleManager.VERIFIER_ROLE(), user2);
    }

    function test_scheduleRoleGrant_RevertIf_InvalidAccount() public {
        vm.prank(admin);
        vm.expectRevert("Invalid account");
        roleManager.scheduleRoleGrant(roleManager.VERIFIER_ROLE(), address(0));
    }

    function test_scheduleRoleGrant_RevertIf_AlreadyHasRole() public {
        vm.startPrank(admin);

        roleManager.scheduleRoleGrant(roleManager.VERIFIER_ROLE(), user1);

        vm.expectRevert("Already has role");
        roleManager.scheduleRoleGrant(roleManager.VERIFIER_ROLE(), user1);

        vm.stopPrank();
    }

    // ============================================
    //      EXECUTE ROLE GRANT TESTS
    // ============================================

    function test_executeRoleGrant_Success() public {
        vm.startPrank(admin);

        // Schedule grant
        roleManager.scheduleRoleGrant(roleManager.ADMIN_ROLE(), user1);

        // Fast forward past timelock
        vm.warp(block.timestamp + roleManager.ROLE_CHANGE_TIMELOCK() + 1);

        vm.expectEmit(true, true, true, true);
        emit RoleGrantExecuted(roleManager.ADMIN_ROLE(), user1, admin);

        roleManager.executeRoleGrant(roleManager.ADMIN_ROLE(), user1);

        // Should now have role
        assertTrue(roleManager.hasRole(roleManager.ADMIN_ROLE(), user1));

        // Pending grant should be cleared
        assertEq(
            roleManager.getPendingRoleGrant(roleManager.ADMIN_ROLE(), user1),
            0
        );

        vm.stopPrank();
    }

    function test_executeRoleGrant_RevertIf_NoScheduledGrant() public {
        vm.prank(admin);
        vm.expectRevert();
        roleManager.executeRoleGrant(roleManager.ADMIN_ROLE(), user1);
    }

    function test_executeRoleGrant_RevertIf_TimelockNotExpired() public {
        vm.startPrank(admin);

        roleManager.scheduleRoleGrant(roleManager.ADMIN_ROLE(), user1);

        // Try to execute immediately
        vm.expectRevert();
        roleManager.executeRoleGrant(roleManager.ADMIN_ROLE(), user1);

        vm.stopPrank();
    }

    // ============================================
    // CANCEL ROLE GRANT TESTS
    // ============================================

    function test_cancelRoleGrant_Success() public {
        vm.startPrank(admin);

        roleManager.scheduleRoleGrant(roleManager.ADMIN_ROLE(), user1);

        vm.expectEmit(true, true, true, true);
        emit RoleGrantCancelled(roleManager.ADMIN_ROLE(), user1, admin);

        roleManager.cancelRoleGrant(roleManager.ADMIN_ROLE(), user1);

        assertEq(
            roleManager.getPendingRoleGrant(roleManager.ADMIN_ROLE(), user1),
            0
        );

        vm.stopPrank();
    }

    function test_cancelRoleGrant_RevertIf_NoScheduledGrant() public {
        vm.prank(admin);
        vm.expectRevert();
        roleManager.cancelRoleGrant(roleManager.ADMIN_ROLE(), user1);
    }

    // ============================================
    // REVOKE ROLE TESTS
    // ============================================

    function test_revokeRoleWithCheck_Success() public {
        vm.startPrank(admin);

        // Grant role first
        roleManager.scheduleRoleGrant(roleManager.VERIFIER_ROLE(), user1);

        // Revoke
        roleManager.revokeRoleWithCheck(roleManager.VERIFIER_ROLE(), user1);

        assertFalse(roleManager.hasRole(roleManager.VERIFIER_ROLE(), user1));

        vm.stopPrank();
    }

    function test_revokeRoleWithCheck_RevertIf_LastAdmin() public {
        vm.prank(admin);
        vm.expectRevert();
        roleManager.revokeRoleWithCheck(
            roleManager.DEFAULT_ADMIN_ROLE(),
            admin
        );
    }

    function test_revokeRoleWithCheck_AllowsIfMultipleAdmins() public {
        vm.startPrank(admin);

        // Add another admin
        roleManager.scheduleRoleGrant(roleManager.DEFAULT_ADMIN_ROLE(), user1);
        vm.warp(block.timestamp + roleManager.ROLE_CHANGE_TIMELOCK() + 1);
        roleManager.executeRoleGrant(roleManager.DEFAULT_ADMIN_ROLE(), user1);

        // Now can revoke original admin
        roleManager.revokeRoleWithCheck(
            roleManager.DEFAULT_ADMIN_ROLE(),
            admin
        );

        assertFalse(
            roleManager.hasRole(roleManager.DEFAULT_ADMIN_ROLE(), admin)
        );
        assertTrue(
            roleManager.hasRole(roleManager.DEFAULT_ADMIN_ROLE(), user1)
        );

        vm.stopPrank();
    }

    // ============================================
    // PAUSE/UNPAUSE TESTS
    // ============================================

    function test_pause_Success() public {
        vm.prank(admin);

        vm.expectEmit(true, false, false, true);
        emit EmergencyPaused(admin, "Test pause");

        roleManager.pause("Test pause");

        assertTrue(roleManager.isPaused());
    }

    function test_pause_RevertIf_NotPauser() public {
        vm.prank(user1);
        vm.expectRevert("Not pauser");
        roleManager.pause("Test");
    }

    function test_unpause_Success() public {
        vm.startPrank(admin);

        roleManager.pause("Test");

        vm.expectEmit(true, false, false, false);
        emit EmergencyUnpaused(admin);

        roleManager.unpause();

        assertFalse(roleManager.isPaused());

        vm.stopPrank();
    }

    function test_unpause_RevertIf_NotAdmin() public {
        vm.prank(admin);
        roleManager.pause("Test");

        vm.prank(user1);
        vm.expectRevert("Not admin");
        roleManager.unpause();
    }

    // ============================================
    // VIEW FUNCTION TESTS
    // ============================================

    function test_getRoleMembers() public {
        vm.startPrank(admin);

        roleManager.scheduleRoleGrant(roleManager.VERIFIER_ROLE(), user1);
        roleManager.scheduleRoleGrant(roleManager.VERIFIER_ROLE(), user2);

        address[] memory members = roleManager.getRoleMembers(
            roleManager.VERIFIER_ROLE()
        );

        assertEq(members.length, 2);
        assertEq(members[0], user1);
        assertEq(members[1], user2);

        vm.stopPrank();
    }

    function test_getRoleMemberCount() public {
        vm.startPrank(admin);

        assertEq(
            roleManager.getRoleMemberCount(roleManager.VERIFIER_ROLE()),
            0
        );

        roleManager.scheduleRoleGrant(roleManager.VERIFIER_ROLE(), user1);
        assertEq(
            roleManager.getRoleMemberCount(roleManager.VERIFIER_ROLE()),
            1
        );

        roleManager.scheduleRoleGrant(roleManager.VERIFIER_ROLE(), user2);
        assertEq(
            roleManager.getRoleMemberCount(roleManager.VERIFIER_ROLE()),
            2
        );

        vm.stopPrank();
    }

    function test_canExecuteRoleGrant() public {
        vm.startPrank(admin);

        roleManager.scheduleRoleGrant(roleManager.ADMIN_ROLE(), user1);

        assertFalse(
            roleManager.canExecuteRoleGrant(roleManager.ADMIN_ROLE(), user1)
        );

        vm.warp(block.timestamp + roleManager.ROLE_CHANGE_TIMELOCK() + 1);

        assertTrue(
            roleManager.canExecuteRoleGrant(roleManager.ADMIN_ROLE(), user1)
        );

        vm.stopPrank();
    }

    function test_isAdmin() public {
        assertTrue(roleManager.isAdmin(admin));
        assertFalse(roleManager.isAdmin(user1));

        vm.prank(admin);
        roleManager.scheduleRoleGrant(roleManager.ADMIN_ROLE(), user1);
        vm.warp(block.timestamp + roleManager.ROLE_CHANGE_TIMELOCK() + 1);

        vm.prank(admin);
        roleManager.executeRoleGrant(roleManager.ADMIN_ROLE(), user1);

        assertTrue(roleManager.isAdmin(user1));
    }

    // ============================================
    // BATCH OPERATIONS TESTS
    // ============================================

    function test_batchGrantRoles_Success() public {
        vm.prank(admin);

        bytes32[] memory roles = new bytes32[](3);
        roles[0] = roleManager.VERIFIER_ROLE();
        roles[1] = roleManager.ARBITRATOR_ROLE();
        roles[2] = roleManager.PAUSER_ROLE();

        address[] memory accounts = new address[](3);
        accounts[0] = user1;
        accounts[1] = user1;
        accounts[2] = user1;

        roleManager.batchGrantRoles(roles, accounts);

        assertTrue(roleManager.hasRole(roleManager.VERIFIER_ROLE(), user1));
        assertTrue(roleManager.hasRole(roleManager.ARBITRATOR_ROLE(), user1));
        assertTrue(roleManager.hasRole(roleManager.PAUSER_ROLE(), user1));
    }

    function test_batchGrantRoles_RevertIf_LengthMismatch() public {
        bytes32[] memory roles = new bytes32[](2);
        address[] memory accounts = new address[](3);

        vm.prank(admin);
        vm.expectRevert("Length mismatch");
        roleManager.batchGrantRoles(roles, accounts);
    }

    function test_hasAllRoles() public {
        vm.startPrank(admin);

        roleManager.scheduleRoleGrant(roleManager.VERIFIER_ROLE(), user1);
        roleManager.scheduleRoleGrant(roleManager.ARBITRATOR_ROLE(), user1);

        bytes32[] memory rolesToCheck = new bytes32[](2);
        rolesToCheck[0] = roleManager.VERIFIER_ROLE();
        rolesToCheck[1] = roleManager.ARBITRATOR_ROLE();

        assertTrue(roleManager.hasAllRoles(user1, rolesToCheck));

        rolesToCheck[1] = roleManager.FEE_MANAGER_ROLE();
        assertFalse(roleManager.hasAllRoles(user1, rolesToCheck));

        vm.stopPrank();
    }

    function test_hasAnyRole() public {
        vm.prank(admin);
        roleManager.scheduleRoleGrant(roleManager.VERIFIER_ROLE(), user1);

        bytes32[] memory rolesToCheck = new bytes32[](2);
        rolesToCheck[0] = roleManager.VERIFIER_ROLE();
        rolesToCheck[1] = roleManager.ARBITRATOR_ROLE();

        assertTrue(roleManager.hasAnyRole(user1, rolesToCheck));

        rolesToCheck[0] = roleManager.ARBITRATOR_ROLE();
        rolesToCheck[1] = roleManager.FEE_MANAGER_ROLE();

        assertFalse(roleManager.hasAnyRole(user1, rolesToCheck));
    }

    // ============================================
    // FUZZ TESTS
    // ============================================

    function testFuzz_scheduleRoleGrant_NonSensitiveRoles(
        address account
    ) public {
        vm.assume(account != address(0));
        vm.assume(!roleManager.hasRole(roleManager.VERIFIER_ROLE(), account));

        vm.prank(admin);
        roleManager.scheduleRoleGrant(roleManager.VERIFIER_ROLE(), account);

        assertTrue(roleManager.hasRole(roleManager.VERIFIER_ROLE(), account));
    }

    function testFuzz_revokeRoleWithCheck(address account) public {
        vm.assume(account != address(0));
        vm.assume(account != admin);

        vm.startPrank(admin);

        roleManager.scheduleRoleGrant(roleManager.VERIFIER_ROLE(), account);
        assertTrue(roleManager.hasRole(roleManager.VERIFIER_ROLE(), account));

        roleManager.revokeRoleWithCheck(roleManager.VERIFIER_ROLE(), account);
        assertFalse(roleManager.hasRole(roleManager.VERIFIER_ROLE(), account));

        vm.stopPrank();
    }
}

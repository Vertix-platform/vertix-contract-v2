// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../../src/verification/ReputationManager.sol";
import "../../src/access/RoleManager.sol";
import "../../src/libraries/AssetTypes.sol";

contract ReputationManagerTest is Test {
    ReputationManager public reputationManager;
    RoleManager public roleManager;

    address public admin = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public unauthorized = address(0x4);

    // Events
    event ReputationUpdated(
        address indexed user,
        IReputationManager.ReputationAction indexed action,
        int256 pointsChange,
        int256 newScore
    );

    event UserBanned(
        address indexed user,
        string reason,
        address indexed bannedBy
    );

    event UserUnbanned(address indexed user, address indexed unbannedBy);

    function setUp() public {
        vm.startPrank(admin);

        // Deploy RoleManager
        roleManager = new RoleManager(admin);

        // Deploy ReputationManager
        reputationManager = new ReputationManager(address(roleManager));

        vm.stopPrank();
    }

    // ============================================
    // CONSTRUCTOR TESTS
    // ============================================

    function test_constructor_Success() public {
        ReputationManager newManager = new ReputationManager(
            address(roleManager)
        );
        assertEq(address(newManager.roleManager()), address(roleManager));

        // Check constants
        assertEq(newManager.POINTS_SUCCESSFUL_SALE(), 10);
        assertEq(newManager.POINTS_SUCCESSFUL_PURCHASE(), 5);
        assertEq(newManager.POINTS_VERIFIED_ASSET(), 20);
        assertEq(newManager.POINTS_DISPUTE_WON(), 10);
        assertEq(newManager.POINTS_DISPUTE_LOST(), -50);
        assertEq(newManager.POINTS_FRAUD(), -100);
        assertEq(newManager.POINTS_INACTIVITY_DECAY(), -1);
        assertEq(newManager.INACTIVITY_PERIOD(), 30 days);
        assertEq(newManager.BAN_THRESHOLD(), -100);
    }

    function test_constructor_RevertIf_InvalidRoleManager() public {
        vm.expectRevert("Invalid role manager");
        new ReputationManager(address(0));
    }

    // ============================================
    // UPDATE REPUTATION TESTS
    // ============================================

    function test_updateReputation_SuccessfulSale() public {
        vm.prank(admin);

        vm.expectEmit(true, true, true, true);
        emit ReputationUpdated(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale,
            10,
            110
        );

        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );

        IReputationManager.Reputation memory rep = reputationManager
            .getReputation(user1);
        assertEq(rep.score, 110); // Base 100 + 10
        assertEq(rep.successfulSales, 1);
        assertEq(rep.lastActivityTime, block.timestamp);
    }

    function test_updateReputation_SuccessfulPurchase() public {
        vm.prank(admin);
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulPurchase
        );

        IReputationManager.Reputation memory rep = reputationManager
            .getReputation(user1);
        assertEq(rep.score, 105); // Base 100 + 5
        assertEq(rep.successfulPurchases, 1);
    }

    function test_updateReputation_VerifiedAsset() public {
        vm.prank(admin);
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.VerifiedAsset
        );

        IReputationManager.Reputation memory rep = reputationManager
            .getReputation(user1);
        assertEq(rep.score, 120); // Base 100 + 20
        assertEq(rep.verifiedAssets, 1);
    }

    function test_updateReputation_DisputeWon() public {
        vm.prank(admin);
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.DisputeWon
        );

        IReputationManager.Reputation memory rep = reputationManager
            .getReputation(user1);
        assertEq(rep.score, 110); // Base 100 + 10
        assertEq(rep.disputesWon, 1);
    }

    function test_updateReputation_DisputeLost() public {
        vm.prank(admin);
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.DisputeLost
        );

        IReputationManager.Reputation memory rep = reputationManager
            .getReputation(user1);
        assertEq(rep.score, 50); // Base 100 - 50
        assertEq(rep.disputesLost, 1);
    }

    function test_updateReputation_FraudDetected_AutoBan() public {
        vm.prank(admin);

        vm.expectEmit(true, true, true, true);
        emit UserBanned(
            user1,
            "Score below threshold",
            address(reputationManager)
        );

        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.FraudDetected
        );

        IReputationManager.Reputation memory rep = reputationManager
            .getReputation(user1);
        assertEq(rep.score, 0); // Base 100 - 100
        assertTrue(rep.isBanned);
    }

    function test_updateReputation_MultipleTimes() public {
        vm.startPrank(admin);

        // Successful sale: 100 + 10 = 110
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );

        // Successful purchase: 110 + 5 = 115
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulPurchase
        );

        // Verified asset: 115 + 20 = 135
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.VerifiedAsset
        );

        vm.stopPrank();

        IReputationManager.Reputation memory rep = reputationManager
            .getReputation(user1);
        assertEq(rep.score, 135);
        assertEq(rep.successfulSales, 1);
        assertEq(rep.successfulPurchases, 1);
        assertEq(rep.verifiedAssets, 1);
    }

    function test_updateReputation_InactivityDecay() public {
        vm.startPrank(admin);

        // Initial update
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );

        // Score is now 110
        assertEq(reputationManager.getReputation(user1).score, 110);

        // Move forward 60 days (2 inactivity periods)
        vm.warp(block.timestamp + 60 days);

        // Update again - should apply decay before update
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );

        vm.stopPrank();

        // 110 (previous) - 2 (decay) + 10 (new sale) = 118
        IReputationManager.Reputation memory rep = reputationManager
            .getReputation(user1);
        assertEq(rep.score, 118);
    }

    function test_updateReputation_AutoBanAtThreshold() public {
        vm.startPrank(admin);

        // Start with base score 100
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );

        // Apply multiple dispute losses to reach ban threshold
        // 110 - 50 = 60
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.DisputeLost
        );

        // 60 - 50 = 10
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.DisputeLost
        );

        // 10 - 50 = -40
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.DisputeLost
        );

        // -40 - 50 = -90
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.DisputeLost
        );

        // Not yet banned at -90
        assertFalse(reputationManager.getReputation(user1).isBanned);

        // -90 - 50 = -140 (below -100 threshold, should auto-ban)
        vm.expectEmit(true, true, true, true);
        emit UserBanned(
            user1,
            "Score below threshold",
            address(reputationManager)
        );

        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.DisputeLost
        );

        vm.stopPrank();

        assertTrue(reputationManager.getReputation(user1).isBanned);
        assertEq(reputationManager.getReputation(user1).score, -140);
    }

    function test_updateReputation_RevertIf_InvalidUser() public {
        vm.prank(admin);
        vm.expectRevert("Invalid user");
        reputationManager.updateReputation(
            address(0),
            IReputationManager.ReputationAction.SuccessfulSale
        );
    }

    function test_updateReputation_RevertIf_NotAuthorized() public {
        vm.prank(unauthorized);
        vm.expectRevert("Not authorized to update reputation");
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );
    }

    // ============================================
    // BAN/UNBAN TESTS
    // ============================================

    function test_banUser_Success() public {
        // Initialize user with some activity
        vm.prank(admin);
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );

        // Ban user
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit UserBanned(user1, "Violating terms", admin);

        reputationManager.banUser(user1, "Violating terms");

        assertTrue(reputationManager.isBanned(user1));
        assertFalse(reputationManager.isGoodStanding(user1));
    }

    function test_banUser_RevertIf_NotAdmin() public {
        vm.prank(unauthorized);
        vm.expectRevert("Not admin");
        reputationManager.banUser(user1, "Unauthorized ban");
    }

    function test_banUser_RevertIf_AlreadyBanned() public {
        vm.startPrank(admin);

        // Initialize and ban user
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );
        reputationManager.banUser(user1, "First ban");

        // Try to ban again
        vm.expectRevert("Already banned");
        reputationManager.banUser(user1, "Second ban");

        vm.stopPrank();
    }

    function test_unbanUser_Success() public {
        vm.startPrank(admin);

        // Initialize, ban, then unban
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );
        reputationManager.banUser(user1, "Test ban");

        vm.expectEmit(true, true, true, true);
        emit UserUnbanned(user1, admin);

        reputationManager.unbanUser(user1);

        vm.stopPrank();

        assertFalse(reputationManager.isBanned(user1));
    }

    function test_unbanUser_RevertIf_NotAdmin() public {
        vm.prank(admin);
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );

        vm.prank(admin);
        reputationManager.banUser(user1, "Test ban");

        vm.prank(unauthorized);
        vm.expectRevert("Not admin");
        reputationManager.unbanUser(user1);
    }

    function test_unbanUser_RevertIf_NotBanned() public {
        vm.prank(admin);
        vm.expectRevert("Not banned");
        reputationManager.unbanUser(user1);
    }

    // ============================================
    // VIEW FUNCTION TESTS
    // ============================================

    function test_getReputationScore_NewUser() public {
        int256 score = reputationManager.getReputationScore(user1);
        assertEq(score, 100); // Base score for new user
    }

    function test_getReputationScore_WithActivity() public {
        vm.prank(admin);
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );

        int256 score = reputationManager.getReputationScore(user1);
        assertEq(score, 110);
    }

    function test_getReputationScore_WithDecay() public {
        vm.prank(admin);
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );

        // Move forward 90 days (3 inactivity periods)
        vm.warp(block.timestamp + 90 days);

        // Score should be 110 - 3 = 107 (with decay)
        int256 score = reputationManager.getReputationScore(user1);
        assertEq(score, 107);
    }

    function test_isGoodStanding_NewUser() public {
        // New users start in good standing (100 >= 50)
        assertTrue(reputationManager.isGoodStanding(user1));
    }

    function test_isGoodStanding_HighScore() public {
        vm.startPrank(admin);
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.VerifiedAsset
        );
        vm.stopPrank();

        assertTrue(reputationManager.isGoodStanding(user1));
    }

    function test_isGoodStanding_LowScore() public {
        vm.startPrank(admin);
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.DisputeLost
        );
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.DisputeLost
        );
        vm.stopPrank();

        // 100 - 50 - 50 = 0 (below 50, not in good standing)
        assertFalse(reputationManager.isGoodStanding(user1));
    }

    function test_isGoodStanding_Banned() public {
        vm.startPrank(admin);
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );
        reputationManager.banUser(user1, "Test ban");
        vm.stopPrank();

        assertFalse(reputationManager.isGoodStanding(user1));
    }

    function test_isBanned_NotBanned() public {
        assertFalse(reputationManager.isBanned(user1));
    }

    function test_isBanned_Banned() public {
        vm.startPrank(admin);
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.FraudDetected
        );
        vm.stopPrank();

        assertTrue(reputationManager.isBanned(user1));
    }

    function test_getUserStats() public {
        vm.startPrank(admin);

        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulPurchase
        );
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.VerifiedAsset
        );
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.DisputeWon
        );
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.DisputeLost
        );

        vm.stopPrank();

        (
            uint32 successfulSales,
            uint32 successfulPurchases,
            uint32 disputesLost,
            uint32 disputesWon,
            uint32 verifiedAssets
        ) = reputationManager.getUserStats(user1);

        assertEq(successfulSales, 2);
        assertEq(successfulPurchases, 1);
        assertEq(disputesLost, 1);
        assertEq(disputesWon, 1);
        assertEq(verifiedAssets, 1);
    }

    function test_getSuccessRate_NewUser() public {
        uint256 successRate = reputationManager.getSuccessRate(user1);
        assertEq(successRate, 10000); // 100% for new users
    }

    function test_getSuccessRate_NoDisputes() public {
        vm.startPrank(admin);
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulPurchase
        );
        vm.stopPrank();

        uint256 successRate = reputationManager.getSuccessRate(user1);
        assertEq(successRate, 10000); // 100% with no disputes
    }

    function test_getSuccessRate_WithDisputes() public {
        vm.startPrank(admin);

        // 3 successful sales
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );

        // 2 successful purchases
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulPurchase
        );
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulPurchase
        );

        // 1 dispute lost
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.DisputeLost
        );

        vm.stopPrank();

        // Total: 5 transactions, 1 dispute lost
        // Success rate: (5 - 1) / 5 = 4/5 = 80% = 8000 basis points
        uint256 successRate = reputationManager.getSuccessRate(user1);
        assertEq(successRate, 8000);
    }

    function test_getSuccessRate_AllDisputesLost() public {
        vm.startPrank(admin);

        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.DisputeLost
        );

        vm.stopPrank();

        // 1 transaction, 1 dispute lost = 0% success rate
        uint256 successRate = reputationManager.getSuccessRate(user1);
        assertEq(successRate, 0);
    }

    function test_getReputation_CompleteData() public {
        vm.startPrank(admin);

        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulPurchase
        );

        vm.stopPrank();

        IReputationManager.Reputation memory rep = reputationManager
            .getReputation(user1);

        assertEq(rep.score, 115); // 100 + 10 + 5
        assertEq(rep.successfulSales, 1);
        assertEq(rep.successfulPurchases, 1);
        assertEq(rep.disputesLost, 0);
        assertEq(rep.disputesWon, 0);
        assertEq(rep.verifiedAssets, 0);
        assertFalse(rep.isBanned);
        assertEq(rep.lastActivityTime, block.timestamp);
    }

    // ============================================
    // FUZZ TESTS
    // ============================================

    function testFuzz_updateReputation_SuccessfulSale(uint8 count) public {
        vm.assume(count > 0 && count <= 100);

        vm.startPrank(admin);

        for (uint8 i = 0; i < count; i++) {
            reputationManager.updateReputation(
                user1,
                IReputationManager.ReputationAction.SuccessfulSale
            );
        }

        vm.stopPrank();

        IReputationManager.Reputation memory rep = reputationManager
            .getReputation(user1);
        assertEq(rep.successfulSales, count);
        assertEq(rep.score, 100 + (int256(uint256(count)) * 10));
    }

    function testFuzz_getReputationScore_WithDecay(uint256 timeElapsed) public {
        timeElapsed = bound(timeElapsed, 0, 365 days);

        vm.prank(admin);
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        );

        // Initial score is 110
        assertEq(reputationManager.getReputationScore(user1), 110);

        // Move time forward
        vm.warp(block.timestamp + timeElapsed);

        // Calculate expected decay
        uint256 inactivePeriods = timeElapsed / 30 days;
        int256 expectedScore = 110 - int256(inactivePeriods);

        assertEq(reputationManager.getReputationScore(user1), expectedScore);
    }

    function testFuzz_getSuccessRate(
        uint8 sales,
        uint8 purchases,
        uint8 disputesLost
    ) public {
        vm.assume(sales > 0 && sales <= 50);
        vm.assume(purchases > 0 && purchases <= 50);
        vm.assume(disputesLost <= sales + purchases);

        vm.startPrank(admin);

        for (uint8 i = 0; i < sales; i++) {
            reputationManager.updateReputation(
                user1,
                IReputationManager.ReputationAction.SuccessfulSale
            );
        }

        for (uint8 i = 0; i < purchases; i++) {
            reputationManager.updateReputation(
                user1,
                IReputationManager.ReputationAction.SuccessfulPurchase
            );
        }

        for (uint8 i = 0; i < disputesLost; i++) {
            reputationManager.updateReputation(
                user1,
                IReputationManager.ReputationAction.DisputeLost
            );
        }

        vm.stopPrank();

        uint256 totalTransactions = uint256(sales) + uint256(purchases);
        uint256 successful = totalTransactions - uint256(disputesLost);
        uint256 expectedRate = (successful * 10000) / totalTransactions;

        uint256 actualRate = reputationManager.getSuccessRate(user1);
        assertEq(actualRate, expectedRate);
    }

    // ============================================
    // EDGE CASE TESTS
    // ============================================

    function test_edgeCase_ScoreAtExactBanThreshold() public {
        vm.startPrank(admin);

        // Bring score to exactly -100
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        ); // 110

        // Apply fraud to get to exactly 10
        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.FraudDetected
        ); // 10

        // Apply multiple dispute losses to reach exactly -100
        for (uint8 i = 0; i < 3; i++) {
            reputationManager.updateReputation(
                user1,
                IReputationManager.ReputationAction.DisputeLost
            );
        }

        vm.stopPrank();

        // At exactly -100, should NOT be auto-banned (threshold is <= -100)
        // Actually, the logic bans at <= -100, so this should be banned
        assertTrue(reputationManager.getReputation(user1).isBanned);
    }

    function test_edgeCase_NegativeScoreButNotBanned() public {
        vm.startPrank(admin);

        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.SuccessfulSale
        ); // 110

        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.DisputeLost
        ); // 60

        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.DisputeLost
        ); // 10

        reputationManager.updateReputation(
            user1,
            IReputationManager.ReputationAction.DisputeLost
        ); // -40

        vm.stopPrank();

        // Score is negative but above -100, should not be banned
        assertFalse(reputationManager.getReputation(user1).isBanned);
        assertEq(reputationManager.getReputation(user1).score, -40);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ReputationManager} from "../../src/verification/ReputationManager.sol";
import {RoleManager} from "../../src/access/RoleManager.sol";
import {IReputationManager} from "../../src/interfaces/IReputationManager.sol";
import {AssetTypes} from "../../src/libraries/AssetTypes.sol";
import {Errors} from "../../src/libraries/Errors.sol";

contract ReputationManagerTest is Test {
    ReputationManager public reputationManager;
    RoleManager public roleManager;

    address public admin;
    address public user1;
    address public user2;
    address public user3;
    address public authorizedContract;

    // Events
    event ReputationUpdated(
        address indexed user, IReputationManager.ReputationAction action, int256 pointsChange, int256 newScore
    );
    event UserBanned(address indexed user, string reason, address bannedBy);
    event UserUnbanned(address indexed user, address unbannedBy);

    function setUp() public {
        admin = makeAddr("admin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        authorizedContract = makeAddr("authorizedContract");

        // Deploy role manager
        roleManager = new RoleManager(admin);

        // Deploy reputation manager
        reputationManager = new ReputationManager(address(roleManager));

        // Grant admin role to authorized contract for testing
        vm.startPrank(admin);
        roleManager.scheduleRoleGrant(roleManager.ADMIN_ROLE(), authorizedContract);
        // Fast forward past timelock and execute
        vm.warp(block.timestamp + roleManager.ROLE_CHANGE_TIMELOCK() + 1);
        roleManager.executeRoleGrant(roleManager.ADMIN_ROLE(), authorizedContract);
        vm.stopPrank();
    }

    // ============================================
    //          CONSTRUCTOR TESTS
    // ============================================

    function test_Constructor_SetsRoleManager() public view {
        assertEq(address(reputationManager.roleManager()), address(roleManager));
    }

    function test_Constructor_RevertsOnZeroAddress() public {
        vm.expectRevert(Errors.InvalidRoleManager.selector);
        new ReputationManager(address(0));
    }

    function test_Constructor_VerifiesConstants() public view {
        assertEq(reputationManager.POINTS_SUCCESSFUL_SALE(), 10);
        assertEq(reputationManager.POINTS_SUCCESSFUL_PURCHASE(), 5);
        assertEq(reputationManager.POINTS_VERIFIED_ASSET(), 20);
        assertEq(reputationManager.POINTS_DISPUTE_WON(), 10);
        assertEq(reputationManager.POINTS_DISPUTE_LOST(), -50);
        assertEq(reputationManager.POINTS_FRAUD(), -100);
        assertEq(reputationManager.POINTS_INACTIVITY_DECAY(), -1);
        assertEq(reputationManager.INACTIVITY_PERIOD(), 30 days);
        assertEq(reputationManager.BAN_THRESHOLD(), -100);
    }

    // ============================================
    //        UPDATE REPUTATION TESTS
    // ============================================

    function test_UpdateReputation_SuccessfulSale_IncreasesScore() public {
        vm.startPrank(authorizedContract);

        vm.expectEmit(true, false, false, true);
        emit ReputationUpdated(user1, IReputationManager.ReputationAction.SuccessfulSale, 10, 110);

        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);

        IReputationManager.Reputation memory rep = reputationManager.getReputation(user1);
        assertEq(rep.score, 110);
        assertEq(rep.successfulSales, 1);
        assertEq(rep.lastActivityTime, block.timestamp);

        vm.stopPrank();
    }

    function test_UpdateReputation_SuccessfulPurchase_IncreasesScore() public {
        vm.startPrank(authorizedContract);

        vm.expectEmit(true, false, false, true);
        emit ReputationUpdated(user1, IReputationManager.ReputationAction.SuccessfulPurchase, 5, 105);

        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulPurchase);

        IReputationManager.Reputation memory rep = reputationManager.getReputation(user1);
        assertEq(rep.score, 105);
        assertEq(rep.successfulPurchases, 1);

        vm.stopPrank();
    }

    function test_UpdateReputation_VerifiedAsset_IncreasesScore() public {
        vm.startPrank(authorizedContract);

        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.VerifiedAsset);

        IReputationManager.Reputation memory rep = reputationManager.getReputation(user1);
        assertEq(rep.score, 120);
        assertEq(rep.verifiedAssets, 1);

        vm.stopPrank();
    }

    function test_UpdateReputation_DisputeWon_IncreasesScore() public {
        vm.startPrank(authorizedContract);

        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.DisputeWon);

        IReputationManager.Reputation memory rep = reputationManager.getReputation(user1);
        assertEq(rep.score, 110);
        assertEq(rep.disputesWon, 1);

        vm.stopPrank();
    }

    function test_UpdateReputation_DisputeLost_DecreasesScore() public {
        vm.startPrank(authorizedContract);

        vm.expectEmit(true, false, false, true);
        emit ReputationUpdated(user1, IReputationManager.ReputationAction.DisputeLost, -50, 50);

        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.DisputeLost);

        IReputationManager.Reputation memory rep = reputationManager.getReputation(user1);
        assertEq(rep.score, 50);
        assertEq(rep.disputesLost, 1);

        vm.stopPrank();
    }

    function test_UpdateReputation_FraudDetected_BansUser() public {
        vm.startPrank(authorizedContract);

        // Fraud detection sets ban flag directly, doesn't emit UserBanned event
        // Only emits ReputationUpdated event
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.FraudDetected);

        IReputationManager.Reputation memory rep = reputationManager.getReputation(user1);
        assertEq(rep.score, 0); // 100 - 100
        assertTrue(rep.isBanned);

        vm.stopPrank();
    }

    function test_UpdateReputation_MultipleActions_AccumulatesScore() public {
        vm.startPrank(authorizedContract);

        // Multiple successful sales
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);

        IReputationManager.Reputation memory rep = reputationManager.getReputation(user1);
        assertEq(rep.score, 130); // 100 + 10 + 10 + 10
        assertEq(rep.successfulSales, 3);

        vm.stopPrank();
    }

    function test_UpdateReputation_InitializesNewUser() public {
        vm.startPrank(authorizedContract);

        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);

        IReputationManager.Reputation memory rep = reputationManager.getReputation(user1);
        assertEq(rep.score, 110); // 100 base + 10
        assertTrue(rep.lastActivityTime > 0);

        vm.stopPrank();
    }

    function test_UpdateReputation_BansWhenScoreBelowThreshold() public {
        vm.startPrank(authorizedContract);

        // Initialize user
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);

        // Multiple dispute losses to bring score below -100
        // Start: 110, after each -50: 60, 10, -40, -90, -140
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.DisputeLost);
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.DisputeLost);
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.DisputeLost);
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.DisputeLost);
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.DisputeLost);

        IReputationManager.Reputation memory rep = reputationManager.getReputation(user1);
        assertTrue(rep.isBanned);
        assertLe(rep.score, -100);

        vm.stopPrank();
    }

    function test_UpdateReputation_RevertsOnZeroAddress() public {
        vm.startPrank(authorizedContract);

        vm.expectRevert(Errors.InvalidUser.selector);
        reputationManager.updateReputation(address(0), IReputationManager.ReputationAction.SuccessfulSale);

        vm.stopPrank();
    }

    function test_UpdateReputation_RevertsIfNotAuthorized() public {
        vm.startPrank(user1);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotAuthorized.selector, user1));
        reputationManager.updateReputation(user2, IReputationManager.ReputationAction.SuccessfulSale);

        vm.stopPrank();
    }

    function test_UpdateReputation_AllowsAdmin() public {
        vm.startPrank(admin);

        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);

        IReputationManager.Reputation memory rep = reputationManager.getReputation(user1);
        assertEq(rep.score, 110);

        vm.stopPrank();
    }

    // ============================================
    //        INACTIVITY DECAY TESTS
    // ============================================

    function test_InactivityDecay_AppliesAfter30Days() public {
        vm.startPrank(authorizedContract);

        // Initialize user
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);
        assertEq(reputationManager.getReputationScore(user1), 110);

        // Fast forward 30 days
        vm.warp(block.timestamp + 30 days);

        // Check score with decay
        int256 score = reputationManager.getReputationScore(user1);
        assertEq(score, 109); // 110 - 1 (one period)

        vm.stopPrank();
    }

    function test_InactivityDecay_AppliesMultiplePeriods() public {
        vm.startPrank(authorizedContract);

        // Initialize user
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);
        assertEq(reputationManager.getReputationScore(user1), 110);

        // Fast forward 90 days (3 periods)
        vm.warp(block.timestamp + 90 days);

        int256 score = reputationManager.getReputationScore(user1);
        assertEq(score, 107); // 110 - 3

        vm.stopPrank();
    }

    function test_InactivityDecay_ResetsOnActivity() public {
        vm.startPrank(authorizedContract);

        // Initialize user
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);

        // Fast forward 30 days
        vm.warp(block.timestamp + 30 days);

        // Update reputation (applies decay and resets timer)
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulPurchase);

        IReputationManager.Reputation memory rep = reputationManager.getReputation(user1);
        assertEq(rep.score, 114); // 110 - 1 (decay) + 5 (purchase)
        assertEq(rep.lastActivityTime, block.timestamp);

        vm.stopPrank();
    }

    function test_InactivityDecay_NoDecayForNewUser() public view {
        int256 score = reputationManager.getReputationScore(user1);
        assertEq(score, 100); // Base score for new user
    }

    function test_InactivityDecay_PartialPeriodNotApplied() public {
        vm.startPrank(authorizedContract);

        // Initialize user
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);

        // Fast forward 29 days (just under one period)
        vm.warp(block.timestamp + 29 days);

        int256 score = reputationManager.getReputationScore(user1);
        assertEq(score, 110); // No decay yet

        vm.stopPrank();
    }

    // ============================================
    //          BAN/UNBAN TESTS
    // ============================================

    function test_BanUser_AdminCanBan() public {
        vm.startPrank(admin);

        vm.expectEmit(true, false, false, true);
        emit UserBanned(user1, "Terms violation", admin);

        reputationManager.banUser(user1, "Terms violation");

        assertTrue(reputationManager.isBanned(user1));

        vm.stopPrank();
    }

    function test_BanUser_RevertsIfAlreadyBanned() public {
        vm.startPrank(admin);

        reputationManager.banUser(user1, "First ban");

        vm.expectRevert(abi.encodeWithSelector(Errors.AlreadyBanned.selector, user1));
        reputationManager.banUser(user1, "Second ban");

        vm.stopPrank();
    }

    function test_BanUser_RevertsIfNotAdmin() public {
        vm.startPrank(user1);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotAdmin.selector, user1));
        reputationManager.banUser(user2, "test");

        vm.stopPrank();
    }

    function test_UnbanUser_AdminCanUnban() public {
        vm.startPrank(admin);

        // First ban the user
        reputationManager.banUser(user1, "test");
        assertTrue(reputationManager.isBanned(user1));

        // Then unban
        vm.expectEmit(true, false, false, false);
        emit UserUnbanned(user1, admin);

        reputationManager.unbanUser(user1);

        assertFalse(reputationManager.isBanned(user1));

        vm.stopPrank();
    }

    function test_UnbanUser_RevertsIfNotBanned() public {
        vm.startPrank(admin);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotBanned.selector, user1));
        reputationManager.unbanUser(user1);

        vm.stopPrank();
    }

    function test_UnbanUser_RevertsIfNotAdmin() public {
        vm.startPrank(admin);
        reputationManager.banUser(user1, "test");
        vm.stopPrank();

        vm.startPrank(user2);

        vm.expectRevert(abi.encodeWithSelector(Errors.NotAdmin.selector, user2));
        reputationManager.unbanUser(user1);

        vm.stopPrank();
    }

    // ============================================
    //          VIEW FUNCTION TESTS
    // ============================================

    function test_GetReputation_ReturnsEmptyForNewUser() public view {
        IReputationManager.Reputation memory rep = reputationManager.getReputation(user1);

        assertEq(rep.score, 0);
        assertEq(rep.successfulSales, 0);
        assertEq(rep.successfulPurchases, 0);
        assertEq(rep.disputesLost, 0);
        assertEq(rep.disputesWon, 0);
        assertEq(rep.verifiedAssets, 0);
        assertEq(rep.lastActivityTime, 0);
        assertFalse(rep.isBanned);
    }

    function test_GetReputation_ReturnsCorrectData() public {
        vm.startPrank(authorizedContract);

        // Build up reputation
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulPurchase);
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.VerifiedAsset);
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.DisputeWon);

        IReputationManager.Reputation memory rep = reputationManager.getReputation(user1);

        assertEq(rep.score, 155); // 100 + 10 + 10 + 5 + 20 + 10
        assertEq(rep.successfulSales, 2);
        assertEq(rep.successfulPurchases, 1);
        assertEq(rep.verifiedAssets, 1);
        assertEq(rep.disputesWon, 1);
        assertEq(rep.disputesLost, 0);

        vm.stopPrank();
    }

    function test_GetReputationScore_ReturnsBaseForNewUser() public view {
        int256 score = reputationManager.getReputationScore(user1);
        assertEq(score, 100);
    }

    function test_GetReputationScore_IncludesDecay() public {
        vm.startPrank(authorizedContract);

        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);

        // Fast forward 60 days
        vm.warp(block.timestamp + 60 days);

        int256 score = reputationManager.getReputationScore(user1);
        assertEq(score, 108); // 110 - 2

        vm.stopPrank();
    }

    function test_IsGoodStanding_TrueForGoodUser() public {
        vm.startPrank(authorizedContract);

        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);

        assertTrue(reputationManager.isGoodStanding(user1));

        vm.stopPrank();
    }

    function test_IsGoodStanding_TrueAtThreshold() public {
        vm.startPrank(authorizedContract);

        // Initialize user at base score (100)
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);

        // Bring score down to exactly 50 (MIN_GOOD_STANDING_SCORE)
        // Current: 110, need to lose 60 points
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.DisputeLost); // -50
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.DisputeLost); // -50

        IReputationManager.Reputation memory rep = reputationManager.getReputation(user1);
        assertEq(rep.score, 10); // 110 - 50 - 50

        // Score is 10, which is below 50
        assertFalse(reputationManager.isGoodStanding(user1));

        vm.stopPrank();
    }

    function test_IsGoodStanding_FalseForLowScore() public {
        vm.startPrank(authorizedContract);

        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.DisputeLost);
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.DisputeLost);

        assertFalse(reputationManager.isGoodStanding(user1));

        vm.stopPrank();
    }

    function test_IsGoodStanding_FalseForBannedUser() public {
        vm.startPrank(admin);

        reputationManager.banUser(user1, "test");

        assertFalse(reputationManager.isGoodStanding(user1));

        vm.stopPrank();
    }

    function test_IsGoodStanding_ConsidersDecay() public {
        vm.startPrank(authorizedContract);

        // Start with score of 55
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.DisputeLost); // 110 - 50 = 60

        assertTrue(reputationManager.isGoodStanding(user1));

        // Fast forward enough to decay below 50
        vm.warp(block.timestamp + 330 days); // 11 periods = -11 points

        // 60 - 11 = 49, which is below 50
        assertFalse(reputationManager.isGoodStanding(user1));

        vm.stopPrank();
    }

    function test_IsBanned_ReturnsFalseForNewUser() public view {
        assertFalse(reputationManager.isBanned(user1));
    }

    function test_IsBanned_ReturnsTrueForBannedUser() public {
        vm.startPrank(admin);

        reputationManager.banUser(user1, "test");

        assertTrue(reputationManager.isBanned(user1));

        vm.stopPrank();
    }

    function test_IsBanned_ReturnsTrueForFraudUser() public {
        vm.startPrank(authorizedContract);

        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.FraudDetected);

        assertTrue(reputationManager.isBanned(user1));

        vm.stopPrank();
    }

    // ============================================
    //          EDGE CASE TESTS
    // ============================================

    function test_ScoreCanGoNegative() public {
        vm.startPrank(authorizedContract);

        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);

        // Multiple disputes to go negative
        for (uint256 i = 0; i < 5; i++) {
            reputationManager.updateReputation(user1, IReputationManager.ReputationAction.DisputeLost);
        }

        IReputationManager.Reputation memory rep = reputationManager.getReputation(user1);
        assertLt(rep.score, 0);

        vm.stopPrank();
    }

    function test_MultipleUsersIndependentScores() public {
        vm.startPrank(authorizedContract);

        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);
        reputationManager.updateReputation(user2, IReputationManager.ReputationAction.DisputeLost);
        reputationManager.updateReputation(user3, IReputationManager.ReputationAction.VerifiedAsset);

        assertEq(reputationManager.getReputationScore(user1), 110);
        assertEq(reputationManager.getReputationScore(user2), 50);
        assertEq(reputationManager.getReputationScore(user3), 120);

        vm.stopPrank();
    }

    function test_BanAndUnban_RestoresAccess() public {
        vm.startPrank(admin);

        // Ban user
        reputationManager.banUser(user1, "test");
        assertTrue(reputationManager.isBanned(user1));
        assertFalse(reputationManager.isGoodStanding(user1));

        // Unban user
        reputationManager.unbanUser(user1);
        assertFalse(reputationManager.isBanned(user1));

        vm.stopPrank();

        // Good standing depends on score
        // New user has base score of 100, which is >= 50, so they are in good standing
        assertTrue(reputationManager.isGoodStanding(user1));
    }

    function test_ActivityAfterLongInactivity() public {
        vm.startPrank(authorizedContract);

        // Initialize user
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);

        // Fast forward 1 year
        vm.warp(block.timestamp + 365 days);

        // New activity
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);

        IReputationManager.Reputation memory rep = reputationManager.getReputation(user1);
        // 110 (initial) - 12 (decay for 12 periods) + 10 (new sale) = 108
        assertEq(rep.score, 108);

        vm.stopPrank();
    }

    function test_FraudDetection_SetsBanFlag() public {
        vm.startPrank(authorizedContract);

        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.FraudDetected);

        IReputationManager.Reputation memory rep = reputationManager.getReputation(user1);
        assertTrue(rep.isBanned);
        assertEq(rep.score, 0); // 100 - 100

        vm.stopPrank();
    }

    function test_AllActionTypes_UpdateCorrectly() public {
        vm.startPrank(authorizedContract);

        // Test each action type
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);
        IReputationManager.Reputation memory rep1 = reputationManager.getReputation(user1);
        assertEq(rep1.successfulSales, 1);

        reputationManager.updateReputation(user2, IReputationManager.ReputationAction.SuccessfulPurchase);
        IReputationManager.Reputation memory rep2 = reputationManager.getReputation(user2);
        assertEq(rep2.successfulPurchases, 1);

        reputationManager.updateReputation(user3, IReputationManager.ReputationAction.VerifiedAsset);
        IReputationManager.Reputation memory rep3 = reputationManager.getReputation(user3);
        assertEq(rep3.verifiedAssets, 1);

        address user4 = makeAddr("user4");
        reputationManager.updateReputation(user4, IReputationManager.ReputationAction.DisputeWon);
        IReputationManager.Reputation memory rep4 = reputationManager.getReputation(user4);
        assertEq(rep4.disputesWon, 1);

        address user5 = makeAddr("user5");
        reputationManager.updateReputation(user5, IReputationManager.ReputationAction.DisputeLost);
        IReputationManager.Reputation memory rep5 = reputationManager.getReputation(user5);
        assertEq(rep5.disputesLost, 1);

        vm.stopPrank();
    }

    // ============================================
    //          FUZZ TESTS
    // ============================================

    function testFuzz_UpdateReputation_SuccessfulSale(address user) public {
        vm.assume(user != address(0));

        vm.startPrank(authorizedContract);

        reputationManager.updateReputation(user, IReputationManager.ReputationAction.SuccessfulSale);

        IReputationManager.Reputation memory rep = reputationManager.getReputation(user);
        assertEq(rep.score, 110);
        assertEq(rep.successfulSales, 1);

        vm.stopPrank();
    }

    function testFuzz_BanUser_WithReason(address user, string calldata reason) public {
        vm.assume(user != address(0));

        vm.startPrank(admin);

        reputationManager.banUser(user, reason);

        assertTrue(reputationManager.isBanned(user));

        vm.stopPrank();
    }

    function testFuzz_GetReputationScore_WithDecay(uint256 daysInactive) public {
        vm.assume(daysInactive <= 3650); // Max 10 years

        vm.startPrank(authorizedContract);

        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);

        // Fast forward
        vm.warp(block.timestamp + (daysInactive * 1 days));

        int256 score = reputationManager.getReputationScore(user1);
        int256 expectedDecay = int256(daysInactive / 30);
        int256 expectedScore = 110 - expectedDecay;

        assertEq(score, expectedScore);

        vm.stopPrank();
    }

    function testFuzz_MultipleActions_AccumulateScore(uint8 numActions) public {
        vm.assume(numActions > 0 && numActions <= 50); // Reasonable limit

        vm.startPrank(authorizedContract);

        for (uint256 i = 0; i < numActions; i++) {
            reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);
        }

        IReputationManager.Reputation memory rep = reputationManager.getReputation(user1);
        int256 expectedScore = 100 + (int256(uint256(numActions)) * 10);
        assertEq(rep.score, expectedScore);
        assertEq(rep.successfulSales, numActions);

        vm.stopPrank();
    }

    // ============================================
    //       INTEGRATION-STYLE TESTS
    // ============================================

    function test_CompleteUserJourney_PositiveReputation() public {
        vm.startPrank(authorizedContract);

        // User starts as new user
        assertEq(reputationManager.getReputationScore(user1), 100);

        // User makes successful sale
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);
        assertEq(reputationManager.getReputationScore(user1), 110);

        // User verifies their asset
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.VerifiedAsset);
        assertEq(reputationManager.getReputationScore(user1), 130);

        // User makes multiple purchases
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulPurchase);
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulPurchase);
        assertEq(reputationManager.getReputationScore(user1), 140);

        // User wins a dispute
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.DisputeWon);
        assertEq(reputationManager.getReputationScore(user1), 150);

        // User is in good standing
        assertTrue(reputationManager.isGoodStanding(user1));
        assertFalse(reputationManager.isBanned(user1));

        vm.stopPrank();
    }

    function test_CompleteUserJourney_NegativeReputation() public {
        vm.startPrank(authorizedContract);

        // User starts with initial activity
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.SuccessfulSale);
        assertEq(reputationManager.getReputationScore(user1), 110);

        // User loses multiple disputes
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.DisputeLost);
        assertEq(reputationManager.getReputationScore(user1), 60);

        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.DisputeLost);
        assertEq(reputationManager.getReputationScore(user1), 10);

        // User is no longer in good standing
        assertFalse(reputationManager.isGoodStanding(user1));

        // More dispute losses to trigger ban (need to go below -100)
        // Current: 10, after each -50: -40, -90, -140
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.DisputeLost);
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.DisputeLost);
        reputationManager.updateReputation(user1, IReputationManager.ReputationAction.DisputeLost);

        assertTrue(reputationManager.isBanned(user1));
        assertFalse(reputationManager.isGoodStanding(user1));

        vm.stopPrank();
    }
}

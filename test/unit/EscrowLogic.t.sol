// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {EscrowLogic} from "../../src/libraries/EscrowLogic.sol";
import {AssetTypes} from "../../src/libraries/AssetTypes.sol";
import {Errors} from "../../src/libraries/Errors.sol";

contract EscrowLogicWrapper {
    function validateMetadataURI(string memory uri) external view {
        this.validateMetadataURICalldata(uri);
    }

    function validateMetadataURICalldata(string calldata uri) external pure {
        EscrowLogic.validateMetadataURI(uri);
    }
}

contract EscrowLogicTest is Test {
    EscrowLogicWrapper public wrapper;
    address buyer = address(0x1);
    address seller = address(0x2);

    function setUp() public {
        wrapper = new EscrowLogicWrapper();
        // Set timestamp to a reasonable value to avoid underflow
        vm.warp(30 days);
    }

    // ============ validateEscrowParams Tests ============

    function test_ValidateEscrowParams_Success() public pure {
        EscrowLogic.validateEscrowParams(address(0x1), address(0x2), 1 ether, 7 days);
    }

    // Note: Cannot test pure library function reverts with vm.expectRevert
    // The validation logic is tested indirectly through EscrowManager contract tests

    // ============ validateHash Tests ============

    function test_ValidateHash_Success() public pure {
        EscrowLogic.validateHash(keccak256("test"));
    }

    // Note: Cannot test pure library function reverts with vm.expectRevert

    // ============ validateMetadataURI Tests ============

    function test_ValidateMetadataURI_Success() public view {
        wrapper.validateMetadataURI("ipfs://test");
    }

    function test_ValidateMetadataURI_RevertEmpty() public {
        vm.expectRevert(abi.encodeWithSelector(Errors.EmptyString.selector, "metadataURI"));
        wrapper.validateMetadataURI("");
    }

    function test_ValidateMetadataURI_RevertTooLong() public {
        bytes memory longBytes = new bytes(257);
        for (uint256 i = 0; i < 257; i++) {
            longBytes[i] = "a";
        }
        string memory longURI = string(longBytes);

        vm.expectRevert(abi.encodeWithSelector(Errors.StringTooLong.selector, 257, 256));
        wrapper.validateMetadataURI(longURI);
    }

    // ============ calculateDeadlines Tests ============

    function test_CalculateDeadlines_Basic() public view {
        uint256 duration = 14 days;

        (uint256 releaseTime, uint256 verificationDeadline, uint256 disputeDeadline) =
            EscrowLogic.calculateDeadlines(duration);

        assertEq(releaseTime, block.timestamp + duration);
        assertEq(verificationDeadline, block.timestamp + (duration / 2));
        assertEq(disputeDeadline, releaseTime + 7 days);
    }

    function test_CalculateDeadlines_ShortDuration() public view {
        uint256 duration = 1 days;

        (uint256 releaseTime, uint256 verificationDeadline, uint256 disputeDeadline) =
            EscrowLogic.calculateDeadlines(duration);

        assertEq(releaseTime, block.timestamp + 1 days);
        assertEq(verificationDeadline, block.timestamp + 12 hours);
        assertEq(disputeDeadline, releaseTime + 7 days);
    }

    // ============ calculateReleaseTime Tests ============

    function test_CalculateReleaseTime() public pure {
        uint256 createdAt = 1000;
        uint256 duration = 7 days;

        uint256 releaseTime = EscrowLogic.calculateReleaseTime(createdAt, duration);

        assertEq(releaseTime, createdAt + duration);
    }

    // ============ canRelease Tests ============

    function test_CanRelease_BuyerConfirmed() public view {
        bool buyerConfirmed = true;
        bool sellerDelivered = false;
        uint256 releaseTime = block.timestamp + 1 days;

        assertTrue(EscrowLogic.canRelease(buyerConfirmed, sellerDelivered, releaseTime));
    }

    function test_CanRelease_AutoReleaseAfterDeadline() public view {
        bool buyerConfirmed = false;
        bool sellerDelivered = true;
        uint256 releaseTime = block.timestamp - 1;

        assertTrue(EscrowLogic.canRelease(buyerConfirmed, sellerDelivered, releaseTime));
    }

    function test_CanRelease_NotYet() public view {
        bool buyerConfirmed = false;
        bool sellerDelivered = true;
        uint256 releaseTime = block.timestamp + 1 days;

        assertFalse(EscrowLogic.canRelease(buyerConfirmed, sellerDelivered, releaseTime));
    }

    function test_CanRelease_NotDelivered() public view {
        bool buyerConfirmed = false;
        bool sellerDelivered = false;
        uint256 releaseTime = block.timestamp - 1;

        assertFalse(EscrowLogic.canRelease(buyerConfirmed, sellerDelivered, releaseTime));
    }

    // ============ isReleaseOverdue Tests ============

    function test_IsReleaseOverdue_True() public view {
        bool sellerDelivered = true;
        uint256 releaseTime = block.timestamp - 1;

        assertTrue(EscrowLogic.isReleaseOverdue(sellerDelivered, releaseTime));
    }

    function test_IsReleaseOverdue_False_NotDelivered() public view {
        bool sellerDelivered = false;
        uint256 releaseTime = block.timestamp - 1;

        assertFalse(EscrowLogic.isReleaseOverdue(sellerDelivered, releaseTime));
    }

    function test_IsReleaseOverdue_False_NotYet() public view {
        bool sellerDelivered = true;
        uint256 releaseTime = block.timestamp + 1 days;

        assertFalse(EscrowLogic.isReleaseOverdue(sellerDelivered, releaseTime));
    }

    // ============ timeUntilRelease Tests ============

    function test_TimeUntilRelease_Future() public view {
        uint256 releaseTime = block.timestamp + 7 days;

        uint256 remaining = EscrowLogic.timeUntilRelease(releaseTime);

        assertEq(remaining, 7 days);
    }

    function test_TimeUntilRelease_Past() public view {
        uint256 releaseTime = block.timestamp - 1 days;

        uint256 remaining = EscrowLogic.timeUntilRelease(releaseTime);

        assertEq(remaining, 0);
    }

    function test_TimeUntilRelease_Now() public view {
        uint256 releaseTime = block.timestamp;

        uint256 remaining = EscrowLogic.timeUntilRelease(releaseTime);

        assertEq(remaining, 0);
    }

    // ============ canCancel Tests ============

    function test_CanCancel_True() public pure {
        bool sellerDelivered = false;
        address caller = address(0x1);
        address buyerAddr = address(0x1);

        assertTrue(EscrowLogic.canCancel(sellerDelivered, caller, buyerAddr));
    }

    function test_CanCancel_False_NotBuyer() public pure {
        bool sellerDelivered = false;
        address caller = address(0x2);
        address buyerAddr = address(0x1);

        assertFalse(EscrowLogic.canCancel(sellerDelivered, caller, buyerAddr));
    }

    function test_CanCancel_False_AlreadyDelivered() public pure {
        bool sellerDelivered = true;
        address caller = address(0x1);
        address buyerAddr = address(0x1);

        assertFalse(EscrowLogic.canCancel(sellerDelivered, caller, buyerAddr));
    }

    // ============ calculateCancellationFees Tests ============

    function test_CalculateCancellationFees_NotDelivered() public pure {
        uint256 amount = 1 ether;
        bool sellerDelivered = false;

        (uint256 buyerRefund, uint256 sellerCompensation) =
            EscrowLogic.calculateCancellationFees(amount, sellerDelivered);

        assertEq(buyerRefund, 1 ether);
        assertEq(sellerCompensation, 0);
    }

    function test_CalculateCancellationFees_Delivered() public pure {
        uint256 amount = 1 ether;
        bool sellerDelivered = true;

        (uint256 buyerRefund, uint256 sellerCompensation) =
            EscrowLogic.calculateCancellationFees(amount, sellerDelivered);

        uint256 expectedCompensation = (amount * AssetTypes.CANCELLATION_PENALTY_BPS) / AssetTypes.BPS_DENOMINATOR;
        assertEq(sellerCompensation, expectedCompensation);
        assertEq(buyerRefund, amount - expectedCompensation);
    }

    // ============ canOpenDispute Tests ============

    function test_CanOpenDispute_Active() public view {
        AssetTypes.EscrowState state = AssetTypes.EscrowState.Active;
        uint256 disputeDeadline = block.timestamp + 1 days;

        assertTrue(EscrowLogic.canOpenDispute(state, disputeDeadline));
    }

    function test_CanOpenDispute_Delivered() public view {
        AssetTypes.EscrowState state = AssetTypes.EscrowState.Delivered;
        uint256 disputeDeadline = block.timestamp + 1 days;

        assertTrue(EscrowLogic.canOpenDispute(state, disputeDeadline));
    }

    function test_CanOpenDispute_False_WrongState() public view {
        AssetTypes.EscrowState state = AssetTypes.EscrowState.Completed;
        uint256 disputeDeadline = block.timestamp + 1 days;

        assertFalse(EscrowLogic.canOpenDispute(state, disputeDeadline));
    }

    function test_CanOpenDispute_False_DeadlinePassed() public view {
        AssetTypes.EscrowState state = AssetTypes.EscrowState.Active;
        uint256 disputeDeadline = block.timestamp - 1;

        assertFalse(EscrowLogic.canOpenDispute(state, disputeDeadline));
    }

    // ============ canCallerDispute Tests ============

    function test_CanCallerDispute_Buyer() public pure {
        assertTrue(EscrowLogic.canCallerDispute(address(0x1), address(0x1), address(0x2)));
    }

    function test_CanCallerDispute_Seller() public pure {
        assertTrue(EscrowLogic.canCallerDispute(address(0x2), address(0x1), address(0x2)));
    }

    function test_CanCallerDispute_False() public pure {
        address other = address(0x3);
        assertFalse(EscrowLogic.canCallerDispute(other, address(0x1), address(0x2)));
    }

    // ============ escrowAgeInDays Tests ============

    function test_EscrowAgeInDays_Zero() public view {
        uint256 createdAt = block.timestamp;

        assertEq(EscrowLogic.escrowAgeInDays(createdAt), 0);
    }

    function test_EscrowAgeInDays_OneDayAgo() public view {
        uint256 createdAt = block.timestamp - 1 days;

        assertEq(EscrowLogic.escrowAgeInDays(createdAt), 1);
    }

    function test_EscrowAgeInDays_SevenDaysAgo() public view {
        uint256 createdAt = block.timestamp - 7 days;

        assertEq(EscrowLogic.escrowAgeInDays(createdAt), 7);
    }

    function test_EscrowAgeInDays_Future() public view {
        uint256 createdAt = block.timestamp + 1 days;

        assertEq(EscrowLogic.escrowAgeInDays(createdAt), 0);
    }

    // ============ escrowProgress Tests ============

    function test_EscrowProgress_Zero() public view {
        uint256 createdAt = block.timestamp;
        uint256 duration = 7 days;

        assertEq(EscrowLogic.escrowProgress(createdAt, duration), 0);
    }

    function test_EscrowProgress_Fifty() public view {
        uint256 createdAt = block.timestamp - 7 days;
        uint256 duration = 14 days;

        uint256 progress = EscrowLogic.escrowProgress(createdAt, duration);

        assertEq(progress, 5000); // 50% = 5000 bps
    }

    function test_EscrowProgress_Complete() public view {
        uint256 createdAt = block.timestamp - 7 days;
        uint256 duration = 7 days;

        uint256 progress = EscrowLogic.escrowProgress(createdAt, duration);

        assertEq(progress, AssetTypes.BPS_DENOMINATOR); // 100%
    }

    function test_EscrowProgress_Overtime() public view {
        uint256 createdAt = block.timestamp - 14 days;
        uint256 duration = 7 days;

        uint256 progress = EscrowLogic.escrowProgress(createdAt, duration);

        assertEq(progress, AssetTypes.BPS_DENOMINATOR); // Capped at 100%
    }

    function test_EscrowProgress_Future() public view {
        uint256 createdAt = block.timestamp + 1 days;
        uint256 duration = 7 days;

        assertEq(EscrowLogic.escrowProgress(createdAt, duration), 0);
    }

    // ============ isInVerificationPeriod Tests ============

    function test_IsInVerificationPeriod_True() public view {
        uint256 verificationDeadline = block.timestamp + 1 days;

        assertTrue(EscrowLogic.isInVerificationPeriod(verificationDeadline));
    }

    function test_IsInVerificationPeriod_AtDeadline() public view {
        uint256 verificationDeadline = block.timestamp;

        assertTrue(EscrowLogic.isInVerificationPeriod(verificationDeadline));
    }

    function test_IsInVerificationPeriod_False() public view {
        uint256 verificationDeadline = block.timestamp - 1;

        assertFalse(EscrowLogic.isInVerificationPeriod(verificationDeadline));
    }

    // ============ hasVerificationPeriodEnded Tests ============

    function test_HasVerificationPeriodEnded_True() public view {
        uint256 verificationDeadline = block.timestamp - 1;

        assertTrue(EscrowLogic.hasVerificationPeriodEnded(verificationDeadline));
    }

    function test_HasVerificationPeriodEnded_False() public view {
        uint256 verificationDeadline = block.timestamp + 1 days;

        assertFalse(EscrowLogic.hasVerificationPeriodEnded(verificationDeadline));
    }

    function test_HasVerificationPeriodEnded_AtDeadline() public view {
        uint256 verificationDeadline = block.timestamp;

        assertFalse(EscrowLogic.hasVerificationPeriodEnded(verificationDeadline));
    }

    // ============ generateEscrowId Tests ============

    function test_GenerateEscrowId_Deterministic() public pure {
        uint256 counter = 1;

        bytes32 id1 = EscrowLogic.generateEscrowId(counter, address(0x1), address(0x2));
        bytes32 id2 = EscrowLogic.generateEscrowId(counter, address(0x1), address(0x2));

        assertEq(id1, id2);
    }

    function test_GenerateEscrowId_Unique() public pure {
        bytes32 id1 = EscrowLogic.generateEscrowId(1, address(0x1), address(0x2));
        bytes32 id2 = EscrowLogic.generateEscrowId(2, address(0x1), address(0x2));

        assertTrue(id1 != id2);
    }

    // ============ isTerminalState Tests ============

    function test_IsTerminalState_Completed() public pure {
        assertTrue(EscrowLogic.isTerminalState(AssetTypes.EscrowState.Completed));
    }

    function test_IsTerminalState_Cancelled() public pure {
        assertTrue(EscrowLogic.isTerminalState(AssetTypes.EscrowState.Cancelled));
    }

    function test_IsTerminalState_Refunded() public pure {
        assertTrue(EscrowLogic.isTerminalState(AssetTypes.EscrowState.Refunded));
    }

    function test_IsTerminalState_Active() public pure {
        assertFalse(EscrowLogic.isTerminalState(AssetTypes.EscrowState.Active));
    }

    function test_IsTerminalState_Disputed() public pure {
        assertFalse(EscrowLogic.isTerminalState(AssetTypes.EscrowState.Disputed));
    }

    // ============ isActiveState Tests ============

    function test_IsActiveState_Active() public pure {
        assertTrue(EscrowLogic.isActiveState(AssetTypes.EscrowState.Active));
    }

    function test_IsActiveState_Delivered() public pure {
        assertTrue(EscrowLogic.isActiveState(AssetTypes.EscrowState.Delivered));
    }

    function test_IsActiveState_Completed() public pure {
        assertFalse(EscrowLogic.isActiveState(AssetTypes.EscrowState.Completed));
    }

    function test_IsActiveState_Disputed() public pure {
        assertFalse(EscrowLogic.isActiveState(AssetTypes.EscrowState.Disputed));
    }

    // ============ isReasonableAmount Tests ============

    function test_IsReasonableAmount_SocialMedia() public pure {
        assertTrue(EscrowLogic.isReasonableAmount(1 ether, AssetTypes.AssetType.SocialMediaTwitter));
        assertTrue(EscrowLogic.isReasonableAmount(10_000 ether, AssetTypes.AssetType.SocialMediaInstagram));
    }

    function test_IsReasonableAmount_SocialMedia_TooHigh() public pure {
        assertFalse(EscrowLogic.isReasonableAmount(10_001 ether, AssetTypes.AssetType.SocialMediaTwitter));
    }

    function test_IsReasonableAmount_Website() public pure {
        assertTrue(EscrowLogic.isReasonableAmount(1 ether, AssetTypes.AssetType.Website));
        assertTrue(EscrowLogic.isReasonableAmount(50_000 ether, AssetTypes.AssetType.Website));
    }

    function test_IsReasonableAmount_Website_TooHigh() public pure {
        assertFalse(EscrowLogic.isReasonableAmount(50_001 ether, AssetTypes.AssetType.Website));
    }

    function test_IsReasonableAmount_TooLow() public pure {
        assertFalse(EscrowLogic.isReasonableAmount(0.0001 ether, AssetTypes.AssetType.SocialMediaTwitter));
    }

    function test_IsReasonableAmount_MaxForSocialMedia() public pure {
        // For social media, max is 10k ETH
        assertTrue(EscrowLogic.isReasonableAmount(10_000 ether, AssetTypes.AssetType.SocialMediaTwitter));

        // Exceeding max should fail
        assertFalse(EscrowLogic.isReasonableAmount(10_001 ether, AssetTypes.AssetType.SocialMediaTwitter));
    }

    // ============ Integration Tests ============

    function test_Integration_FullEscrowLifecycle() public {
        // Validate params
        uint256 amount = 1 ether;
        uint256 duration = 7 days;
        EscrowLogic.validateEscrowParams(buyer, seller, amount, duration);

        // Calculate deadlines
        (uint256 releaseTime, uint256 verificationDeadline, uint256 disputeDeadline) =
            EscrowLogic.calculateDeadlines(duration);

        // Check initial state
        assertTrue(EscrowLogic.isInVerificationPeriod(verificationDeadline));
        assertFalse(EscrowLogic.canRelease(false, false, releaseTime));

        // Simulate seller delivery
        bool sellerDelivered = true;

        // Check can still cancel before delivery
        assertTrue(EscrowLogic.canCancel(false, buyer, buyer));
        assertFalse(EscrowLogic.canCancel(sellerDelivered, buyer, buyer));

        // Check dispute can be opened
        assertTrue(EscrowLogic.canOpenDispute(AssetTypes.EscrowState.Active, disputeDeadline));
        assertTrue(EscrowLogic.canCallerDispute(buyer, buyer, seller));

        // Fast forward to release time
        vm.warp(releaseTime);

        // Check auto-release conditions
        assertTrue(EscrowLogic.canRelease(false, sellerDelivered, releaseTime));
        assertTrue(EscrowLogic.isReleaseOverdue(sellerDelivered, releaseTime));
        assertEq(EscrowLogic.timeUntilRelease(releaseTime), 0);
    }

    function test_Integration_CancellationScenarios() public pure {
        uint256 amount = 1 ether;

        // Scenario 1: Cancel before delivery
        (uint256 refund1, uint256 comp1) = EscrowLogic.calculateCancellationFees(amount, false);
        assertEq(refund1, amount);
        assertEq(comp1, 0);

        // Scenario 2: Cancel after delivery
        (uint256 refund2, uint256 comp2) = EscrowLogic.calculateCancellationFees(amount, true);
        assertTrue(refund2 < amount);
        assertTrue(comp2 > 0);
        assertEq(refund2 + comp2, amount);
    }
}

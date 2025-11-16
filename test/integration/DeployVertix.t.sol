// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployVertix} from "../../script/DeployVertix.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DeployVertixTest is Test {
    DeployVertix deployer;
    HelperConfig helperConfig;

    function setUp() public {
        deployer = new DeployVertix();
        helperConfig = new HelperConfig();
    }

    function test_DeploymentSucceeds() public {
        DeployVertix.DeployedContracts memory contracts = deployer.run();

        assertFalse(address(contracts.roleManager) == address(0));
        assertFalse(address(contracts.feeDistributor) == address(0));
        assertFalse(address(contracts.verificationRegistry) == address(0));
        assertFalse(address(contracts.reputationManager) == address(0));
        assertFalse(address(contracts.escrowManager) == address(0));
        assertFalse(address(contracts.marketplaceCore) == address(0));
        assertFalse(address(contracts.nftMarketplace) == address(0));
        assertFalse(address(contracts.nftFactory) == address(0));
        assertFalse(address(contracts.offerManager) == address(0));
        assertFalse(address(contracts.auctionManager) == address(0));
    }

    function test_RoleManagerHasCorrectAdmin() public {
        DeployVertix.DeployedContracts memory contracts = deployer.run();
        (address admin,,,) = helperConfig.activeNetworkConfig();

        assertTrue(contracts.roleManager.hasRole(contracts.roleManager.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_NFTMarketplacePointsToMarketplaceCore() public {
        DeployVertix.DeployedContracts memory contracts = deployer.run();

        assertEq(contracts.nftMarketplace.marketplaceCore(), address(contracts.marketplaceCore));
    }

    function test_MarketplaceCoreReferencesCorrectContracts() public {
        DeployVertix.DeployedContracts memory contracts = deployer.run();

        assertEq(address(contracts.marketplaceCore.escrowManager()), address(contracts.escrowManager));
        assertEq(address(contracts.marketplaceCore.nftMarketplace()), address(contracts.nftMarketplace));
        assertEq(address(contracts.marketplaceCore.roleManager()), address(contracts.roleManager));
    }

    function test_FeeDistributorHasCorrectConfig() public {
        DeployVertix.DeployedContracts memory contracts = deployer.run();
        (, address feeCollector, uint256 platformFeeBps,) = helperConfig.activeNetworkConfig();

        assertEq(contracts.feeDistributor.feeCollector(), feeCollector);
        assertEq(contracts.feeDistributor.platformFeeBps(), platformFeeBps);
    }

    function test_OfferManagerReferencesCorrectContracts() public {
        DeployVertix.DeployedContracts memory contracts = deployer.run();

        assertEq(address(contracts.offerManager.roleManager()), address(contracts.roleManager));
        assertEq(address(contracts.offerManager.feeDistributor()), address(contracts.feeDistributor));
        assertEq(address(contracts.offerManager.marketplace()), address(contracts.marketplaceCore));
        assertEq(address(contracts.offerManager.escrowManager()), address(contracts.escrowManager));
    }

    function test_AuctionManagerReferencesCorrectContracts() public {
        DeployVertix.DeployedContracts memory contracts = deployer.run();

        assertEq(address(contracts.auctionManager.roleManager()), address(contracts.roleManager));
        assertEq(address(contracts.auctionManager.feeDistributor()), address(contracts.feeDistributor));
        assertEq(address(contracts.auctionManager.escrowManager()), address(contracts.escrowManager));
    }

    function test_AllContractsHaveSameRoleManager() public {
        DeployVertix.DeployedContracts memory contracts = deployer.run();

        address roleManager = address(contracts.roleManager);

        assertEq(address(contracts.verificationRegistry.roleManager()), roleManager);
        assertEq(address(contracts.reputationManager.roleManager()), roleManager);
        assertEq(address(contracts.escrowManager.roleManager()), roleManager);
        assertEq(address(contracts.marketplaceCore.roleManager()), roleManager);
        assertEq(address(contracts.nftFactory.roleManager()), roleManager);
        assertEq(address(contracts.offerManager.roleManager()), roleManager);
        assertEq(address(contracts.auctionManager.roleManager()), roleManager);
    }

    function test_HelperConfig_AnvilConfig() public {
        HelperConfig config = new HelperConfig();
        (address admin, address feeCollector, uint256 platformFeeBps, uint256 deployerKey) =
            config.activeNetworkConfig();

        assertFalse(admin == address(0));
        assertFalse(feeCollector == address(0));
        assertEq(platformFeeBps, 250);
        assertEq(deployerKey, config.DEFAULT_ANVIL_PRIVATE_KEY());
    }
}

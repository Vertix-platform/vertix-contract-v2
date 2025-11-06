// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/access/RoleManager.sol";
import "../src/core/FeeDistributor.sol";
import "../src/escrow/EscrowManager.sol";
import "../src/nft/NFTFactory.sol";
import "../src/nft/NFTMarketplace.sol";
import "../src/verification/VerificationRegistry.sol";
import "../src/verification/ReputationManager.sol";
import "../src/core/MarketplaceCore.sol";
import "../src/libraries/AssetTypes.sol";

/**
 * @title DeployVertix
 * @notice Deployment script for Vertix marketplace contracts
 * @dev Deploy in correct order respecting dependencies
 *
 * Usage:
 * forge script script/DeployVertix.s.sol:DeployVertix --rpc-url <RPC_URL> --broadcast --verify
 */
contract DeployVertix is Script {
    // Deployment addresses (will be populated during deployment)
    address public roleManager;
    address public feeDistributor;
    address public escrowManager;
    address public nftFactory;
    address public nftMarketplace;
    address public verificationRegistry;
    address public reputationManager;
    address public marketplaceCore;

    // Configuration
    uint256 public constant PLATFORM_FEE_BPS = 250; // 2.5%
    address public feeCollector;
    address public deployer;

    function run() external {
        // Get deployer from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        // Fee collector (can be changed later)
        feeCollector = deployer; // Initially deployer, update later

        console.log("Deploying Vertix Marketplace...");
        console.log("Deployer:", deployer);
        console.log("Network:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        // ============================================
        // 1. DEPLOY ACCESS CONTROL
        // ============================================
        console.log("\n1. Deploying RoleManager...");
        roleManager = address(new RoleManager(deployer));
        console.log("   RoleManager deployed at:", roleManager);

        // ============================================
        // 2. DEPLOY FEE DISTRIBUTOR
        // ============================================
        console.log("\n2. Deploying FeeDistributor...");
        feeDistributor = address(new FeeDistributor(roleManager, feeCollector, PLATFORM_FEE_BPS));
        console.log("   FeeDistributor deployed at:", feeDistributor);

        // ============================================
        // 3. DEPLOY ESCROW MANAGER
        // ============================================
        console.log("\n3. Deploying EscrowManager...");
        escrowManager = address(new EscrowManager(roleManager, feeDistributor, PLATFORM_FEE_BPS));
        console.log("   EscrowManager deployed at:", escrowManager);

        // ============================================
        // 4. DEPLOY NFT FACTORY
        // ============================================
        console.log("\n4. Deploying NFTFactory...");
        nftFactory = address(new NFTFactory(roleManager));
        console.log("   NFTFactory deployed at:", nftFactory);

        // ============================================
        // 5. DEPLOY NFT MARKETPLACE
        // ============================================
        console.log("\n5. Deploying NFTMarketplace...");
        nftMarketplace = address(new NFTMarketplace(roleManager, feeDistributor, PLATFORM_FEE_BPS));
        console.log("   NFTMarketplace deployed at:", nftMarketplace);

        // ============================================
        // 6. DEPLOY VERIFICATION REGISTRY
        // ============================================
        console.log("\n6. Deploying VerificationRegistry...");
        verificationRegistry = address(new VerificationRegistry(roleManager));
        console.log("   VerificationRegistry deployed at:", verificationRegistry);

        // ============================================
        // 7. DEPLOY REPUTATION MANAGER
        // ============================================
        console.log("\n7. Deploying ReputationManager...");
        reputationManager = address(new ReputationManager(roleManager));
        console.log("   ReputationManager deployed at:", reputationManager);

        // ============================================
        // 8. DEPLOY MARKETPLACE CORE
        // ============================================
        console.log("\n8. Deploying MarketplaceCore...");
        marketplaceCore = address(new MarketplaceCore(roleManager, escrowManager, nftMarketplace));
        console.log("   MarketplaceCore deployed at:", marketplaceCore);

        vm.stopBroadcast();

        // ============================================
        // PRINT DEPLOYMENT SUMMARY
        // ============================================
        console.log("\n" "========================================");
        console.log("VERTIX MARKETPLACE DEPLOYMENT COMPLETE");
        console.log("========================================");
        console.log("RoleManager:", roleManager);
        console.log("FeeDistributor:", feeDistributor);
        console.log("EscrowManager:", escrowManager);
        console.log("NFTFactory:", nftFactory);
        console.log("NFTMarketplace:", nftMarketplace);
        console.log("VerificationRegistry:", verificationRegistry);
        console.log("ReputationManager:", reputationManager);
        console.log("MarketplaceCore:", marketplaceCore);
        console.log("========================================");
        console.log("\nPlatform Fee:", PLATFORM_FEE_BPS, "bps (2.5%)");
        console.log("Fee Collector:", feeCollector);
        console.log("\n All contracts deployed successfully!");
        console.log("\nNext Steps:");
        console.log("1. Verify contracts on block explorer");
        console.log("2. Add backend service as VERIFIER_ROLE");
        console.log("3. Update fee collector if needed");
        console.log("4. Test basic functionality");
        console.log("5. Transfer admin to multi-sig wallet");
    }
}

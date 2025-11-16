// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {RoleManager} from "../src/access/RoleManager.sol";
import {FeeDistributor} from "../src/core/FeeDistributor.sol";
import {VerificationRegistry} from "../src/verification/VerificationRegistry.sol";
import {ReputationManager} from "../src/verification/ReputationManager.sol";
import {EscrowManager} from "../src/escrow/EscrowManager.sol";
import {MarketplaceCore} from "../src/core/MarketplaceCore.sol";
import {NFTMarketplace} from "../src/nft/NFTMarketplace.sol";
import {NFTFactory} from "../src/nft/NFTFactory.sol";
import {OfferManager} from "../src/core/OfferManager.sol";
import {AuctionManager} from "../src/core/AuctionManager.sol";

contract DeployVertix is Script {
    struct DeployedContracts {
        RoleManager roleManager;
        FeeDistributor feeDistributor;
        VerificationRegistry verificationRegistry;
        ReputationManager reputationManager;
        EscrowManager escrowManager;
        MarketplaceCore marketplaceCore;
        NFTMarketplace nftMarketplace;
        NFTFactory nftFactory;
        OfferManager offerManager;
        AuctionManager auctionManager;
    }

    function run() external returns (DeployedContracts memory) {
        HelperConfig helperConfig = new HelperConfig();
        (address admin, address feeCollector, uint256 platformFeeBps, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);

        RoleManager roleManager = new RoleManager(admin);

        FeeDistributor feeDistributor = new FeeDistributor(address(roleManager), feeCollector, platformFeeBps);

        VerificationRegistry verificationRegistry = new VerificationRegistry(address(roleManager));

        ReputationManager reputationManager = new ReputationManager(address(roleManager));

        EscrowManager escrowManager = new EscrowManager(address(roleManager), address(feeDistributor), platformFeeBps);

        NFTFactory nftFactory = new NFTFactory(address(roleManager));

        address futureMarketplaceCore =
            vm.computeCreateAddress(vm.addr(deployerKey), vm.getNonce(vm.addr(deployerKey)) + 1);

        NFTMarketplace nftMarketplace =
            new NFTMarketplace(futureMarketplaceCore, address(feeDistributor), platformFeeBps);

        MarketplaceCore marketplaceCore =
            new MarketplaceCore(address(roleManager), address(escrowManager), address(nftMarketplace));

        OfferManager offerManager = new OfferManager(
            address(roleManager),
            address(feeDistributor),
            address(marketplaceCore),
            address(escrowManager),
            platformFeeBps
        );

        AuctionManager auctionManager =
            new AuctionManager(address(roleManager), address(feeDistributor), address(escrowManager), platformFeeBps);

        vm.stopBroadcast();

        return DeployedContracts({
            roleManager: roleManager,
            feeDistributor: feeDistributor,
            verificationRegistry: verificationRegistry,
            reputationManager: reputationManager,
            escrowManager: escrowManager,
            marketplaceCore: marketplaceCore,
            nftMarketplace: nftMarketplace,
            nftFactory: nftFactory,
            offerManager: offerManager,
            auctionManager: auctionManager
        });
    }
}

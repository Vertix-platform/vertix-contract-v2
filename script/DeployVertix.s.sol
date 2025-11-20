// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {RoleManager} from "../src/access/RoleManager.sol";
import {FeeDistributor} from "../src/core/FeeDistributor.sol";
import {VerificationRegistry} from "../src/verification/VerificationRegistry.sol";
import {ReputationManager} from "../src/verification/ReputationManager.sol";
import {EscrowManager} from "../src/escrow/EscrowManager.sol";
import {MarketplaceCore} from "../src/core/MarketplaceCore.sol";
import {NFTMarketplace} from "../src/nft/NFTMarketplace.sol";
import {NFTFactory} from "../src/nft/NFTFactory.sol";
import {VertixSinglesNFT721} from "../src/nft/VertixSinglesNFT721.sol";
import {VertixSinglesNFT1155} from "../src/nft/VertixSinglesNFT1155.sol";
import {SinglesNFTHelper} from "../src/nft/SinglesNFTHelper.sol";
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
        VertixSinglesNFT721 singlesNFT721;
        VertixSinglesNFT1155 singlesNFT1155;
        SinglesNFTHelper singlesHelper;
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

        // Deploy shared collections for single NFTs (industry-standard approach)
        VertixSinglesNFT721 singlesNFT721 = new VertixSinglesNFT721();
        singlesNFT721.initialize("Vertix Singles", "VSINGLE", admin);

        VertixSinglesNFT1155 singlesNFT1155 = new VertixSinglesNFT1155();
        singlesNFT1155.initialize("Vertix Editions", "VEDITION", "", admin);

        address futureMarketplaceCore =
            vm.computeCreateAddress(vm.addr(deployerKey), vm.getNonce(vm.addr(deployerKey)) + 2);

        SinglesNFTHelper singlesHelper =
            new SinglesNFTHelper(address(singlesNFT721), address(singlesNFT1155), futureMarketplaceCore);

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

        roleManager.scheduleRoleGrant(roleManager.ARBITRATOR_ROLE(), admin);
        roleManager.scheduleRoleGrant(roleManager.VERIFIER_ROLE(), admin);

        escrowManager.addAuthorizedMarketplace(address(marketplaceCore));
        escrowManager.addAuthorizedMarketplace(address(offerManager));
        escrowManager.addAuthorizedMarketplace(address(auctionManager));

        marketplaceCore.addAuthorizedCaller(address(offerManager));

        verificationRegistry.addVerifier(admin);

        reputationManager.addAuthorizedContract(address(escrowManager));
        reputationManager.addAuthorizedContract(address(marketplaceCore));

        vm.stopBroadcast();

        console.log("Deployed Addresses:");
        console.log("RoleManager:", address(roleManager));
        console.log("FeeDistributor:", address(feeDistributor));
        console.log("VerificationRegistry:", address(verificationRegistry));
        console.log("ReputationManager:", address(reputationManager));
        console.log("EscrowManager:", address(escrowManager));
        console.log("NFTFactory:", address(nftFactory));
        console.log("  NFT721 Implementation:", nftFactory.nft721Implementation());
        console.log("  NFT1155 Implementation:", nftFactory.nft1155Implementation());
        console.log("VertixSinglesNFT721 (Shared Collection):", address(singlesNFT721));
        console.log("VertixSinglesNFT1155 (Shared Editions):", address(singlesNFT1155));
        console.log("SinglesNFTHelper (Mint & List Helper):", address(singlesHelper));
        console.log("NFTMarketplace:", address(nftMarketplace));
        console.log("MarketplaceCore:", address(marketplaceCore));
        console.log("OfferManager:", address(offerManager));
        console.log("AuctionManager:", address(auctionManager));

        return DeployedContracts({
            roleManager: roleManager,
            feeDistributor: feeDistributor,
            verificationRegistry: verificationRegistry,
            reputationManager: reputationManager,
            escrowManager: escrowManager,
            marketplaceCore: marketplaceCore,
            nftMarketplace: nftMarketplace,
            nftFactory: nftFactory,
            singlesNFT721: singlesNFT721,
            singlesNFT1155: singlesNFT1155,
            singlesHelper: singlesHelper,
            offerManager: offerManager,
            auctionManager: auctionManager
        });
    }
}

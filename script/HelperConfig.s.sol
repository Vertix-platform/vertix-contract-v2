// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    error HelperConfig__PrivateKeyNotSet();

    struct NetworkConfig {
        address admin;
        address feeCollector;
        uint256 platformFeeBps;
        uint256 deployerKey;
    }

    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 public constant DEFAULT_PLATFORM_FEE_BPS = 250; // 2.5%

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 8453) {
            activeNetworkConfig = getBaseMainnetConfig();
        } else if (block.chainid == 84_532) {
            activeNetworkConfig = getBaseSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getBaseMainnetConfig() public view returns (NetworkConfig memory) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        if (deployerKey == 0) {
            revert HelperConfig__PrivateKeyNotSet();
        }
        return NetworkConfig({
            admin: vm.envAddress("ADMIN_ADDRESS"),
            feeCollector: vm.envAddress("FEE_COLLECTOR_ADDRESS"),
            platformFeeBps: DEFAULT_PLATFORM_FEE_BPS,
            deployerKey: deployerKey
        });
    }

    function getBaseSepoliaConfig() public view returns (NetworkConfig memory) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        if (deployerKey == 0) {
            revert HelperConfig__PrivateKeyNotSet();
        }
        return NetworkConfig({
            admin: vm.envAddress("ADMIN_ADDRESS"),
            feeCollector: vm.envAddress("FEE_COLLECTOR_ADDRESS"),
            platformFeeBps: DEFAULT_PLATFORM_FEE_BPS,
            deployerKey: deployerKey
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.admin != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast(DEFAULT_ANVIL_PRIVATE_KEY);
        address admin = vm.addr(DEFAULT_ANVIL_PRIVATE_KEY);
        address feeCollector = makeAddr("feeCollector");
        vm.stopBroadcast();

        return NetworkConfig({
            admin: admin,
            feeCollector: feeCollector,
            platformFeeBps: DEFAULT_PLATFORM_FEE_BPS,
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }
}

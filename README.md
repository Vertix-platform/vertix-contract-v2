# Vertix Contract

Smart contracts powering the Vertix decentralized marketplace for digital assets.

## What is Vertix?

Vertix is a decentralized marketplace where people can buy and sell digital assets securely. Unlike traditional online marketplaces, Vertix uses blockchain technology to ensure transparent, trustless transactions without relying on a central authority.

### What Can You Buy and Sell on Vertix?

- **NFTs (Digital Collectibles)**: Unique digital items like art, music, or collectibles
- **Social Media Accounts**: Verified social media profiles with established followers
- **Gaming Accounts**: Accounts from popular games with progress, items, or achievements
- **Websites and Domains**: Digital properties with existing traffic or value
- Etc

## How Does It Work?

### For Non-Technical Users

Think of Vertix as an online marketplace with built-in security features:

1. **Escrow Protection**: When you buy something, your payment is held safely in escrow (like a digital safe) until you receive what you purchased. This protects both buyers and sellers.

2. **Verification System**: Digital assets are verified before sale to ensure authenticity. For example, social media accounts are checked to confirm ownership.

3. **Smart Contracts**: These are like automated agreements that execute themselves when conditions are met. No middleman needed - the code handles everything fairly and transparently.

4. **Transparent Fees**: A small 2.5% platform fee is charged on sales. Creators can also earn royalties on resales of their items.

5. **Blockchain Security**: All transactions are recorded on the blockchain (a permanent, transparent ledger), making them secure and tamper-proof.

### Why Blockchain?

- **Trustless**: You don't need to trust the other person or a company - the smart contract ensures fair execution
- **Transparent**: All transactions are publicly visible on the blockchain
- **Permanent**: Once recorded, transaction history cannot be altered or deleted
- **Decentralized**: No single company controls the marketplace
- **Lower Fees**: By removing intermediaries, costs are reduced

## Technical Overview

### Architecture

Vertix is built on Ethereum-compatible blockchains (Base and Polygon*) using Solidity smart contracts. The system is designed with security, gas efficiency, and modularity as top priorities.

## Getting Started

### Installation

Clone the repository and install dependencies:

```shell
git clone https://github.com/Vertix-platform/vertix-contract-v2
cd vertix-contract-v2
forge install
```

### Build

Compile all smart contracts:

```shell
forge build
```

### Test

Run the complete test suite:

```shell
forge test
```

Run tests with detailed output:

```shell
forge test -vvv
```

Run tests with gas reporting:

```shell
forge test --gas-report
```

Run specific test file:

```shell
forge test --match-path test/unit/MarketplaceCore.t.sol
```

### Code Formatting

Format all Solidity files:

```shell
forge fmt
```

Check formatting without changes:

```shell
forge fmt --check
```

## Project Structure

```
src/
├── access/         # Access control and role management
├── core/           # Core marketplace functionality
├── escrow/         # Escrow contracts
├── interfaces/     # Contract interfaces
├── libraries/      # Shared libraries
├── nft/            # NFT implementations (ERC-721, ERC-1155)
└── verification/   # Verification logic
```

## Design Principles

### Security First
Every contract follows security best practices:
- OpenZeppelin's battle-tested libraries
- Reentrancy guards on all fund transfers
- Comprehensive input validation
- Emergency pause functionality
- Extensive test coverage

### Gas Optimization
Designed for cost-efficient transactions:
- Optimized storage layout
- Batch operations support
- Efficient data structures
- Minimal on-chain storage

### Modularity
Clean separation of concerns:
- Interface-driven design
- Loosely coupled components
- Reusable libraries
- Easy to test and maintain

## Fee Structure

- **Platform Fee**: 2.5% (250 basis points) on all sales
- **Creator Royalties**: Configurable per NFT collection (standard is 5-10%)
- **Gas Fees**: Paid by transaction initiator (standard blockchain cost)

Fees are automatically calculated and distributed by the FeeDistributor contract.

## Supported Asset Types

1. **NFTs**: Full ERC-721 and ERC-1155 support with royalties
2. **Social Media Accounts**: Hash-based verification with transfer locks
3. **Gaming Accounts**: Verified through platform-specific proofs
4. **Websites**: Domain ownership verification

## Testing Philosophy

We maintain high test coverage (90%+) with:

- **Unit Tests**: Test individual functions in isolation
- **Integration Tests**: Test complete user workflows
- **Fuzz Tests**: Test with random inputs to find edge cases
- **Invariant Tests**: Verify system properties always hold true

Example test naming convention:
- `test_createListing_Success()` - Happy path
- `test_createListing_RevertIf_UnauthorizedSeller()` - Error case

## Contributing

When contributing to this project:

1. Follow the existing code style and structure
2. Write comprehensive tests for new features
3. Add NatSpec documentation to all public functions
4. Ensure all tests pass before submitting
5. Run gas optimization checks
6. Update this README if adding major features

## License

MIT License

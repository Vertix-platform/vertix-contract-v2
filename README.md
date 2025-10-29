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

### Core Components

#### 1. Escrow System (`src/escrow/`)
Handles secure holding of funds during transactions. All sales go through escrow to protect both parties:
- Configurable timelock periods
- Auto-release mechanism when conditions are met
- Dispute freezing capability
- Partial refund support
- Complete state transition tracking

#### 2. NFT Contracts (`src/nft/`)
Implementation of digital collectibles following industry standards:
- **VertixNFT721**: Standard NFTs (one-of-a-kind items)
- **VertixNFT1155**: Multi-edition NFTs (multiple copies of same item)
- Built-in royalty support (ERC-2981)
- Metadata storage for item details
- Transfer locks for pending sales

#### 3. Marketplace Core (`src/core/`)
The central marketplace logic:
- **MarketplaceCore**: Listing creation, sale execution, and order management
- **FeeDistributor**: Handles platform fees and creator royalties
- Support for fixed-price sales, auctions, and offers
- Integration with escrow for secure transactions

#### 4. Access Control (`src/access/`)
Manages permissions and roles:
- **RoleManager**: Controls who can perform administrative actions
- Multi-level permission system
- Secure ownership transfer mechanisms

#### 5. Verification System (`src/verification/`)
Ensures asset authenticity:
- On-chain verification hash storage
- Expiring verifications for time-sensitive assets
- Authorized verifier whitelist
- Verification event logging for transparency

#### 6. Shared Libraries (`src/libraries/`)
Reusable code components for common operations:
- Asset type handling (NFT, social accounts, gaming accounts, websites)
- Fee calculations
- Data validation utilities

### Security Features

- **Reentrancy Protection**: Prevents exploits where attackers recursively call functions
- **Access Controls**: Role-based permissions ensure only authorized actions
- **Input Validation**: All user inputs are checked for validity
- **Safe Fund Transfers**: Uses latest best practices for ETH and token transfers
- **Emergency Pause**: Marketplace can be paused in case of security issues
- **Comprehensive Testing**: Over 90% test coverage with unit, integration, and fuzz tests

### Technical Specifications

- **Solidity Version**: 0.8.20
- **Framework**: Foundry (modern Ethereum development toolkit)
- **Libraries**: OpenZeppelin Contracts v5.x (industry-standard security)
- **Token Standards**: ERC-721, ERC-1155, ERC-2981
- **Networks**: Polygon (low fees, fast), Base (Coinbase's L2)
- **Fee Structure**: 2.5% platform fee + optional creator royalties

## Getting Started

### Prerequisites

Install Foundry, the Ethereum development toolkit:

```shell
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

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

## Deployment

### Testnet Deployment

Deploy to Polygon Mumbai or Base Sepolia testnet:

```shell
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url <TESTNET_RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --broadcast \
  --verify
```

### Mainnet Deployment

Deploy to production networks:

```shell
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url <MAINNET_RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --broadcast \
  --verify \
  --slow
```

Always test thoroughly on testnet before mainnet deployment.

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

### Upgradeability Strategy
Designed for long-term sustainability:
- Modular architecture allows component replacement
- Storage separation for future upgrades
- Clear upgrade paths documented
- Can add new features without disrupting existing functionality

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

## Development Workflow

1. **Write Code**: Create or modify contracts in `src/`
2. **Write Tests**: Add corresponding tests in `test/`
3. **Format**: Run `forge fmt` to format code
4. **Test**: Run `forge test` to verify functionality
5. **Gas Check**: Run `forge test --gas-report` to optimize
6. **Deploy**: Use deployment scripts in `script/`

## Testing Philosophy

We maintain high test coverage (90%+) with:

- **Unit Tests**: Test individual functions in isolation
- **Integration Tests**: Test complete user workflows
- **Fuzz Tests**: Test with random inputs to find edge cases
- **Invariant Tests**: Verify system properties always hold true

Example test naming convention:
- `test_createListing_Success()` - Happy path
- `test_createListing_RevertIf_UnauthorizedSeller()` - Error case

## Additional Resources

- [Foundry Book](https://book.getfoundry.sh/) - Complete Foundry documentation
- [Solidity Docs](https://docs.soliditylang.org/) - Solidity language reference
- [OpenZeppelin](https://docs.openzeppelin.com/contracts/) - Security library documentation
- [ERC Standards](https://eips.ethereum.org/erc) - Ethereum token standards

## Contributing

When contributing to this project:

1. Follow the existing code style and structure
2. Write comprehensive tests for new features
3. Add NatSpec documentation to all public functions
4. Ensure all tests pass before submitting
5. Run gas optimization checks
6. Update this README if adding major features

## Security

Security is our top priority. This codebase follows:

- Industry-standard security practices
- OpenZeppelin's security guidelines
- Regular security audits (before mainnet launch)
- Bug bounty program (post-launch)

If you discover a security vulnerability, please report it responsibly to the development team.

## License

MIT License

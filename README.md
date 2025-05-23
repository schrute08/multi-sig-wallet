# multisig-wallet

A secure, upgradeable multi-signature wallet for Ethereum, supporting up to 25 owners, with integrated ERC20 and Chainlink VRF functionality. Built with Foundry and Hardhat.

## Features

- **MultiSig Wallet:**  
  - Up to 25 owners, with customizable approval requirements.
  - Owners can submit, approve, and execute transactions (ETH or ERC20).
  - Upgradeable via UUPS proxy pattern.
  - Integrated with a Chainlink VRF oracle for randomness.
- **ERC20 Token:**  
  - Simple mintable ERC20 token for testing and demonstration.
- **Chainlink Oracle:**  
  - Chainlink VRF integration for secure randomness (configured for Sepolia testnet).

## Contracts

- `MultiSigWallet.sol`:  
  The main contract. Allows multiple owners to collectively manage funds and approve transactions. Supports both ETH and ERC20 transfers. Includes upgradeability and integrates with Chainlink VRF for randomness.

- `Token.sol`:  
  A basic ERC20 token with a public mint function, used for testing wallet functionality.

- `ChainlinkOracle.sol`:  
  A contract that requests and receives random numbers from Chainlink VRF. Used by the wallet for secure randomness.

## Project Structure

```
contracts/
  MultiSigWallet.sol
  Token.sol
  ChainlinkOracle.sol
test/
  MultiSigWallet.t.sol
lib/
  forge-std/         # Forge standard library (as a git submodule)
foundry.toml         # Foundry configuration
hardhat.config.ts    # Hardhat configuration
```

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Node.js](https://nodejs.org/)
- [Hardhat](https://hardhat.org/)

### Installation

1. Clone the repository:
   ```sh
   git clone <repo-url>
   cd multisig-wallet
   ```

2. Initialize submodules:
   ```sh
   git submodule update --init --recursive
   ```

3. Install Node dependencies:
   ```sh
   npm install
   ```

### Configuration

- Copy `.env.example` to `.env` and fill in any required environment variables (e.g., Chainlink subscription ID for VRF).

### Compile Contracts

```sh
forge build
```

or with Hardhat:

```sh
npx hardhat compile
```

### Running Tests

```sh
forge test
```

## Usage

- Deploy the `MultiSigWallet` contract, specifying the owners, required approvals, ERC20 token address, and Chainlink Oracle address.
- Owners can submit transactions, approve them, and execute once the required number of approvals is reached.
- The wallet supports both ETH and ERC20 transfers.
- The Chainlink Oracle can be used to request secure random numbers.

## Test Coverage

- The test suite (`test/MultiSigWallet.t.sol`) covers:
  - Initialization and setup
  - Submitting, approving, and executing transactions (ETH and ERC20)
  - Access control and error handling
  - Edge cases (zero value, invalid addresses, duplicate owners, etc.)

## License

MIT
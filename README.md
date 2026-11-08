![DeFi Integrations](.github/banner.jpg)

## DeFi Integrations

A playground of example smart contract integrations across DeFi protocols — Aave v4, Morpho Midnight, Zama's Confidential Token Standard, and ERC-3643 permissioned tokens.

## 👻 Aave v4 — Liquidation Protection Manager

This repository contains example of a Position Manager contract called [`LiquidationProtectionManager`](https://github.com/CJ42/aave-v4-contracts-playground/blob/main/src/LiquidationProtectionManager.sol) that allows users to protect their position from being liquidated.

### Features

- Inherits [`PositionManagerBase`](https://github.com/aave/aave-v4/blob/main/src/position-manager/PositionManagerBase.sol) from Aave v4 to re-use pre-built Position Manager functionalities, such as registering spokes and setting the Position Manager contract for the user.
- Implement `HealthFactor` as user-defined value type for type safety over `uint256` primitive type.
- Implement multiple features from latest Solidity 0.8.x releases, such as free functions, import aliases, or operator aliases for user-defined value types.
- Mainnet fork tests against **Main Spoke** on Ethereum mainnet.

## 🦋 Morpho Midnight — Fixed-Term Position Manager

See [`contracts/morpho-midnight`](./contracts/morpho-midnight) for an example integration with [Morpho Midnight](https://docs.morpho.org/learn/concepts/midnight/), Morpho's fixed-rate, fixed-term lending protocol. Bound to the Midnight deployment on Base and tested on a **Base mainnet fork** against live markets (`cd contracts/morpho-midnight && forge test`).

## 👁️‍🗨️ Zama — Wrapped Confidential Token (ERC-7984)

See [`contracts/zama-confidential-token`](./contracts/zama-confidential-token) for an example ERC-20 wrapper built on [Zama's FHEVM](https://docs.zama.org/protocol/protocol/overview) implementing [ERC-7984](https://www.zama.org/post/erc-7984-the-confidential-token-standard-explained), the confidential token standard.

## 🦖 ERC-3643 (T-REX) — Tokenized Stock

See [`contracts/erc3643-rwa-token`](./contracts/erc3643-rwa-token) for a real-world-asset example: a tokenized share class on the official [ERC-3643](https://eips.ethereum.org/EIPS/eip-3643) T-REX contracts, with accredited-investor claims, a country allowlist and a Rule 144 holding period (`cd contracts/erc3643-rwa-token && forge test`).

## Table of Contents

- [Install dependencies](#install-dependencies)
  - [Usage](#usage)
    - [Build](#build)
    - [Run Mainnet Fork Tests](#run-mainnet-fork-tests)

## Requirements

- Foundry

Install or update Foundry:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

## Initial Setup

### Install dependencies

Git submodules (`lib/`) and Soldeer packages (`dependencies/`, used for Zama's FHEVM library which is only published to npm and Soldeer):

```bash
forge install
forge soldeer install
```

<!-- Update the `.env` file with the correct values.

- `RPC_URL` – RPC endpoint (Tenderly Virtual TestNet or public network).
- `SPOKE_ADDRESS` – Aave v4 spoke (e.g. Core on Ethereum mainnet: `0x89914a22E30CDf88A06e801E407ca82520210a79`).
- `RESERVE_ID` – Reserve identifier (e.g. `4` for USDC on Core).
- `PRIVATE_KEY` – Optional deployer key used by scripts (keep it secret).
- `TENDERLY_ACCESS_KEY` – Tenderly access token for verification. -->

## Usage

### Build

```shell
forge build
```

### Run Mainnet Fork Tests

```shell
forge test
```

<!-- ### Deploy

```shell
forge script script/Deploy_ReserveUtilization.s.sol:DeployReserveUtilization \
  --rpc-url <RPC_URL> \
  --broadcast
```

### Verify

#### Tenderly Virtual TestNet

```shell
forge verify-contract \
  <DEPLOYED_ADDRESS> \
  src/ReserveUtilization.sol:ReserveUtilization \
  --verifier-url <RPC_URL>/verify/etherscan \
  --etherscan-api-key <TENDERLY_ACCESS_KEY> \
  --watch
```

#### Etherscan (Public Networks)

```shell
forge verify-contract \
  <DEPLOYED_ADDRESS> \
  src/ReserveUtilization.sol:ReserveUtilization \
  --chain <CHAIN_ID> \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

## License

Aave v4 Foundry Boilerplate [MIT licensed](./LICENSE) -->

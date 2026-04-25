## Aave v4 Position Managers

This repository contains a minimal boilerplate for developing smart contracts that integrate with Aave v4 using [Foundry](https://book.getfoundry.sh/).

## Table of Contents <!-- omit in toc -->

- [Install dependencies](#install-dependencies)
  - [Usage](#usage)
    - [Build](#build)
    - [Test](#test)

## Requirements

- Foundry

Install or update Foundry:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

## Initial Setup

# Install dependencies

```bash
forge install
```

<!-- Create a `.env` file copying the `.env.example` file: -->

Create a `.env` file:

```bash
# User address to fetch positions from
USER=0x
```

```bash
cp .env.example .env
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

### Test

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

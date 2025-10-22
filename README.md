## Aave v4 Foundry Boilerplate

This repository contains a minimal boilerplate for developing smart contracts that integrate with Aave v4 using [Foundry](https://book.getfoundry.sh/).

## Table of Contents <!-- omit in toc -->

- [Requirements](#requirements)
- [Initial Setup](#initial-setup)
- [Usage](#usage)
- [License](#license)

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

Create a `.env` file copying the `.env.example` file:

```bash
cp .env.example .env
```

Update the `.env` file with the correct values.

- `RPC_URL` – RPC endpoint.
- `SPOKE_ADDRESS` – Aave v4 spoke (e.g. Core on Ethereum mainnet: `0x89914a22E30CDf88A06e801E407ca82520210a79`).
- `RESERVE_ID` – Reserve identifier (e.g. `4` for USDC on Core).
- `PRIVATE_KEY` – Optional deployer key used by scripts (keep it secret).

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
forge test
```

### Deploy

```shell
forge script script/Deploy_ReserveUtilization.s.sol:DeployReserveUtilization \
  --rpc-url <RPC_URL> \
  --broadcast
```

### Verify

```shell
forge verify-contract \
  <DEPLOYED_ADDRESS> \
  src/ReserveUtilization.sol:ReserveUtilization \
  --chain <CHAIN_ID> \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

## License

Aave v4 Foundry Boilerplate [MIT licensed](./LICENSE)

# 🔐 Zama — Confidential ERC-20 Wrapper (ERC-7984)

[`ConfidentialERC20Wrapper`](./ConfidentialERC20Wrapper.sol) wraps any public ERC-20 into an [ERC-7984](https://www.zama.org/post/erc-7984-the-confidential-token-standard-explained) confidential token running on [Zama's FHEVM](https://docs.zama.org/protocol/protocol/overview). Balances and transfer amounts are stored as encrypted `euint64` handles and are never revealed on-chain.

## What it does

- **Wrap / unwrap** — inherits OpenZeppelin's `ERC7984ERC20Wrapper`:
  - `wrap(to, amount)` pulls the public ERC-20 and mints the same amount as an encrypted balance, scaled down to at most 6 decimals (see [Why 6 decimals](#why-6-decimals)).
  - `unwrap(from, to, encryptedAmount, inputProof)` burns an encrypted amount and makes it publicly decryptable.
  - `finalizeUnwrap(requestId, cleartext, decryptionProof)` verifies the KMS decryption signatures (`FHE.checkSignatures`) and releases the ERC-20.
- **Confidential transfers** — `confidentialTransfer(to, externalEuint64, inputProof)` and the rest of the ERC-7984 interface (operators, transfer-and-call, disclosure).
- **Encrypted transfer limits** — the owner can set a per-holder limit that stays encrypted:
  - `setTransferLimit(holder, externalEuint64, inputProof)` ingests a client-encrypted value via `FHE.fromExternal`, then grants decryption rights with `FHE.allowThis` / `FHE.allow` to the contract, the owner and the holder.
  - `_update` is overridden to compute `FHE.select(FHE.le(amount, limit), amount, 0)` homomorphically. Following ERC-7984 semantics, an over-limit transfer does not revert (that would leak the comparison result) — it silently transfers an encrypted zero.
  - Mints (wrap) and burns (unwrap) are never limited, so holders can always exit to the underlying token.
- Inherits `ZamaEthereumConfig` to point FHE operations at Zama's coprocessor contracts on Ethereum mainnet / Sepolia.

## Why 6 decimals

ERC-7984 balances are `euint64` handles, so the largest representable balance is `2^64 - 1 ≈ 1.8 × 10^19`. OpenZeppelin's `ERC7984ERC20Wrapper` therefore caps the wrapper at `_maxDecimals() = 6` decimals: an 18-decimal underlying is wrapped at `rate() = 10^12`, which keeps up to ~18 trillion whole tokens representable instead of overflowing past ~18 tokens. Underlyings with 6 decimals or fewer (USDC, USDT) are wrapped 1:1. The cap can be raised by overriding `_maxDecimals()` when the underlying's supply allows it.

## Dependencies

Installed at the root of the repository (see [`AGENTS.md`](../../AGENTS.md)):

| Package | Version | How |
| --- | --- | --- |
| [`@openzeppelin/confidential-contracts`](https://github.com/OpenZeppelin/openzeppelin-confidential-contracts) | `v0.5.3` | `forge install` → `lib/openzeppelin-confidential-contracts` |
| [`@openzeppelin/contracts`](https://github.com/OpenZeppelin/openzeppelin-contracts) | `v5.6.1` | `forge install` → `lib/openzeppelin-contracts` |
| [`@fhevm/solidity`](https://github.com/zama-ai/fhevm/tree/main/library-solidity) | `0.13.4` | `forge soldeer install` → `dependencies/@fhevm-solidity-0.13.4` |
| `encrypted-types` (dependency of `@fhevm/solidity`) | `0.0.4` | `forge soldeer install` → `dependencies/@encrypted-types-0.0.4` |

Zama only publishes the Solidity library to npm and [Soldeer](https://soldeer.xyz) (the standalone `zama-ai/fhevm-solidity` git repository is archived at `v0.7`, and the current sources live in the 200 MB `zama-ai/fhevm` monorepo), hence Soldeer rather than a git submodule for that one. The import prefixes are declared in the root [`remappings.txt`](../../remappings.txt).

Note that OpenZeppelin `main` has since moved `_update` to a 4-argument variant with a `bypassRestrictions` flag; this example targets the released `v0.5.3` API.

```bash
forge install
forge soldeer install
forge build contracts/zama-confidential-token/ConfidentialERC20Wrapper.sol
```

Running it end-to-end requires an FHEVM-enabled network (Sepolia / Ethereum with Zama's coprocessor) or a local FHEVM mock such as [`forge-fhevm`](https://github.com/zama-ai/forge-fhevm) or the `@fhevm/hardhat-plugin`.

## Sources

- Zama FHEVM monorepo (Solidity library in `library-solidity/`): https://github.com/zama-ai/fhevm
- `FHE.sol` API (`euint64`, `externalEuint64`, `FHE.fromExternal`, `FHE.le`, `FHE.select`, `FHE.allow`, `FHE.allowThis`): https://github.com/zama-ai/fhevm/blob/main/library-solidity/lib/FHE.sol
- OpenZeppelin Confidential Contracts (`ERC7984`, `ERC7984ERC20Wrapper`): https://github.com/OpenZeppelin/openzeppelin-confidential-contracts
- ERC-7984 explainer: https://www.zama.org/post/erc-7984-the-confidential-token-standard-explained
- Zama protocol docs: https://docs.zama.org/protocol/protocol/overview

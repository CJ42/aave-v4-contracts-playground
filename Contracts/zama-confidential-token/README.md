# 🔐 Zama — Confidential ERC-20 Wrapper (ERC-7984)

[`ConfidentialERC20Wrapper`](./ConfidentialERC20Wrapper.sol) wraps any public ERC-20 into an [ERC-7984](https://www.zama.org/post/erc-7984-the-confidential-token-standard-explained) confidential token running on [Zama's FHEVM](https://docs.zama.org/protocol/protocol/overview). Balances and transfer amounts are stored as encrypted `euint64` handles and are never revealed on-chain.

## What it does

- **Wrap / unwrap** — inherits OpenZeppelin's `ERC7984ERC20Wrapper`:
  - `wrap(to, amount)` pulls the public ERC-20 and mints the same amount (scaled to max 6 decimals) as an encrypted balance.
  - `unwrap(from, to, encryptedAmount, inputProof)` burns an encrypted amount and makes it publicly decryptable.
  - `finalizeUnwrap(requestId, cleartext, decryptionProof)` verifies the KMS decryption signatures (`FHE.checkSignatures`) and releases the ERC-20.
- **Confidential transfers** — `confidentialTransfer(to, externalEuint64, inputProof)` and the rest of the ERC-7984 interface (operators, transfer-and-call, disclosure).
- **Encrypted transfer limits** — the owner can set a per-holder limit that stays encrypted:
  - `setTransferLimit(holder, externalEuint64, inputProof)` ingests a client-encrypted value via `FHE.fromExternal`, then grants decryption rights with `FHE.allowThis` / `FHE.allow` to the contract, the owner and the holder.
  - `_update` is overridden to compute `FHE.select(FHE.le(amount, limit), amount, 0)` homomorphically. Following ERC-7984 semantics, an over-limit transfer does not revert (that would leak the comparison result) — it silently transfers an encrypted zero.
  - Mints (wrap) and burns (unwrap) are never limited, so holders can always exit to the underlying token.
- Inherits `ZamaEthereumConfig` to point FHE operations at Zama's coprocessor contracts on Ethereum mainnet / Sepolia.

## Dependencies

Written against **`@openzeppelin/confidential-contracts` v0.5.3** (latest release) and **`@fhevm/solidity` v0.13.x**. Note that OZ `main` has since moved `_update` to a 4-argument variant with a `bypassRestrictions` flag; this example targets the released API.

These dependencies are not installed in this repository and `Contracts/` is outside the Foundry `src` directory. To compile:

```bash
npm install --legacy-peer-deps \
  @openzeppelin/confidential-contracts@0.5.3 \
  @fhevm/solidity@0.13 \
  @openzeppelin/contracts@5.6.1
```

Then add to the remappings in `foundry.toml`:

```toml
"@openzeppelin/confidential-contracts/=node_modules/@openzeppelin/confidential-contracts/",
"@openzeppelin/contracts/=node_modules/@openzeppelin/contracts/",
"@fhevm/solidity/=node_modules/@fhevm/solidity/",
```

and build with `forge build Contracts/zama-confidential-token` (solc `0.8.28`, EVM `cancun` or later).

Running it end-to-end requires an FHEVM-enabled network (Sepolia / Ethereum with Zama's coprocessor) or a local FHEVM mock such as [`forge-fhevm`](https://github.com/zama-ai/forge-fhevm) or the `@fhevm/hardhat-plugin`.

## Sources

- Zama FHEVM monorepo (Solidity library in `library-solidity/`): https://github.com/zama-ai/fhevm
- `FHE.sol` API (`euint64`, `externalEuint64`, `FHE.fromExternal`, `FHE.le`, `FHE.select`, `FHE.allow`, `FHE.allowThis`): https://github.com/zama-ai/fhevm/blob/main/library-solidity/lib/FHE.sol
- OpenZeppelin Confidential Contracts (`ERC7984`, `ERC7984ERC20Wrapper`): https://github.com/OpenZeppelin/openzeppelin-confidential-contracts
- ERC-7984 explainer: https://www.zama.org/post/erc-7984-the-confidential-token-standard-explained
- Zama protocol docs: https://docs.zama.org/protocol/protocol/overview

# 🌙 Morpho Midnight — Fixed-Term Position Manager

[`FixedTermPositionManager`](./src/FixedTermPositionManager.sol) bundles common [Morpho Midnight](https://docs.morpho.org/learn/concepts/midnight/) flows into single transactions. Midnight is Morpho's fixed-rate, fixed-term lending protocol: lenders hold **credit** units and borrowers hold **debt** units, each settling 1 loan token at maturity. Rates come from the unit price `P` (`r = 1 / P - 1`), not from an interest rate model.

## What it does

| Function | Midnight calls | Notes |
| --- | --- | --- |
| `supplyCollateralAndBorrow` | `supplyCollateral` → `take` | Sells units into a lender's signed **buy** offer, at a fixed rate, with a `minBorrowedAssets` slippage guard. Collateral lands before Midnight's end-of-`take` health check. |
| `repayAndWithdraw` | `repay` → `withdrawCollateral` | `type(uint256).max` repays all debt / withdraws all collateral. |
| `redeem` | `withdraw` | Redeems credit 1:1, capped by the market's `withdrawable` liquidity. |
| `impliedRate` / `marketId` | — | APR from a unit price (`UnitPrice` user-defined value type) and the market id (upstream `IdLib`). |

Midnight nets a sale against existing credit first, so `supplyCollateralAndBorrow` with zero collateral also works as an **early exit for lenders**.

### Security model

- Users authorize the manager once: `midnight.setIsAuthorized(manager, true, user)`.
- Midnight authorization is all-or-nothing, so every entry point hard-codes `msg.sender` as `onBehalf` and receiver. A third party can only ever act on their own position (see `test_CannotTouchAnotherUsersPosition`).
- Stateless: tokens only transit within a call, and approvals to Midnight are for the exact amount pulled, so no balance or allowance is left behind (asserted after every flow).

## Build & test

This folder is a standalone Foundry project (`evm_version = "osaka"` + via-IR, as required by Midnight's deployed bytecode and its structs). It reuses the [`morpho-org/midnight`](https://github.com/morpho-org/midnight) submodule from the root `lib/` for interfaces and libraries only: no Midnight source is compiled, so the project does not pin a solc version.

```bash
git submodule update --init --recursive lib/midnight
cd contracts/morpho-midnight
forge test
```

The tests run on a **Base mainnet fork** (block `53478628`) against the live Midnight deployment, the live USDC market with WETH and USDC collateral maturing on 2026-12-25 ([`0x9489…c098`](https://api.morpho.org/v0/midnight/markets/0x9489f29b589b92d28733ab15135ce6d9c4b5e64413db4326956447a3de1fc098)), and the production `EcrecoverRatifier`. Lenders sign offers through the production EIP-712 offer-tree flow (single-offer tree: root = leaf, empty proof). Coverage: borrow (incl. fuzz), slippage, insufficient collateral, missing authorization, forged signatures, lender early exit, full repay + withdraw, unhealthy withdraw, redemption, third-party isolation, event payloads and the view helpers.

## Deployment

The manager is bound at compile time to Midnight on **Base** (`8453`): [`0xAdedD8ab6dE832766Fedf0FaC4992E5C4D3EA18A`](https://basescan.org/address/0xAdedD8ab6dE832766Fedf0FaC4992E5C4D3EA18A) (`MIDNIGHT_BASE_MAINNET` in [`Constants.sol`](./src/Constants.sol)), so there is nothing to configure at deployment. All Midnight deployments are listed on [Morpho's addresses page](https://docs.morpho.org/get-started/resources/addresses/). Live markets, books and takeable offers (with ratifier data) are served by `https://api.morpho.org/v0/midnight/*`.

## Sources

- Concepts: https://docs.morpho.org/learn/concepts/midnight/
- Integration guide: https://docs.morpho.org/developers/midnight/get-started/
- Code: https://github.com/morpho-org/midnight · [Whitepaper](https://morpho.org/whitepapers/midnight-whitepaper.pdf)

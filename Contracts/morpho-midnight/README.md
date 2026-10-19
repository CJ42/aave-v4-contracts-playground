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

This folder is a standalone Foundry project: Midnight pins `solc 0.8.34` + `osaka` + via-IR, which conflicts with the root project's `0.8.28` pin. It uses the [`morpho-org/midnight`](https://github.com/morpho-org/midnight) submodule (pinned at `ec91a91`) from the root `lib/`.

```bash
git submodule update --init --recursive lib/midnight
cd Contracts/morpho-midnight
forge test
```

The tests deploy the **real** `Midnight.sol` and `EcrecoverRatifier` locally, and lenders sign offers through the production EIP-712 offer-tree flow (single-offer tree: root = leaf, empty proof). That covers borrow (incl. fuzz), slippage, insufficient collateral, missing authorization, forged signatures, lender early exit, full repay + withdraw, unhealthy withdraw, redemption, third-party isolation and the view helpers.

## Deployment

Midnight lives on **Base** (`8453`) at [`0x2F7a3AA739ba5792Ce1b4eA046117f2C0095BCA6`](https://basescan.org/address/0x2F7a3AA739ba5792Ce1b4eA046117f2C0095BCA6). Live markets, books and takeable offers (with ratifier data) are served by `https://api.morpho.org/v0/midnight/*`.

## Sources

- Concepts: https://docs.morpho.org/learn/concepts/midnight/
- Integration guide: https://docs.morpho.org/developers/midnight/get-started/
- Code: https://github.com/morpho-org/midnight · [Whitepaper](https://morpho.org/whitepapers/midnight-whitepaper.pdf)

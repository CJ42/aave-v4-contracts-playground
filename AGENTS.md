# AGENTS.md

Conventions for this repository. They apply to every integration folder under `contracts/` and to the root Aave v4 project.

## Code style

- **Named arguments in calls with many parameters.** When a function call or an `emit` has more than three arguments, use the named-argument syntax so the intent of every value is readable at the call site:

  ```solidity
  (, borrowedAssets) = MIDNIGHT.take({
    offer: offer,
    ratifierData: ratifierData,
    units: units,
    taker: msg.sender,
    receiverIfTakerIsSeller: msg.sender,
    takerCallback: address(0),
    takerCallbackData: ''
  });

  emit Events.CollateralSuppliedAndBorrowed({user: msg.sender, id: id, /* ... */ borrowedAssets: borrowedAssets});
  ```

  The same applies to struct literals (`Market({chainId: ..., midnight: ...})`).

- **Errors and events live in their own files.** Each integration declares its custom errors in `Errors.sol` and its events in `Events.sol` as file-level declarations, and imports them through a namespace alias:

  ```solidity
  import * as Errors from './Errors.sol';
  import * as Events from './Events.sol';

  require(offer.buy, Errors.NotABuyOffer());
  emit Events.CreditRedeemed({user: msg.sender, id: id, loanToken: market.loanToken, units: redeemedUnits});
  ```

- **Events carry the token addresses** involved in a flow (loan token, collateral token), not only amounts and indexes.

- **Protocol addresses are constants**, not deployment parameters. Hardcode the mainnet address of the protocol an integration targets in a `Constants.sol` file, with a comment pointing to the source of the address (official docs or API).

## Dependencies

- **Every new integration folder must declare its dependencies at the root of the repository**, in two places:
  1. the dependency list: `forge install <org>/<repo>@<tag>` for git-hosted libraries (tracked in `.gitmodules` and `foundry.lock`), or `forge soldeer install <package>~<version>` for libraries only published to Soldeer / npm (tracked in `[dependencies]` of `foundry.toml` and `soldeer.lock`);
  2. the root `remappings.txt`, with the import prefix the integration's sources use.

  Never point a README at `node_modules` or ask the reader to install packages by hand.

- Integrations that cannot share the root compiler settings (for example Morpho Midnight, which needs `evm_version = "osaka"` and via-IR) are standalone Foundry projects inside their folder, with `libs = ["../../lib"]` so they reuse the root dependencies.

## Tests

- **Prefer mainnet fork tests** over local deployments of third-party protocols: fork the chain the integration targets (`[rpc_endpoints]` in the project's `foundry.toml`), pin a block number, and use the real token and protocol addresses. This keeps the project independent from the exact compiler version the protocol was built with.
- Assert the fork setup in `setUp` (market ids, protocol addresses) so a stale constant fails fast with a clear message.

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library EIP712TypesLocal {
  struct SetUserPositionManagers {
    address onBehalfOf;
    PositionManagerUpdate[] updates;
    uint256 nonce;
    uint256 deadline;
  }

  struct PositionManagerUpdate {
    address positionManager;
    bool approve;
  }
}

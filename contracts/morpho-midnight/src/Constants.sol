// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

uint256 constant WAD = 1e18;

/// @dev Morpho Midnight on Base mainnet (chain id 8453).
/// Source: https://docs.morpho.org/get-started/resources/addresses/ (Morpho Midnight → Base),
/// and the `midnight` field returned by https://api.morpho.org/v0/midnight/books for Base markets.
address constant MIDNIGHT_BASE_MAINNET = 0xAdedD8ab6dE832766Fedf0FaC4992E5C4D3EA18A;

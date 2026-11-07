// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @dev Price of one Midnight unit (a claim on 1 loan token at maturity), in WAD.
/// A price `P` implies a fixed rate of `1 / P - 1` over the remaining term.
type UnitPrice is uint256;

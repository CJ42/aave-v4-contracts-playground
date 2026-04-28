// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

type HealthFactor is uint256;

using {isBelow as <} for HealthFactor global;

function isBelow(
  HealthFactor healthFactor,
  HealthFactor threshold
) pure returns (bool) {
  return HealthFactor.unwrap(healthFactor) < HealthFactor.unwrap(threshold);
}

// struct ProtectionParams {
//   address user;
//   uint256 repayReserveId;
//   address repayToken;
//   uint256 repayAmount;
// }

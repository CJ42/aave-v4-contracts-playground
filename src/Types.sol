// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @dev This user-defined value types ensures type safety over the primitive type `uint256`.
/// Since struct members in Aave v4 often include `uint256` types, using a user-defined value type
/// here ensure that a variable representing a health factor cannot be mixed with other `uint256` types
/// and therefore assigned a wrong or unexpected value.
type HealthFactor is uint256;

using {isBelow as <} for HealthFactor global;

function isBelow(
  HealthFactor healthFactor,
  HealthFactor threshold
) pure returns (bool) {
  return HealthFactor.unwrap(healthFactor) < HealthFactor.unwrap(threshold);
}

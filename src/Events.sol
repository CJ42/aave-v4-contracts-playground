// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {HealthFactor} from './Types.sol';

/// @notice Emitted when funds are deposited
/// @param depositor The address that deposited the funds
/// @param token The token that was deposited
/// @param amount The amount deposited
event FundsDeposited(
  address indexed depositor,
  address indexed token,
  uint256 amount
);

/// @notice Emitted when funds are withdrawn
/// @param withdrawer The address that withdrew the funds
/// @param token The token that was withdrawn
/// @param amount The amount withdrawn
event FundsWithdrawn(
  address indexed withdrawer,
  address indexed token,
  uint256 amount
);

/// @notice Emitted when a protection action is executed
/// @param user The user whose position was protected
/// @param healthFactorBefore Health factor before the protection action
/// @param repayReserveId The reserve that was repaid
/// @param repayAmount The amount repaid
event ProtectionExecuted(
  address indexed user,
  HealthFactor healthFactorBefore,
  uint256 repayReserveId,
  uint256 repayAmount
);

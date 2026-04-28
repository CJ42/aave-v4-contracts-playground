// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {HealthFactor} from './Types.sol';

/// @notice Reverts when the requested amount is greater than the available balance
/// @param token The token that was requested
/// @param amount The amount that was requested
/// @param available The available balance
error InsufficientFunds(address token, uint256 amount, uint256 available);

/// @notice Reverts when depositing funds in the Position Manager fails
error DepositFailed();

/// @notice Reverts when the operator is not authorized to perform actions on the Position Manager
/// @param operator The address that was not authorized
error Unauthorized(address operator);

/// @notice Reverts when the available balance is insufficient
error InsufficientBalance();

/// @notice Reverts when withdrawing funds from the Position Manager fails
error WithdrawFailed();

/// @notice Reverts when the spoke is not registered in the Position Manager
/// @param spoke The address of the spoke that was not registered
error SpokeNotRegistered(address spoke);

/// @notice Reverts when the health factor is above the threshold
/// @param healthFactor The health factor that is above the threshold
/// @param threshold The threshold that the health factor is above
error HealthFactorAboveThreshold(
  HealthFactor healthFactor,
  HealthFactor threshold
);

/// @notice Reverts when there is no debt to repay
/// @param reserveId The reserve that was not repaid
error NoDebtToRepay(uint256 reserveId);

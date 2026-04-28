// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {HealthFactor} from './Types.sol';

error InsufficientFunds(address token, uint256 amount, uint256 available);

error DepositFailed();

error Unauthorized(address operator);

error InsufficientBalance();

error WithdrawFailed();

error SpokeNotRegistered(address spoke);

error HealthFactorAboveThreshold(
  HealthFactor healthFactor,
  HealthFactor threshold
);

error NoDebtToRepay(uint256 reserveId);

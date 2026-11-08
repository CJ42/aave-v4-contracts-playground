// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

/// @notice Reverts when configuring country code 0, which the registry returns for unregistered wallets
error InvalidCountry();

/// @notice Reverts when a holding period is above the module's safety cap
/// @param period The requested holding period, in seconds
/// @param maxPeriod The longest holding period the module accepts, in seconds
error HoldingPeriodTooLong(uint256 period, uint256 maxPeriod);

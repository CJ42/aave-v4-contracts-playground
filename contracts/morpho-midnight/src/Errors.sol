// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {UnitPrice} from './Types.sol';

/// @notice Reverts when `market.midnight` is not the Midnight instance this manager is bound to
/// @param expected The Midnight instance this manager is bound to
/// @param actual The Midnight address found in the market
error WrongMidnight(address expected, address actual);

/// @notice Reverts when borrowing against a sell offer (borrowers need a lender's buy offer)
error NotABuyOffer();

/// @notice Reverts when the loan tokens received are below the caller's slippage guard
/// @param minAssets The minimum amount of loan tokens the caller accepted
/// @param receivedAssets The amount of loan tokens the take actually paid out
error InsufficientBorrowedAssets(uint256 minAssets, uint256 receivedAssets);

/// @notice Reverts when there is no credit that can currently be redeemed
error NothingToRedeem();

/// @notice Reverts when a unit price is outside `(0, 1e18]`
/// @param price The invalid unit price
error InvalidUnitPrice(UnitPrice price);

/// @notice Reverts when computing an implied rate with no time left to maturity
error ZeroTimeToMaturity();

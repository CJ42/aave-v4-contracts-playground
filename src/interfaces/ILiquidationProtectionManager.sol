// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ISpoke} from 'aave-v4/src/spoke/interfaces/ISpoke.sol';
import {HealthFactor} from '../Types.sol';

interface ILiquidationProtectionManager {
  /// @notice Deposit funds that the manager can use to repay debt on your behalf
  /// @param token The ERC-20 token to deposit (should match your borrow asset)
  /// @param amount The amount to deposit
  function depositFunds(address token, uint256 amount) external;

  /// @notice Withdraw previously deposited funds
  function withdrawFunds(address token, uint256 amount) external;

  /// @notice Execute protection for a user by repaying part of their debt
  /// @dev Anyone can call this (keeper, bot, or the user themselves)
  /// @param spoke The spoke to execute a repayment on
  /// @param repayReserveId The reserve to repay (e.g., USDC)
  /// @param repayAmount The amount to repay
  function executeProtection(
    ISpoke spoke,
    uint256 repayReserveId,
    uint256 repayAmount
  ) external;

  /// @notice Check if a user's position needs protection
  /// @return needsProtection Whether the health factor is below threshold
  /// @return currentHealthFactor The current health factor
  function checkPosition(
    ISpoke spoke
  )
    external
    view
    returns (bool needsProtection, HealthFactor currentHealthFactor);
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// interfaces
import {IERC20} from 'aave-v4/src/dependencies/openzeppelin/IERC20.sol';
import {ISpoke} from 'aave-v4/src/spoke/interfaces/ISpoke.sol';
import {ILiquidationProtectionManager} from './interfaces/ILiquidationProtectionManager.sol';

// modules
import {PositionManagerBase} from 'aave-v4/src/position-manager/PositionManagerBase.sol';

// libs
import {WadRayMath} from 'aave-v4/src/libraries/math/WadRayMath.sol';
import './libraries/UserData.sol' as UserDataLib;
import './libraries/Reserves.sol' as ReservesLib;

using {UserDataLib.getHealthFactor} for ISpoke;
using {ReservesLib.getUnderlyingToken} for ISpoke;

// errors
import * as Errors from './Errors.sol';

// events
import {FundsDeposited, FundsWithdrawn, ProtectionExecuted} from './Events.sol';

// types
import './Types.sol';

/// @title LiquidationProtectionManager
/// @author Jean Cavallera (CJ42)
/// @notice A Position Manager for Aave v4 that protects users from liquidation
/// by automatically repaying debt when health factor drops below a threshold.
///
/// @dev Inherits {PositionManagerBase} to re-use convenience methods to interact with Spokes.
contract LiquidationProtectionManager is
  ILiquidationProtectionManager,
  PositionManagerBase
{
  /// @dev Health factor threshold below which protection triggers (in WAD, 1e18 = 1.0)
  HealthFactor public immutable HEALTH_FACTOR_THRESHOLD =
    HealthFactor.wrap(1 * WadRayMath.WAD);

  /// @dev Tracks funds deposited for repayment
  mapping(address token => uint256 amount) public protectionReserves;

  /// @dev Track operators allowed to execute operations on the Position Manager
  mapping(address operator => bool allowed) public operators;
  constructor(address user_) PositionManagerBase(user_) {}

  modifier onlyOperator() {
    require(operators[msg.sender], Errors.Unauthorized(msg.sender));
    _;
  }

  function depositFunds(address token, uint256 amount) external onlyOwner {
    bool deposited = IERC20(token).transferFrom(
      msg.sender,
      address(this),
      amount
    );
    require(deposited, Errors.DepositFailed());

    protectionReserves[token] += amount;
    emit FundsDeposited(msg.sender, token, amount);
  }

  function withdrawFunds(address token, uint256 amount) external onlyOwner {
    uint256 availableBalance = protectionReserves[token];
    require(availableBalance >= amount, Errors.InsufficientBalance());

    protectionReserves[token] -= amount;

    // Emit event first to avoid out-of-order event emission if function is called back
    emit FundsWithdrawn(msg.sender, token, amount);

    bool withdrawn = IERC20(token).transfer(msg.sender, amount);
    require(withdrawn, Errors.WithdrawFailed());
  }

  function registerOperator(address operator, bool allowed) external onlyOwner {
    operators[operator] = allowed;
  }

  /// @dev Anyone can call this (keeper, bot, or the user themselves)
  /// @param spoke The spoke to execute a repayment on
  /// @param repayReserveId The reserve to repay (e.g., USDC)
  /// @param repayAmount The amount to repay
  function executeProtection(
    ISpoke spoke,
    uint256 repayReserveId,
    uint256 repayAmount
  ) external onlyOperator onlyRegisteredSpoke(address(spoke)) {
    address user = owner();
    HealthFactor currentHealthFactor = spoke.getHealthFactor(user);

    require(
      currentHealthFactor < HEALTH_FACTOR_THRESHOLD,
      Errors.HealthFactorAboveThreshold(
        currentHealthFactor,
        HEALTH_FACTOR_THRESHOLD
      )
    );

    address underlyingToken = spoke.getUnderlyingToken(repayReserveId);

    // Check user has deposited enough funds
    uint256 available = protectionReserves[underlyingToken];
    if (available < repayAmount) {
      revert Errors.InsufficientFunds(underlyingToken, repayAmount, available);
    }

    uint256 userDebt = spoke.getUserTotalDebt(repayReserveId, user);
    if (userDebt == 0) {
      revert Errors.NoDebtToRepay(repayReserveId);
    }

    // Cap repayment at actual debt
    if (repayAmount > userDebt) {
      repayAmount = userDebt;
    }

    // Approve spoke to pull tokens and repay
    protectionReserves[user] -= repayAmount;
    IERC20(underlyingToken).approve(address(spoke), repayAmount);

    // emit event first to prevent out of order events if function is called back
    emit ProtectionExecuted({
      user: user,
      healthFactorBefore: currentHealthFactor,
      repayReserveId: repayReserveId,
      repayAmount: repayAmount
    });

    spoke.repay(repayReserveId, repayAmount, user);
  }

  function checkPosition(
    ISpoke spoke
  )
    external
    view
    returns (bool needsProtection, HealthFactor currentHealthFactor)
  {
    currentHealthFactor = spoke.getHealthFactor(owner());
    needsProtection = currentHealthFactor < HEALTH_FACTOR_THRESHOLD;
  }

  function _multicallEnabled() internal pure override returns (bool) {
    return true;
  }
}

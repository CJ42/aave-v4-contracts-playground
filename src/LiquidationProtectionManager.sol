// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// interfaces
import {IERC20} from 'aave-v4/src/dependencies/openzeppelin/IERC20.sol';
import {ILiquidationProtectionManager} from './interfaces/ILiquidationProtectionManager.sol';

// modules
import {PositionManagerBase} from 'aave-v4/src/position-manager/PositionManagerBase.sol';

// libs
import {WadRayMath} from 'aave-v4/src/libraries/math/WadRayMath.sol';

// errors
import * as Errors from './Errors.sol';

// events
import {FundsDeposited} from './Events.sol';

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
  uint256 public immutable HEALTH_FACTOR_THRESHOLD = 1 * WadRayMath.WAD;

  /// @dev Tracks funds deposited for repayment
  mapping(address token => uint256 amount) public protectionReserves;
  constructor(address user_) PositionManagerBase(user_) {}

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
    // TODO
  }

  function executeProtection(
    address user,
    uint256 repayReserveId,
    address repayToken,
    uint256 repayAmount
  ) external onlyOwner {
    // TODO
  }

  function checkPosition(
    address user
  ) external view returns (bool needsProtection, uint256 currentHealthFactor) {
    // TODO
  }

  function _multicallEnabled() internal pure override returns (bool) {
    return true;
  }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.x;

// interfaces
import {ISpoke} from 'aave-v4/src/spoke/interfaces/ISpoke.sol';

// types
import {HealthFactor} from '../Types.sol';

/**
 * @dev Helper functions to extract user data from Spoke contracts
 * See below copy struct from `ISpoke.sol`
 *
 * /// @notice User account data describing a user position and its health.
 * /// @dev riskPremium The risk premium of the user position, expressed in BPS.
 * /// @dev avgCollateralFactor The weighted average collateral factor of the user position, expressed in WAD.
 * /// @dev healthFactor The health factor of the user position, expressed in WAD. 1e18 represents a health factor of 1.00.
 * /// @dev totalCollateralValue The total collateral value of the user position, expressed in units of Value.
 * /// @dev totalDebtValueRay The total debt value of the user position, expressed in units of Value and scaled by RAY.
 * /// @dev activeCollateralCount The number of active collaterals, which includes reserves with `collateralFactor` > 0, `enabledAsCollateral` and `suppliedAmount` > 0.
 * /// @dev borrowCount The number of borrowed reserves of the user position.
 * struct UserAccountData {
 *   uint256 riskPremium;
 *   uint256 avgCollateralFactor;
 *   uint256 healthFactor;
 *   uint256 totalCollateralValue;
 *   uint256 totalDebtValueRay;
 *   uint256 activeCollateralCount;
 *   uint256 borrowCount;
 * }
 */

function getHealthFactor(
  ISpoke spoke,
  address user
) view returns (HealthFactor) {
  uint256 healthFactor = spoke.getUserAccountData(user).healthFactor;
  return HealthFactor.wrap(healthFactor);
}

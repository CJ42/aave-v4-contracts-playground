// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice Emitted when `user` supplied collateral and sold `units` of debt into a lender's buy offer
/// @param user The borrower (caller), who receives the loan tokens
/// @param id The Midnight market id
/// @param collateralToken The collateral token supplied
/// @param collateralIndex Index of `collateralToken` in the market's `collateralParams`
/// @param collateralAssets Collateral supplied (0 when borrowing against existing collateral)
/// @param loanToken The market's loan token, received by `user`
/// @param units Debt units sold, each repaying 1 loan token at maturity
/// @param borrowedAssets Loan tokens received by `user`
event CollateralSuppliedAndBorrowed(
  address indexed user,
  bytes32 indexed id,
  address collateralToken,
  uint256 collateralIndex,
  uint256 collateralAssets,
  address loanToken,
  uint256 units,
  uint256 borrowedAssets
);

/// @notice Emitted when `user` repaid debt and withdrew collateral
/// @param user The borrower (caller), who receives the collateral
/// @param id The Midnight market id
/// @param loanToken The market's loan token, pulled from `user` to repay
/// @param repaidUnits Debt units repaid
/// @param collateralToken The collateral token withdrawn
/// @param collateralIndex Index of `collateralToken` in the market's `collateralParams`
/// @param withdrawnAssets Collateral withdrawn to `user`
event RepaidAndWithdrawn(
  address indexed user,
  bytes32 indexed id,
  address loanToken,
  uint256 repaidUnits,
  address collateralToken,
  uint256 collateralIndex,
  uint256 withdrawnAssets
);

/// @notice Emitted when `user` redeemed credit units for loan tokens, 1:1
/// @param user The lender (caller), who receives the loan tokens
/// @param id The Midnight market id
/// @param loanToken The market's loan token, sent to `user`
/// @param units Credit units redeemed
event CreditRedeemed(address indexed user, bytes32 indexed id, address loanToken, uint256 units);

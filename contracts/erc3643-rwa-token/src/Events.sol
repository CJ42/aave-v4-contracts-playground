// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

/// @notice Events of the tokenized stock compliance modules.
/// @dev A library because T-REX pins solc 0.8.17 and file-level events require 0.8.22.
library Events {
  /// @notice Emitted when transfers to investors registered in `country` become allowed
  /// @param compliance The compliance contract the setting applies to
  /// @param country The ISO 3166-1 numeric country code
  event CountryAllowed(address indexed compliance, uint16 indexed country);

  /// @notice Emitted when transfers to investors registered in `country` stop being allowed
  /// @param compliance The compliance contract the setting applies to
  /// @param country The ISO 3166-1 numeric country code
  event CountryDisallowed(address indexed compliance, uint16 indexed country);

  /// @notice Emitted when the holding period applied to future mints changes
  /// @param compliance The compliance contract the setting applies to
  /// @param holdingPeriod The new holding period, in seconds
  event HoldingPeriodSet(address indexed compliance, uint256 holdingPeriod);

  /// @notice Emitted when newly minted shares become subject to a holding period
  /// @param compliance The compliance contract of the token
  /// @param token The share token
  /// @param wallet The wallet holding the locked shares
  /// @param amount The number of shares locked
  /// @param releaseTime The timestamp from which the shares can be transferred
  event SharesLocked(
    address indexed compliance, address indexed token, address indexed wallet, uint256 amount, uint256 releaseTime
  );

  /// @notice Emitted when an agent action moved or burned shares that were still locked
  /// @param compliance The compliance contract of the token
  /// @param token The share token
  /// @param from The wallet the locked shares left
  /// @param to The wallet now holding the lock, or `address(0)` when the shares were burned
  /// @param amount The number of locked shares concerned
  /// @param releaseTime The timestamp from which the shares can be transferred
  event LockMoved(
    address indexed compliance,
    address indexed token,
    address indexed from,
    address to,
    uint256 amount,
    uint256 releaseTime
  );
}

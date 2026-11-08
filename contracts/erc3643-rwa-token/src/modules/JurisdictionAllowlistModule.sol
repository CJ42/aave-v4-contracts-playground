// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

// interfaces
import {IModularCompliance} from '@erc3643org/erc-3643/contracts/compliance/modular/IModularCompliance.sol';
import {IToken} from '@erc3643org/erc-3643/contracts/token/IToken.sol';

// modules
import {
  AbstractModuleUpgradeable,
  IModule
} from '@erc3643org/erc-3643/contracts/compliance/modular/modules/AbstractModuleUpgradeable.sol';

// errors & events
import '../Errors.sol' as Errors;
import {Events} from '../Events.sol';

/// @title JurisdictionAllowlistModule
/// @notice ERC-3643 compliance module that only lets shares reach investors registered in an allowed country.
///
/// @dev Default-deny: a token holds no allowed country until its issuer lists one, so an offering
/// can never be open by omission when it enters a new market. The check reads the country the
/// agent recorded in the `IdentityRegistry`, and it applies to the receiver of a mint or transfer.
/// Sellers are deliberately not checked, so an investor who moved abroad can still exit.
///
/// One deployment can serve many tokens: every setting is keyed by compliance contract, and is
/// changed through `ModularCompliance.callModuleFunction`, which only the compliance owner can use.
contract JurisdictionAllowlistModule is AbstractModuleUpgradeable {
  /// @dev compliance contract => ISO 3166-1 numeric country code => allowed
  mapping(address => mapping(uint16 => bool)) private _allowedCountries;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes the module behind its proxy and makes the caller the upgrade owner.
  function initialize() external initializer {
    __AbstractModule_init();
  }

  /// @notice Allows transfers to investors registered in `_country`.
  /// @param _country The ISO 3166-1 numeric country code
  function allowCountry(uint16 _country) external onlyComplianceCall {
    _allowCountry(_country);
  }

  /// @notice Allows transfers to investors registered in any of `_countries`.
  /// @param _countries The ISO 3166-1 numeric country codes
  function batchAllowCountries(uint16[] calldata _countries) external onlyComplianceCall {
    for (uint256 i = 0; i < _countries.length; i++) {
      _allowCountry(_countries[i]);
    }
  }

  /// @notice Stops allowing transfers to investors registered in `_country`.
  /// @dev Holdings already in that country are untouched and can still be sold to an allowed investor.
  /// @param _country The ISO 3166-1 numeric country code
  function disallowCountry(uint16 _country) external onlyComplianceCall {
    _allowedCountries[msg.sender][_country] = false;
    emit Events.CountryDisallowed({compliance: msg.sender, country: _country});
  }

  /// @inheritdoc IModule
  // solhint-disable-next-line no-empty-blocks
  function moduleTransferAction(address, address, uint256) external override onlyComplianceCall {}

  /// @inheritdoc IModule
  // solhint-disable-next-line no-empty-blocks
  function moduleMintAction(address, uint256) external override onlyComplianceCall {}

  /// @inheritdoc IModule
  // solhint-disable-next-line no-empty-blocks
  function moduleBurnAction(address, uint256) external override onlyComplianceCall {}

  /// @inheritdoc IModule
  function moduleCheck(address, address _to, uint256, address _compliance) external view override returns (bool) {
    IToken token = IToken(IModularCompliance(_compliance).getTokenBound());
    return _allowedCountries[_compliance][token.identityRegistry().investorCountry(_to)];
  }

  /// @inheritdoc IModule
  function canComplianceBind(address) external pure override returns (bool) {
    return true;
  }

  /// @inheritdoc IModule
  function isPlugAndPlay() external pure override returns (bool) {
    return true;
  }

  /// @inheritdoc IModule
  function name() external pure override returns (string memory) {
    return 'JurisdictionAllowlistModule';
  }

  /// @notice Tells whether investors registered in `_country` can receive the token of `_compliance`.
  /// @param _compliance The compliance contract of the token
  /// @param _country The ISO 3166-1 numeric country code
  function isCountryAllowed(address _compliance, uint16 _country) external view returns (bool) {
    return _allowedCountries[_compliance][_country];
  }

  function _allowCountry(uint16 _country) private {
    if (_country == 0) revert Errors.InvalidCountry();
    _allowedCountries[msg.sender][_country] = true;
    emit Events.CountryAllowed({compliance: msg.sender, country: _country});
  }
}

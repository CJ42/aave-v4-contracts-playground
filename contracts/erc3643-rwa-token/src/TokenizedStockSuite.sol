// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

// interfaces
import {ITREXFactory} from '@erc3643org/erc-3643/contracts/factory/ITREXFactory.sol';

// modules
import {HoldingPeriodModule} from './modules/HoldingPeriodModule.sol';
import {JurisdictionAllowlistModule} from './modules/JurisdictionAllowlistModule.sol';

// constants
import {
  CLAIM_TOPIC_ACCREDITED_INVESTOR,
  CLAIM_TOPIC_KYC,
  COUNTRY_GB,
  COUNTRY_US,
  RULE_144_HOLDING_PERIOD,
  SHARE_DECIMALS
} from './Constants.sol';

/// @title TokenizedStockSuite
/// @notice The terms of the example offering, expressed as `TREXFactory.deployTREXSuite` arguments.
///
/// @dev This is the file to adapt for another asset. The T-REX contracts are used unmodified, so
/// the rules of a security live in three places: the claims investors must hold, the compliance
/// modules, and the settings passed to those modules at deployment.
library TokenizedStockSuite {
  /// @notice Builds the token details of a share class restricted to the allowed countries.
  /// @param owner The issuer, who ends up owning every contract of the suite
  /// @param agent The transfer agent, able to register investors, mint, burn, freeze and force transfers
  /// @param name The share class name
  /// @param symbol The share class symbol
  /// @param jurisdictionModule The deployed `JurisdictionAllowlistModule` proxy
  /// @param holdingPeriodModule The deployed `HoldingPeriodModule` proxy
  function tokenDetails(
    address owner,
    address agent,
    string memory name,
    string memory symbol,
    address jurisdictionModule,
    address holdingPeriodModule
  ) internal pure returns (ITREXFactory.TokenDetails memory) {
    address[] memory agents = new address[](1);
    agents[0] = agent;

    address[] memory modules = new address[](2);
    modules[0] = jurisdictionModule;
    modules[1] = holdingPeriodModule;

    uint16[] memory allowedCountries = new uint16[](2);
    allowedCountries[0] = COUNTRY_US;
    allowedCountries[1] = COUNTRY_GB;

    // One setting per module, applied by the factory while it still owns the compliance contract.
    bytes[] memory settings = new bytes[](2);
    settings[0] = abi.encodeCall(JurisdictionAllowlistModule.batchAllowCountries, (allowedCountries));
    settings[1] = abi.encodeCall(HoldingPeriodModule.setHoldingPeriod, (RULE_144_HOLDING_PERIOD));

    return ITREXFactory.TokenDetails({
      owner: owner,
      name: name,
      symbol: symbol,
      decimals: SHARE_DECIMALS,
      irs: address(0), // deploy a dedicated IdentityRegistryStorage
      ONCHAINID: address(0), // let the factory create the token's identity
      irAgents: agents,
      tokenAgents: agents,
      complianceModules: modules,
      complianceSettings: settings
    });
  }

  /// @notice Builds the claim requirements: every investor needs both a KYC and an accreditation claim.
  /// @param claimIssuer The claim issuer trusted for both topics
  function claimDetails(address claimIssuer) internal pure returns (ITREXFactory.ClaimDetails memory) {
    uint256[] memory claimTopics = new uint256[](2);
    claimTopics[0] = CLAIM_TOPIC_KYC;
    claimTopics[1] = CLAIM_TOPIC_ACCREDITED_INVESTOR;

    address[] memory issuers = new address[](1);
    issuers[0] = claimIssuer;

    uint256[][] memory issuerClaims = new uint256[][](1);
    issuerClaims[0] = claimTopics;

    return ITREXFactory.ClaimDetails({claimTopics: claimTopics, issuers: issuers, issuerClaims: issuerClaims});
  }
}

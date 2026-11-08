// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

// modules
import {JurisdictionAllowlistModule} from '../src/modules/JurisdictionAllowlistModule.sol';
import {TokenizedStockFixture} from './utils/TokenizedStockFixture.sol';

// errors & events
import '../src/Errors.sol' as Errors;
import {Events} from '../src/Events.sol';

// constants
import {COUNTRY_GB, COUNTRY_US} from '../src/Constants.sol';

contract JurisdictionAllowlistModuleTest is TokenizedStockFixture {
  string internal constant ONLY_COMPLIANCE = 'only bound compliance can call';

  function test_AllowCountry_EmitsEventAndAllows() public {
    vm.expectEmit(address(jurisdictionModule));
    emit Events.CountryAllowed({compliance: address(compliance), country: COUNTRY_FR});

    _callModule(address(jurisdictionModule), abi.encodeCall(JurisdictionAllowlistModule.allowCountry, (COUNTRY_FR)));

    assertTrue(jurisdictionModule.isCountryAllowed(address(compliance), COUNTRY_FR));
  }

  function test_DisallowCountry_EmitsEventAndDisallows() public {
    vm.expectEmit(address(jurisdictionModule));
    emit Events.CountryDisallowed({compliance: address(compliance), country: COUNTRY_GB});

    _callModule(address(jurisdictionModule), abi.encodeCall(JurisdictionAllowlistModule.disallowCountry, (COUNTRY_GB)));

    assertFalse(jurisdictionModule.isCountryAllowed(address(compliance), COUNTRY_GB));
  }

  function test_BatchAllowCountries_AllowsAll() public {
    uint16[] memory countries = new uint16[](2);
    countries[0] = COUNTRY_FR;
    countries[1] = 276; // Germany

    _callModule(
      address(jurisdictionModule), abi.encodeCall(JurisdictionAllowlistModule.batchAllowCountries, (countries))
    );

    assertTrue(jurisdictionModule.isCountryAllowed(address(compliance), COUNTRY_FR));
    assertTrue(jurisdictionModule.isCountryAllowed(address(compliance), 276));
  }

  function test_AllowCountry_RevertsWhen_CountryIsZero() public {
    vm.prank(issuer);
    vm.expectRevert(Errors.InvalidCountry.selector);
    compliance.callModuleFunction(
      abi.encodeCall(JurisdictionAllowlistModule.allowCountry, (0)), address(jurisdictionModule)
    );
  }

  function test_ModuleCheck_RejectsUnregisteredReceiver() public view {
    assertFalse(jurisdictionModule.moduleCheck(alice, eve, 1, address(compliance)));
  }

  function test_Settings_AreIsolatedPerCompliance() public view {
    assertTrue(jurisdictionModule.isCountryAllowed(address(compliance), COUNTRY_US));
    assertFalse(jurisdictionModule.isCountryAllowed(address(this), COUNTRY_US));
  }

  function test_AccessControl_ConfigurationIsComplianceOnly() public {
    vm.prank(issuer);
    vm.expectRevert(bytes(ONLY_COMPLIANCE));
    jurisdictionModule.allowCountry(COUNTRY_FR);

    vm.prank(issuer);
    vm.expectRevert(bytes(ONLY_COMPLIANCE));
    jurisdictionModule.disallowCountry(COUNTRY_US);
  }

  function test_AccessControl_HooksAreComplianceOnly() public {
    vm.expectRevert(bytes(ONLY_COMPLIANCE));
    jurisdictionModule.moduleMintAction(alice, 1);

    vm.expectRevert(bytes(ONLY_COMPLIANCE));
    jurisdictionModule.moduleTransferAction(alice, bob, 1);

    vm.expectRevert(bytes(ONLY_COMPLIANCE));
    jurisdictionModule.moduleBurnAction(alice, 1);
  }

  function test_Implementation_CannotBeInitialized() public {
    JurisdictionAllowlistModule implementation = new JurisdictionAllowlistModule();
    vm.expectRevert(bytes('Initializable: contract is already initialized'));
    implementation.initialize();
  }

  function test_Metadata() public view {
    assertEq(jurisdictionModule.name(), 'JurisdictionAllowlistModule');
    assertTrue(jurisdictionModule.isPlugAndPlay());
    assertTrue(jurisdictionModule.canComplianceBind(address(compliance)));
  }
}

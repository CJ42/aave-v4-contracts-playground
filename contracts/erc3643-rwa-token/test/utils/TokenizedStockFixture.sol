// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import {Test} from 'forge-std/Test.sol';

// interfaces
import {IIdentity} from '@onchain-id/solidity/contracts/interface/IIdentity.sol';
import {IModularCompliance} from '@erc3643org/erc-3643/contracts/compliance/modular/IModularCompliance.sol';
import {IIdentityRegistry} from '@erc3643org/erc-3643/contracts/registry/interface/IIdentityRegistry.sol';
import {ITrustedIssuersRegistry} from '@erc3643org/erc-3643/contracts/registry/interface/ITrustedIssuersRegistry.sol';
import {
  ITREXImplementationAuthority
} from '@erc3643org/erc-3643/contracts/proxy/authority/ITREXImplementationAuthority.sol';
import {IToken} from '@erc3643org/erc-3643/contracts/token/IToken.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

// OnchainID
import {ClaimIssuer} from '@onchain-id/solidity/contracts/ClaimIssuer.sol';
import {Identity} from '@onchain-id/solidity/contracts/Identity.sol';
import {IdFactory} from '@onchain-id/solidity/contracts/factory/IdFactory.sol';
import {ImplementationAuthority} from '@onchain-id/solidity/contracts/proxy/ImplementationAuthority.sol';

// T-REX
import {ModularCompliance} from '@erc3643org/erc-3643/contracts/compliance/modular/ModularCompliance.sol';
import {ModuleProxy} from '@erc3643org/erc-3643/contracts/compliance/modular/modules/ModuleProxy.sol';
import {TREXFactory} from '@erc3643org/erc-3643/contracts/factory/TREXFactory.sol';
import {
  TREXImplementationAuthority
} from '@erc3643org/erc-3643/contracts/proxy/authority/TREXImplementationAuthority.sol';
import {ClaimTopicsRegistry} from '@erc3643org/erc-3643/contracts/registry/implementation/ClaimTopicsRegistry.sol';
import {IdentityRegistry} from '@erc3643org/erc-3643/contracts/registry/implementation/IdentityRegistry.sol';
import {
  IdentityRegistryStorage
} from '@erc3643org/erc-3643/contracts/registry/implementation/IdentityRegistryStorage.sol';
import {
  TrustedIssuersRegistry
} from '@erc3643org/erc-3643/contracts/registry/implementation/TrustedIssuersRegistry.sol';
import {Token} from '@erc3643org/erc-3643/contracts/token/Token.sol';

// modules
import {HoldingPeriodModule} from '../../src/modules/HoldingPeriodModule.sol';
import {JurisdictionAllowlistModule} from '../../src/modules/JurisdictionAllowlistModule.sol';
import {TokenizedStockSuite} from '../../src/TokenizedStockSuite.sol';

// constants
import {
  CLAIM_SCHEME_ECDSA,
  CLAIM_TOPIC_ACCREDITED_INVESTOR,
  CLAIM_TOPIC_KYC,
  COUNTRY_GB,
  COUNTRY_US,
  RULE_144_HOLDING_PERIOD
} from '../../src/Constants.sol';

/// @dev Deploys the complete stack the way an issuer would: the T-REX implementations behind an
/// implementation authority, OnchainID's identity factory, the `TREXFactory`, one claim issuer, the
/// two compliance modules, then the suite itself. There is no canonical deployment to fork, as every
/// ERC-3643 issuer owns its own suite, so these tests run on a local chain.
abstract contract TokenizedStockFixture is Test {
  uint16 internal constant COUNTRY_FR = 250;
  string internal constant SALT = 'ACME-CLASS-A';

  address internal issuer = makeAddr('issuer');
  address internal agent = makeAddr('transferAgent');
  address internal claimIssuerManager = makeAddr('claimIssuerManager');
  address internal claimSigner;
  uint256 internal claimSignerKey;

  address internal alice = makeAddr('alice'); // US, KYC + accredited
  address internal bob = makeAddr('bob'); // GB, KYC + accredited
  address internal carol = makeAddr('carol'); // FR (not an allowed country), KYC + accredited
  address internal dave = makeAddr('dave'); // US, KYC only
  address internal eve = makeAddr('eve'); // never onboarded

  IdFactory internal idFactory;
  TREXFactory internal trexFactory;
  ClaimIssuer internal claimIssuer;
  JurisdictionAllowlistModule internal jurisdictionModule;
  HoldingPeriodModule internal holdingPeriodModule;

  IToken internal token;
  IModularCompliance internal compliance;
  IIdentityRegistry internal identityRegistry;
  ITrustedIssuersRegistry internal trustedIssuersRegistry;

  function setUp() public virtual {
    (claimSigner, claimSignerKey) = makeAddrAndKey('claimSigner');

    _deployProtocol();
    _deployClaimIssuer();
    _deployModules();
    _deploySuite();

    vm.prank(agent);
    token.unpause();

    uint256[] memory fullClaims = new uint256[](2);
    fullClaims[0] = CLAIM_TOPIC_KYC;
    fullClaims[1] = CLAIM_TOPIC_ACCREDITED_INVESTOR;
    uint256[] memory kycOnly = new uint256[](1);
    kycOnly[0] = CLAIM_TOPIC_KYC;

    _onboard({wallet: alice, country: COUNTRY_US, topics: fullClaims});
    _onboard({wallet: bob, country: COUNTRY_GB, topics: fullClaims});
    _onboard({wallet: carol, country: COUNTRY_FR, topics: fullClaims});
    _onboard({wallet: dave, country: COUNTRY_US, topics: kycOnly});
  }

  function _deployProtocol() private {
    TREXImplementationAuthority authority =
      new TREXImplementationAuthority({referenceStatus: true, trexFactory: address(0), iaFactory: address(0)});
    authority.addAndUseTREXVersion(
      ITREXImplementationAuthority.Version({major: 4, minor: 1, patch: 3}),
      ITREXImplementationAuthority.TREXContracts({
        tokenImplementation: address(new Token()),
        ctrImplementation: address(new ClaimTopicsRegistry()),
        irImplementation: address(new IdentityRegistry()),
        irsImplementation: address(new IdentityRegistryStorage()),
        tirImplementation: address(new TrustedIssuersRegistry()),
        mcImplementation: address(new ModularCompliance())
      })
    );

    Identity identityImplementation = new Identity({initialManagementKey: address(this), _isLibrary: true});
    idFactory = new IdFactory(address(new ImplementationAuthority(address(identityImplementation))));
    trexFactory = new TREXFactory(address(authority), address(idFactory));
    idFactory.addTokenFactory(address(trexFactory));
  }

  function _deployClaimIssuer() private {
    claimIssuer = new ClaimIssuer(claimIssuerManager);
    vm.prank(claimIssuerManager);
    claimIssuer.addKey({_key: keccak256(abi.encode(claimSigner)), _purpose: 3, _type: 1});
  }

  function _deployModules() private {
    jurisdictionModule = JurisdictionAllowlistModule(
      address(
        new ModuleProxy(
          address(new JurisdictionAllowlistModule()), abi.encodeCall(JurisdictionAllowlistModule.initialize, ())
        )
      )
    );
    holdingPeriodModule = HoldingPeriodModule(
      address(new ModuleProxy(address(new HoldingPeriodModule()), abi.encodeCall(HoldingPeriodModule.initialize, ())))
    );
  }

  function _deploySuite() private {
    trexFactory.deployTREXSuite(
      SALT,
      TokenizedStockSuite.tokenDetails({
        owner: issuer,
        agent: agent,
        name: 'Acme Corp Class A',
        symbol: 'ACME',
        jurisdictionModule: address(jurisdictionModule),
        holdingPeriodModule: address(holdingPeriodModule)
      }),
      TokenizedStockSuite.claimDetails(address(claimIssuer))
    );

    token = IToken(trexFactory.getToken(SALT));
    compliance = token.compliance();
    identityRegistry = token.identityRegistry();
    trustedIssuersRegistry = identityRegistry.issuersRegistry();

    // `deployTREXSuite` hands every contract over to the owner except the storage it deployed.
    trexFactory.recoverContractOwnership(address(identityRegistry.identityStorage()), issuer);
  }

  /// @dev Creates the investor's identity, adds the signed claims from the investor's wallet, and registers it.
  function _onboard(address wallet, uint16 country, uint256[] memory topics) internal returns (IIdentity identity) {
    identity = IIdentity(idFactory.createIdentity(wallet, vm.toString(wallet)));
    for (uint256 i = 0; i < topics.length; i++) {
      bytes memory data = abi.encode('verified off-chain');
      bytes memory signature = _signClaim({identity: identity, topic: topics[i], data: data});
      vm.prank(wallet);
      identity.addClaim({
        _topic: topics[i],
        _scheme: CLAIM_SCHEME_ECDSA,
        issuer: address(claimIssuer),
        _signature: signature,
        _data: data,
        _uri: ''
      });
    }
    vm.prank(agent);
    identityRegistry.registerIdentity(wallet, identity, country);
  }

  function _signClaim(IIdentity identity, uint256 topic, bytes memory data) internal view returns (bytes memory) {
    bytes32 dataHash = keccak256(abi.encode(identity, topic, data));
    bytes32 digest = keccak256(abi.encodePacked('\x19Ethereum Signed Message:\n32', dataHash));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(claimSignerKey, digest);
    return abi.encodePacked(r, s, v);
  }

  /// @dev Revokes the claim of `topic` the same way a claim issuer would on losing an investor's accreditation.
  function _revokeClaim(address wallet, uint256 topic) internal {
    IIdentity identity = identityRegistry.identity(wallet);
    (,,, bytes memory signature,,) = identity.getClaim(keccak256(abi.encode(address(claimIssuer), topic)));
    vm.prank(claimIssuerManager);
    claimIssuer.revokeClaimBySignature(signature);
  }

  function _mint(address wallet, uint256 amount) internal {
    vm.prank(agent);
    token.mint(wallet, amount);
  }

  function _ownerOf(address target) internal view returns (address) {
    return Ownable(target).owner();
  }

  function _callModule(address module, bytes memory data) internal {
    vm.prank(issuer);
    compliance.callModuleFunction(data, module);
  }

  function _skipHoldingPeriod() internal {
    skip(RULE_144_HOLDING_PERIOD);
  }
}

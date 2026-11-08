// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

// interfaces
import {IIdentity} from '@onchain-id/solidity/contracts/interface/IIdentity.sol';
import {IClaimIssuer} from '@onchain-id/solidity/contracts/interface/IClaimIssuer.sol';

// modules
import {JurisdictionAllowlistModule} from '../src/modules/JurisdictionAllowlistModule.sol';
import {TokenizedStockFixture} from './utils/TokenizedStockFixture.sol';

// constants
import {
  CLAIM_TOPIC_ACCREDITED_INVESTOR,
  CLAIM_TOPIC_KYC,
  COUNTRY_US,
  RULE_144_HOLDING_PERIOD,
  SHARE_DECIMALS
} from '../src/Constants.sol';

/// @dev Full lifecycle of the share token against the unmodified T-REX and OnchainID contracts.
contract TokenizedStockTest is TokenizedStockFixture {
  string internal constant NOT_AGENT = 'AgentRole: caller does not have the Agent role';
  string internal constant NOT_VERIFIED = 'Identity is not verified.';
  string internal constant NOT_COMPLIANT = 'Compliance not followed';
  string internal constant TRANSFER_NOT_POSSIBLE = 'Transfer not possible';
  string internal constant WALLET_FROZEN = 'wallet is frozen';
  string internal constant PAUSED = 'Pausable: paused';
  string internal constant INSUFFICIENT_BALANCE = 'Insufficient Balance';

  uint256 internal constant SHARES = 1_000;

  // ---- Deployment ----

  function test_Deployment_WiresTheSuite() public view {
    assertEq(token.name(), 'Acme Corp Class A');
    assertEq(token.symbol(), 'ACME');
    assertEq(token.decimals(), SHARE_DECIMALS);
    assertTrue(token.onchainID() != address(0), 'token identity');
    assertFalse(token.paused());

    assertEq(compliance.getTokenBound(), address(token));
    assertTrue(compliance.isModuleBound(address(jurisdictionModule)));
    assertTrue(compliance.isModuleBound(address(holdingPeriodModule)));
    assertEq(holdingPeriodModule.holdingPeriodOf(address(compliance)), RULE_144_HOLDING_PERIOD);
    assertTrue(jurisdictionModule.isCountryAllowed(address(compliance), COUNTRY_US));

    uint256[] memory topics = identityRegistry.topicsRegistry().getClaimTopics();
    assertEq(topics.length, 2);
    assertEq(topics[0], CLAIM_TOPIC_KYC);
    assertEq(topics[1], CLAIM_TOPIC_ACCREDITED_INVESTOR);
    assertTrue(trustedIssuersRegistry.isTrustedIssuer(address(claimIssuer)));
  }

  function test_Deployment_IssuerOwnsEveryContract() public view {
    assertEq(_ownerOf(address(token)), issuer);
    assertEq(_ownerOf(address(compliance)), issuer);
    assertEq(_ownerOf(address(identityRegistry)), issuer);
    assertEq(_ownerOf(address(identityRegistry.identityStorage())), issuer);
    assertEq(_ownerOf(address(identityRegistry.topicsRegistry())), issuer);
    assertEq(_ownerOf(address(trustedIssuersRegistry)), issuer);
  }

  // ---- Investor eligibility ----

  function test_IsVerified_RequiresEveryClaimTopic() public view {
    assertTrue(identityRegistry.isVerified(alice));
    assertFalse(identityRegistry.isVerified(dave), 'no accreditation claim');
    assertFalse(identityRegistry.isVerified(eve), 'no identity');
  }

  function test_Mint_ToEligibleInvestor() public {
    _mint(alice, SHARES);
    assertEq(token.balanceOf(alice), SHARES);
    assertEq(token.totalSupply(), SHARES);
  }

  function test_Mint_RevertsWhen_CallerIsNotAgent() public {
    vm.prank(issuer);
    vm.expectRevert(bytes(NOT_AGENT));
    token.mint(alice, SHARES);
  }

  function test_Mint_RevertsWhen_InvestorIsNotAccredited() public {
    vm.prank(agent);
    vm.expectRevert(bytes(NOT_VERIFIED));
    token.mint(dave, SHARES);
  }

  function test_Mint_RevertsWhen_InvestorHasNoIdentity() public {
    vm.prank(agent);
    vm.expectRevert(bytes(NOT_VERIFIED));
    token.mint(eve, SHARES);
  }

  function test_Mint_RevertsWhen_CountryIsNotAllowed() public {
    vm.prank(agent);
    vm.expectRevert(bytes(NOT_COMPLIANT));
    token.mint(carol, SHARES);
  }

  // ---- Transfers ----

  function test_Transfer_SucceedsAfterHoldingPeriod() public {
    _mint(alice, SHARES);
    _skipHoldingPeriod();

    vm.prank(alice);
    token.transfer(bob, 400);

    assertEq(token.balanceOf(alice), SHARES - 400);
    assertEq(token.balanceOf(bob), 400);
    assertEq(holdingPeriodModule.lockedBalanceOf(address(compliance), bob), 0, 'resale carries no lock');
  }

  function test_Transfer_RevertsDuringHoldingPeriod() public {
    _mint(alice, SHARES);
    skip(RULE_144_HOLDING_PERIOD - 1);

    vm.prank(alice);
    vm.expectRevert(bytes(TRANSFER_NOT_POSSIBLE));
    token.transfer(bob, 1);
  }

  function test_Transfer_OnlyMovesReleasedTranches() public {
    _mint(alice, 100);
    skip(RULE_144_HOLDING_PERIOD / 2);
    _mint(alice, 50);
    skip(RULE_144_HOLDING_PERIOD / 2);

    assertEq(holdingPeriodModule.lockedBalanceOf(address(compliance), alice), 50);

    vm.prank(alice);
    vm.expectRevert(bytes(TRANSFER_NOT_POSSIBLE));
    token.transfer(bob, 101);

    vm.prank(alice);
    token.transfer(bob, 100);
    assertEq(token.balanceOf(alice), 50);

    vm.prank(alice);
    vm.expectRevert(bytes(TRANSFER_NOT_POSSIBLE));
    token.transfer(bob, 1);

    skip(RULE_144_HOLDING_PERIOD / 2);
    vm.prank(alice);
    token.transfer(bob, 50);
    assertEq(token.balanceOf(bob), 150);
  }

  function test_TransferFrom_EnforcesTheSameRules() public {
    _mint(alice, SHARES);
    vm.prank(alice);
    token.approve(address(this), SHARES);

    vm.expectRevert(bytes(TRANSFER_NOT_POSSIBLE));
    token.transferFrom(alice, bob, 1);

    _skipHoldingPeriod();
    token.transferFrom(alice, bob, SHARES);
    assertEq(token.balanceOf(bob), SHARES);
    assertEq(token.allowance(alice, address(this)), 0);
  }

  function test_Transfer_RevertsWhen_RecipientIsNotAccredited() public {
    _mint(alice, SHARES);
    _skipHoldingPeriod();

    vm.prank(alice);
    vm.expectRevert(bytes(TRANSFER_NOT_POSSIBLE));
    token.transfer(dave, 1);
  }

  function test_Transfer_RevertsWhen_RecipientAccreditationIsRevoked() public {
    _mint(alice, SHARES);
    _skipHoldingPeriod();
    _revokeClaim(bob, CLAIM_TOPIC_ACCREDITED_INVESTOR);
    assertFalse(identityRegistry.isVerified(bob));

    vm.prank(alice);
    vm.expectRevert(bytes(TRANSFER_NOT_POSSIBLE));
    token.transfer(bob, 1);
  }

  function test_Transfer_SellerWithRevokedClaimCanStillExit() public {
    _mint(alice, SHARES);
    _skipHoldingPeriod();
    _revokeClaim(alice, CLAIM_TOPIC_KYC);

    vm.prank(alice);
    token.transfer(bob, SHARES);
    assertEq(token.balanceOf(bob), SHARES);
  }

  function test_Transfer_RevertsWhen_ClaimIssuerIsNoLongerTrusted() public {
    _mint(alice, SHARES);
    _skipHoldingPeriod();

    vm.prank(issuer);
    trustedIssuersRegistry.removeTrustedIssuer(IClaimIssuer(address(claimIssuer)));

    vm.prank(alice);
    vm.expectRevert(bytes(TRANSFER_NOT_POSSIBLE));
    token.transfer(bob, 1);
  }

  function test_Transfer_RevertsWhen_RecipientCountryIsNotAllowed() public {
    _mint(alice, SHARES);
    _skipHoldingPeriod();

    vm.prank(alice);
    vm.expectRevert(bytes(TRANSFER_NOT_POSSIBLE));
    token.transfer(carol, 1);
  }

  function test_Transfer_FollowsCountryAllowlistChanges() public {
    _mint(alice, SHARES);
    _skipHoldingPeriod();

    _callModule(address(jurisdictionModule), abi.encodeCall(JurisdictionAllowlistModule.allowCountry, (COUNTRY_FR)));
    vm.prank(alice);
    token.transfer(carol, 1);
    assertEq(token.balanceOf(carol), 1);

    _callModule(address(jurisdictionModule), abi.encodeCall(JurisdictionAllowlistModule.disallowCountry, (COUNTRY_FR)));
    vm.prank(alice);
    vm.expectRevert(bytes(TRANSFER_NOT_POSSIBLE));
    token.transfer(carol, 1);
  }

  function test_Transfer_RevertsWhen_InvestorMovedToDisallowedCountry() public {
    _mint(alice, SHARES);
    _skipHoldingPeriod();

    vm.prank(agent);
    identityRegistry.updateCountry(bob, COUNTRY_FR);

    vm.prank(alice);
    vm.expectRevert(bytes(TRANSFER_NOT_POSSIBLE));
    token.transfer(bob, 1);
  }

  function test_CanTransfer_ReturnsFalseAboveBalance() public {
    _mint(alice, SHARES);
    _skipHoldingPeriod();
    assertFalse(compliance.canTransfer(alice, bob, type(uint256).max));
  }

  // ---- Agent actions ----

  function test_ForcedTransfer_MovesLockedSharesWithTheirLock() public {
    _mint(alice, SHARES);
    uint256 unlocksAt = block.timestamp + RULE_144_HOLDING_PERIOD;
    skip(30 days);

    vm.prank(agent);
    token.forcedTransfer(alice, bob, 300);

    assertEq(token.balanceOf(alice), SHARES - 300);
    assertEq(token.balanceOf(bob), 300);
    assertEq(holdingPeriodModule.lockedBalanceOf(address(compliance), alice), SHARES - 300);
    assertEq(holdingPeriodModule.lockedBalanceOf(address(compliance), bob), 300);

    vm.warp(unlocksAt - 1);
    vm.prank(bob);
    vm.expectRevert(bytes(TRANSFER_NOT_POSSIBLE));
    token.transfer(alice, 1);

    vm.warp(unlocksAt);
    vm.prank(bob);
    token.transfer(alice, 300);
    assertEq(token.balanceOf(alice), SHARES);
  }

  function test_ForcedTransfer_OverridesModulesButNotIdentity() public {
    _mint(alice, SHARES);

    vm.prank(agent);
    token.forcedTransfer(alice, carol, 1);
    assertEq(token.balanceOf(carol), 1, 'court order into a non-allowed country');

    vm.prank(agent);
    vm.expectRevert(bytes(TRANSFER_NOT_POSSIBLE));
    token.forcedTransfer(alice, dave, 1);

    vm.prank(agent);
    vm.expectRevert(bytes(TRANSFER_NOT_POSSIBLE));
    token.forcedTransfer(alice, eve, 1);
  }

  function test_ForcedTransfer_RevertsWhen_CallerIsNotAgent() public {
    _mint(alice, SHARES);

    vm.prank(issuer);
    vm.expectRevert(bytes(NOT_AGENT));
    token.forcedTransfer(alice, bob, 1);
  }

  function test_ForcedTransfer_ConsumesFrozenTokens() public {
    _mint(alice, SHARES);
    vm.prank(agent);
    token.freezePartialTokens(alice, 800);

    vm.prank(agent);
    token.forcedTransfer(alice, bob, 500);

    assertEq(token.balanceOf(bob), 500);
    assertEq(token.getFrozenTokens(alice), 500, 'free balance is used before frozen tokens');
  }

  function test_RecoveryAddress_MigratesBalanceLocksAndFreeze() public {
    _mint(alice, SHARES);
    uint256 unlocksAt = block.timestamp + RULE_144_HOLDING_PERIOD;

    address aliceNewWallet = makeAddr('aliceNewWallet');
    IIdentity aliceIdentity = identityRegistry.identity(alice);
    vm.prank(alice);
    aliceIdentity.addKey({_key: keccak256(abi.encode(aliceNewWallet)), _purpose: 1, _keyType: 1});

    vm.startPrank(agent);
    token.freezePartialTokens(alice, 100);
    token.setAddressFrozen(alice, true);
    token.recoveryAddress(alice, aliceNewWallet, address(aliceIdentity));
    vm.stopPrank();

    assertEq(token.balanceOf(alice), 0);
    assertEq(token.balanceOf(aliceNewWallet), SHARES);
    assertEq(token.getFrozenTokens(aliceNewWallet), 100);
    assertTrue(token.isFrozen(aliceNewWallet));
    assertEq(address(identityRegistry.identity(alice)), address(0));
    assertEq(address(identityRegistry.identity(aliceNewWallet)), address(aliceIdentity));

    assertEq(holdingPeriodModule.lockedBalanceOf(address(compliance), alice), 0);
    assertEq(holdingPeriodModule.lockedBalanceOf(address(compliance), aliceNewWallet), SHARES);

    vm.startPrank(agent);
    token.setAddressFrozen(aliceNewWallet, false);
    token.unfreezePartialTokens(aliceNewWallet, 100);
    vm.stopPrank();

    vm.warp(unlocksAt - 1);
    vm.prank(aliceNewWallet);
    vm.expectRevert(bytes(TRANSFER_NOT_POSSIBLE));
    token.transfer(bob, 1);

    vm.warp(unlocksAt);
    vm.prank(aliceNewWallet);
    token.transfer(bob, SHARES);
    assertEq(token.balanceOf(bob), SHARES);
  }

  function test_RecoveryAddress_RevertsWhen_NewWalletIsNotAnIdentityKey() public {
    _mint(alice, SHARES);
    address stranger = makeAddr('stranger');
    address aliceIdentity = address(identityRegistry.identity(alice));

    vm.prank(agent);
    vm.expectRevert(bytes('Recovery not possible'));
    token.recoveryAddress(alice, stranger, aliceIdentity);
  }

  function test_Burn_ReleasesTheBurnedShareLocks() public {
    _mint(alice, SHARES);

    vm.prank(agent);
    token.burn(alice, 400);

    assertEq(token.totalSupply(), SHARES - 400);
    assertEq(holdingPeriodModule.lockedBalanceOf(address(compliance), alice), SHARES - 400);
  }

  // ---- Freeze & pause ----

  function test_SetAddressFrozen_BlocksSenderAndRecipient() public {
    _mint(alice, SHARES);
    _skipHoldingPeriod();

    vm.prank(agent);
    token.setAddressFrozen(alice, true);
    vm.prank(alice);
    vm.expectRevert(bytes(WALLET_FROZEN));
    token.transfer(bob, 1);

    vm.startPrank(agent);
    token.setAddressFrozen(alice, false);
    token.setAddressFrozen(bob, true);
    vm.stopPrank();
    vm.prank(alice);
    vm.expectRevert(bytes(WALLET_FROZEN));
    token.transfer(bob, 1);
  }

  function test_FreezePartialTokens_BlocksOnlyTheFrozenAmount() public {
    _mint(alice, SHARES);
    _skipHoldingPeriod();
    vm.prank(agent);
    token.freezePartialTokens(alice, 900);

    vm.prank(alice);
    vm.expectRevert(bytes(INSUFFICIENT_BALANCE));
    token.transfer(bob, 101);

    vm.prank(alice);
    token.transfer(bob, 100);
    assertEq(token.balanceOf(bob), 100);
  }

  function test_Pause_BlocksTransfersButNotAgentActions() public {
    _mint(alice, SHARES);
    _skipHoldingPeriod();
    vm.prank(agent);
    token.pause();

    vm.prank(alice);
    vm.expectRevert(bytes(PAUSED));
    token.transfer(bob, 1);

    vm.startPrank(agent);
    token.forcedTransfer(alice, bob, 1);
    token.mint(alice, 1);
    token.unpause();
    vm.stopPrank();

    vm.prank(alice);
    token.transfer(bob, 1);
    assertEq(token.balanceOf(bob), 2);
  }

  function test_Pause_RevertsWhen_CallerIsNotAgent() public {
    vm.prank(issuer);
    vm.expectRevert(bytes(NOT_AGENT));
    token.pause();
  }
}

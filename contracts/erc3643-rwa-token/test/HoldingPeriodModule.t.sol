// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

// modules
import {HoldingPeriodModule} from '../src/modules/HoldingPeriodModule.sol';
import {TokenizedStockFixture} from './utils/TokenizedStockFixture.sol';

// errors & events
import '../src/Errors.sol' as Errors;
import {Events} from '../src/Events.sol';

// constants
import {RULE_144_HOLDING_PERIOD} from '../src/Constants.sol';

contract HoldingPeriodModuleTest is TokenizedStockFixture {
  string internal constant ONLY_COMPLIANCE = 'only bound compliance can call';

  function _locked(address wallet) private view returns (uint256) {
    return holdingPeriodModule.lockedBalanceOf(address(compliance), wallet);
  }

  function _locks(address wallet) private view returns (HoldingPeriodModule.Lock[] memory) {
    return holdingPeriodModule.locksOf(address(compliance), wallet);
  }

  // ---- Configuration ----

  function test_SetHoldingPeriod_EmitsEventAndApplies() public {
    vm.expectEmit(address(holdingPeriodModule));
    emit Events.HoldingPeriodSet({compliance: address(compliance), holdingPeriod: 184 days});

    _callModule(address(holdingPeriodModule), abi.encodeCall(HoldingPeriodModule.setHoldingPeriod, (184 days)));

    assertEq(holdingPeriodModule.holdingPeriodOf(address(compliance)), 184 days);
  }

  function test_SetHoldingPeriod_RevertsWhen_AboveCap() public {
    uint256 maxPeriod = holdingPeriodModule.MAX_HOLDING_PERIOD();

    vm.prank(issuer);
    vm.expectRevert(abi.encodeWithSelector(Errors.HoldingPeriodTooLong.selector, maxPeriod + 1, maxPeriod));
    compliance.callModuleFunction(
      abi.encodeCall(HoldingPeriodModule.setHoldingPeriod, (maxPeriod + 1)), address(holdingPeriodModule)
    );
  }

  function test_SetHoldingPeriod_LeavesExistingLocksUntouched() public {
    _mint(alice, 100);
    uint256 releaseTime = block.timestamp + RULE_144_HOLDING_PERIOD;

    _callModule(address(holdingPeriodModule), abi.encodeCall(HoldingPeriodModule.setHoldingPeriod, (1 days)));
    _mint(alice, 10);

    HoldingPeriodModule.Lock[] memory locks = _locks(alice);
    assertEq(locks[0].releaseTime, releaseTime);
    assertEq(locks[1].releaseTime, block.timestamp + 1 days);
  }

  function test_ZeroHoldingPeriod_LeavesMintsUnlocked() public {
    _callModule(address(holdingPeriodModule), abi.encodeCall(HoldingPeriodModule.setHoldingPeriod, (0)));
    _mint(alice, 100);

    assertEq(_locks(alice).length, 0);

    vm.prank(alice);
    token.transfer(bob, 100);
    assertEq(token.balanceOf(bob), 100);
  }

  // ---- Lock accounting ----

  function test_Mint_EmitsSharesLocked() public {
    vm.expectEmit(address(holdingPeriodModule));
    emit Events.SharesLocked({
      compliance: address(compliance),
      token: address(token),
      wallet: alice,
      amount: 100,
      releaseTime: block.timestamp + RULE_144_HOLDING_PERIOD
    });

    _mint(alice, 100);
  }

  function test_ForcedTransfer_EmitsLockMoved() public {
    _mint(alice, 100);

    vm.expectEmit(address(holdingPeriodModule));
    emit Events.LockMoved({
      compliance: address(compliance),
      token: address(token),
      from: alice,
      to: bob,
      amount: 40,
      releaseTime: block.timestamp + RULE_144_HOLDING_PERIOD
    });

    vm.prank(agent);
    token.forcedTransfer(alice, bob, 40);
  }

  function test_Burn_EmitsLockMovedToZeroAddress() public {
    _mint(alice, 100);

    vm.expectEmit(address(holdingPeriodModule));
    emit Events.LockMoved({
      compliance: address(compliance),
      token: address(token),
      from: alice,
      to: address(0),
      amount: 40,
      releaseTime: block.timestamp + RULE_144_HOLDING_PERIOD
    });

    vm.prank(agent);
    token.burn(alice, 40);
  }

  function test_ForcedTransfer_TakesFreeSharesBeforeLocks() public {
    _mint(alice, 100);
    _skipHoldingPeriod();
    _mint(alice, 50);

    vm.prank(agent);
    token.forcedTransfer(alice, bob, 100);

    assertEq(_locked(alice), 50);
    assertEq(_locked(bob), 0);
  }

  function test_ForcedTransfer_MovesNewestLocksFirst() public {
    _mint(alice, 100);
    uint256 oldestRelease = block.timestamp + RULE_144_HOLDING_PERIOD;
    skip(10 days);
    _mint(alice, 50);
    uint256 newestRelease = block.timestamp + RULE_144_HOLDING_PERIOD;

    vm.prank(agent);
    token.forcedTransfer(alice, bob, 70);

    HoldingPeriodModule.Lock[] memory aliceLocks = _locks(alice);
    assertEq(aliceLocks.length, 1);
    assertEq(aliceLocks[0].amount, 80);
    assertEq(aliceLocks[0].releaseTime, oldestRelease);

    HoldingPeriodModule.Lock[] memory bobLocks = _locks(bob);
    assertEq(bobLocks.length, 2);
    assertEq(bobLocks[0].amount, 50);
    assertEq(bobLocks[0].releaseTime, newestRelease);
    assertEq(bobLocks[1].amount, 20);
    assertEq(bobLocks[1].releaseTime, oldestRelease);
  }

  function test_ForcedTransfer_ToSelfKeepsLocks() public {
    _mint(alice, 100);

    vm.prank(agent);
    token.forcedTransfer(alice, alice, 100);

    assertEq(token.balanceOf(alice), 100);
    assertEq(_locked(alice), 100);
  }

  function test_ExpiredLocks_ArePrunedOnSettlement() public {
    _mint(alice, 100);
    _skipHoldingPeriod();
    _mint(alice, 50);
    assertEq(_locks(alice).length, 1, 'pruned when the new lock is added');
    assertEq(_locks(alice)[0].amount, 50);
  }

  function test_LockCap_MergesIntoNewestLockAndNeverAdvancesRelease() public {
    uint256 maxLocks = holdingPeriodModule.MAX_LOCKS_PER_WALLET();
    for (uint256 i = 0; i < maxLocks; i++) {
      _mint(alice, 1);
      skip(1 days);
    }
    assertEq(_locks(alice).length, maxLocks);

    uint256 mergedRelease = block.timestamp + RULE_144_HOLDING_PERIOD;
    vm.expectEmit(address(holdingPeriodModule));
    emit Events.SharesLocked({
      compliance: address(compliance), token: address(token), wallet: alice, amount: 10, releaseTime: mergedRelease
    });
    _mint(alice, 10);

    HoldingPeriodModule.Lock[] memory locks = _locks(alice);
    assertEq(locks.length, maxLocks);
    assertEq(locks[maxLocks - 1].amount, 11);
    assertEq(locks[maxLocks - 1].releaseTime, mergedRelease);
    assertEq(_locked(alice), maxLocks + 10);
  }

  /// @dev Whatever mix of agent actions and elapsed time happens, locks never exceed the balance
  /// and the transferable balance computed by the module is exactly what a transfer can move.
  function testFuzz_AgentActions_KeepLocksWithinBalance(
    uint96 firstMint,
    uint96 secondMint,
    uint96 forced,
    uint96 burned,
    uint32 firstWait,
    uint32 secondWait
  ) public {
    vm.assume(firstMint > 0 && secondMint > 0);
    _mint(alice, firstMint);
    skip(bound(firstWait, 0, RULE_144_HOLDING_PERIOD * 2));
    _mint(alice, secondMint);

    uint256 forcedAmount = bound(forced, 0, token.balanceOf(alice));
    if (forcedAmount > 0) {
      vm.prank(agent);
      token.forcedTransfer(alice, bob, forcedAmount);
    }
    uint256 burnedAmount = bound(burned, 0, token.balanceOf(alice));
    if (burnedAmount > 0) {
      vm.prank(agent);
      token.burn(alice, burnedAmount);
    }
    skip(bound(secondWait, 0, RULE_144_HOLDING_PERIOD * 2));

    assertLe(_locked(alice), token.balanceOf(alice));
    assertLe(_locked(bob), token.balanceOf(bob));

    uint256 transferable = token.balanceOf(alice) - _locked(alice);
    assertTrue(compliance.canTransfer(alice, bob, transferable));
    if (_locked(alice) > 0) assertFalse(compliance.canTransfer(alice, bob, transferable + 1));
  }

  // ---- Access control & upgrades ----

  function test_AccessControl_ConfigurationIsComplianceOnly() public {
    vm.prank(issuer);
    vm.expectRevert(bytes(ONLY_COMPLIANCE));
    holdingPeriodModule.setHoldingPeriod(0);
  }

  function test_AccessControl_HooksAreComplianceOnly() public {
    vm.expectRevert(bytes(ONLY_COMPLIANCE));
    holdingPeriodModule.moduleMintAction(alice, 1);

    vm.expectRevert(bytes(ONLY_COMPLIANCE));
    holdingPeriodModule.moduleTransferAction(alice, bob, 1);

    vm.expectRevert(bytes(ONLY_COMPLIANCE));
    holdingPeriodModule.moduleBurnAction(alice, 1);
  }

  function test_Upgrade_RevertsWhen_CallerIsNotOwner() public {
    address newImplementation = address(new HoldingPeriodModule());

    vm.prank(issuer);
    vm.expectRevert(bytes('Ownable: caller is not the owner'));
    holdingPeriodModule.upgradeTo(newImplementation);
  }

  function test_Upgrade_KeepsLocks() public {
    _mint(alice, 100);

    holdingPeriodModule.upgradeTo(address(new HoldingPeriodModule()));

    assertEq(_locked(alice), 100);
    assertTrue(holdingPeriodModule.isComplianceBound(address(compliance)));
  }

  function test_Implementation_CannotBeInitialized() public {
    HoldingPeriodModule implementation = new HoldingPeriodModule();
    vm.expectRevert(bytes('Initializable: contract is already initialized'));
    implementation.initialize();
  }

  function test_Metadata() public view {
    assertEq(holdingPeriodModule.name(), 'HoldingPeriodModule');
    assertTrue(holdingPeriodModule.isPlugAndPlay());
    assertTrue(holdingPeriodModule.canComplianceBind(address(compliance)));
  }
}

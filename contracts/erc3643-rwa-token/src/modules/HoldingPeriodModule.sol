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

/// @title HoldingPeriodModule
/// @notice ERC-3643 compliance module that keeps newly issued shares locked for a holding period,
/// modelling the restricted-securities holding period of SEC Rule 144(d).
///
/// @dev Every mint opens one lock on the receiving wallet, and only the part of a wallet's balance
/// that is not locked can be transferred. Shares that leave a wallet through a regular transfer
/// are therefore always past their holding period, and the receiver gets them free of any lock.
///
/// T-REX agent actions (`forcedTransfer`, `recoveryAddress`, `burn`) skip `moduleCheck` and can
/// take locked shares. When that happens the hook moves the affected locks to the receiver with
/// their original release time, so restricted shares stay restricted in new hands (or, on a
/// recovery, on the investor's new wallet). This keeps `locked <= balance` true for every wallet.
///
/// The hooks never revert on a valid call: a failing hook would revert the agent action, and a
/// transfer agent must always be able to execute a court order or a wallet recovery. For the same
/// reason a wallet's locks are capped by merging into the newest lock rather than by reverting.
///
/// Locks are keyed by wallet and balances are read from the token, so the module holds no balance
/// copy that could drift. It only covers shares minted after it is bound: bind it before issuance.
contract HoldingPeriodModule is AbstractModuleUpgradeable {
  /// @notice A quantity of locked shares and the moment they become transferable.
  struct Lock {
    uint256 amount;
    uint256 releaseTime;
  }

  /// @notice Safety cap on the holding period, which also keeps release times from overflowing.
  uint256 public constant MAX_HOLDING_PERIOD = 3650 days;

  /// @notice Number of locks a wallet can hold, which bounds the gas cost of every transfer check.
  uint256 public constant MAX_LOCKS_PER_WALLET = 32;

  /// @dev compliance contract => holding period applied to future mints, in seconds
  mapping(address => uint256) private _holdingPeriods;

  /// @dev compliance contract => wallet => open locks, oldest first
  mapping(address => mapping(address => Lock[])) private _locks;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes the module behind its proxy and makes the caller the upgrade owner.
  function initialize() external initializer {
    __AbstractModule_init();
  }

  /// @notice Sets the holding period of future mints. Existing locks keep their release time.
  /// @param _holdingPeriod The holding period in seconds, 0 to stop locking new shares
  function setHoldingPeriod(uint256 _holdingPeriod) external onlyComplianceCall {
    if (_holdingPeriod > MAX_HOLDING_PERIOD) {
      revert Errors.HoldingPeriodTooLong({period: _holdingPeriod, maxPeriod: MAX_HOLDING_PERIOD});
    }
    _holdingPeriods[msg.sender] = _holdingPeriod;
    emit Events.HoldingPeriodSet({compliance: msg.sender, holdingPeriod: _holdingPeriod});
  }

  /// @inheritdoc IModule
  function moduleTransferAction(address _from, address _to, uint256) external override onlyComplianceCall {
    _settleLocks({from: _from, to: _to});
  }

  /// @inheritdoc IModule
  function moduleMintAction(address _to, uint256 _value) external override onlyComplianceCall {
    uint256 holdingPeriod = _holdingPeriods[msg.sender];
    if (holdingPeriod == 0) return;

    uint256 releaseTime =
      _addLock({locks: _locks[msg.sender][_to], amount: _value, releaseTime: block.timestamp + holdingPeriod});
    emit Events.SharesLocked({
      compliance: msg.sender,
      token: IModularCompliance(msg.sender).getTokenBound(),
      wallet: _to,
      amount: _value,
      releaseTime: releaseTime
    });
  }

  /// @inheritdoc IModule
  function moduleBurnAction(address _from, uint256) external override onlyComplianceCall {
    _settleLocks({from: _from, to: address(0)});
  }

  /// @inheritdoc IModule
  function moduleCheck(address _from, address, uint256 _value, address _compliance)
    external
    view
    override
    returns (bool)
  {
    if (_from == address(0)) return true;

    uint256 balance = IToken(IModularCompliance(_compliance).getTokenBound()).balanceOf(_from);
    uint256 locked = lockedBalanceOf(_compliance, _from);
    return locked <= balance && _value <= balance - locked;
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
    return 'HoldingPeriodModule';
  }

  /// @notice Returns the holding period applied to future mints of the token of `_compliance`.
  /// @param _compliance The compliance contract of the token
  function holdingPeriodOf(address _compliance) external view returns (uint256) {
    return _holdingPeriods[_compliance];
  }

  /// @notice Returns the stored locks of `_wallet`, which can include some already past their release time.
  /// @param _compliance The compliance contract of the token
  /// @param _wallet The investor wallet
  function locksOf(address _compliance, address _wallet) external view returns (Lock[] memory) {
    return _locks[_compliance][_wallet];
  }

  /// @notice Returns how many shares of `_wallet` are still inside their holding period.
  /// @param _compliance The compliance contract of the token
  /// @param _wallet The investor wallet
  /// @return locked The number of shares that cannot be transferred yet
  function lockedBalanceOf(address _compliance, address _wallet) public view returns (uint256 locked) {
    Lock[] storage locks = _locks[_compliance][_wallet];
    uint256 length = locks.length;
    for (uint256 i = 0; i < length; i++) {
      if (locks[i].releaseTime > block.timestamp) locked += locks[i].amount;
    }
  }

  /// @dev Runs after the token debited `from`. Regular transfers leave `locked <= balance`, so only
  /// agent actions reach the loop. Newest locks go first, and they carry the latest release times.
  /// @param from The debited wallet
  /// @param to The credited wallet, or `address(0)` when the shares were burned
  function _settleLocks(address from, address to) private {
    Lock[] storage locks = _locks[msg.sender][from];
    if (locks.length == 0) return;

    _removeExpiredLocks(locks);
    uint256 locked = 0;
    for (uint256 i = 0; i < locks.length; i++) {
      locked += locks[i].amount;
    }

    address token = IModularCompliance(msg.sender).getTokenBound();
    uint256 balance = IToken(token).balanceOf(from);
    if (locked <= balance) return;

    uint256 excess = locked - balance;
    while (excess != 0) {
      Lock storage newest = locks[locks.length - 1];
      uint256 amount = newest.amount <= excess ? newest.amount : excess;
      uint256 releaseTime = newest.releaseTime;

      if (amount == newest.amount) locks.pop();
      else newest.amount -= amount;
      excess -= amount;

      if (to != address(0)) {
        releaseTime = _addLock({locks: _locks[msg.sender][to], amount: amount, releaseTime: releaseTime});
      }
      emit Events.LockMoved({
        compliance: msg.sender, token: token, from: from, to: to, amount: amount, releaseTime: releaseTime
      });
    }
  }

  /// @dev Records a lock. Once a wallet reaches the cap the shares join its newest lock and the
  /// later of the two release times applies, which can only delay a release, never advance it.
  /// @return The release time that applies to `amount`
  function _addLock(Lock[] storage locks, uint256 amount, uint256 releaseTime) private returns (uint256) {
    _removeExpiredLocks(locks);

    uint256 length = locks.length;
    if (length < MAX_LOCKS_PER_WALLET) {
      locks.push(Lock({amount: amount, releaseTime: releaseTime}));
      return releaseTime;
    }

    Lock storage newest = locks[length - 1];
    newest.amount += amount;
    if (releaseTime > newest.releaseTime) newest.releaseTime = releaseTime;
    return newest.releaseTime;
  }

  /// @dev Compacts `locks` in place, keeping the remaining locks in their original order.
  function _removeExpiredLocks(Lock[] storage locks) private {
    uint256 length = locks.length;
    uint256 kept = 0;
    for (uint256 i = 0; i < length; i++) {
      if (locks[i].releaseTime > block.timestamp) {
        if (kept != i) locks[kept] = locks[i];
        kept++;
      }
    }
    for (; length > kept; length--) {
      locks.pop();
    }
  }
}

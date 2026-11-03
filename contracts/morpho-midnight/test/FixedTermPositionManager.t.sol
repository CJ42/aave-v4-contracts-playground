// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from 'forge-std/Test.sol';

// interfaces
import {IERC20} from 'forge-std/interfaces/IERC20.sol';
import {IMidnight, Market, Offer, CollateralParams} from 'midnight/interfaces/IMidnight.sol';
import {IOracle} from 'midnight/interfaces/IOracle.sol';
import {
  IEcrecoverRatifier,
  Signature,
  EIP712_DOMAIN_TYPEHASH
} from 'midnight/ratifiers/interfaces/IEcrecoverRatifier.sol';

// modules
import {FixedTermPositionManager} from '../src/FixedTermPositionManager.sol';

// libs
import {HashLib} from 'midnight/ratifiers/libraries/HashLib.sol';
import {TickLib} from 'midnight/libraries/TickLib.sol';

// errors & events
import * as Errors from '../src/Errors.sol';
import * as Events from '../src/Events.sol';

// types & constants
import {UnitPrice} from '../src/Types.sol';
import {WAD, MIDNIGHT_BASE_MAINNET} from '../src/Constants.sol';

/// @dev Base mainnet fork tests. The manager runs against the live Midnight deployment, a live
/// USDC market (WETH + USDC collateral, maturity 2026-12-25) and the production EcrecoverRatifier.
/// Lenders sign offers through the production EIP-712 offer-tree flow (single-offer tree: root = leaf, empty proof).
contract FixedTermPositionManagerForkTest is Test {
  // Base mainnet (chain id 8453)
  uint256 internal constant FORK_BLOCK = 53_478_628;
  IERC20 internal constant USDC = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
  IERC20 internal constant WETH = IERC20(0x4200000000000000000000000000000000000006);
  IMidnight internal constant MIDNIGHT = IMidnight(MIDNIGHT_BASE_MAINNET);
  /// @dev https://docs.morpho.org/get-started/resources/addresses/ (Morpho Midnight → Base → EcrecoverRatifier)
  IEcrecoverRatifier internal constant RATIFIER = IEcrecoverRatifier(0xd6e70365C8E8DDa9a4ca662C07bbE663b017755E);

  /// @dev https://api.morpho.org/v0/midnight/markets/0x9489f29b589b92d28733ab15135ce6d9c4b5e64413db4326956447a3de1fc098
  bytes32 internal constant MARKET_ID = 0x9489f29b589b92d28733ab15135ce6d9c4b5e64413db4326956447a3de1fc098;
  uint256 internal constant MATURITY = 1_798_210_800;
  uint256 internal constant RCF_THRESHOLD = 3_000e6;
  uint256 internal constant LIQUIDATION_CURSOR = 0.3e18;
  uint256 internal constant WETH_LLTV = 0.86e18;
  address internal constant WETH_ORACLE = 0xFEa2D58cEfCb9fcb597723c6bAE66fFE4193aFE4;
  uint256 internal constant USDC_LLTV = 0.98e18;
  address internal constant USDC_ORACLE = 0x4429112b3C00b40Cf295db81cfcdE39d7d5ADC1d;

  uint256 internal constant ORACLE_PRICE_SCALE = 1e36;
  uint256 internal constant WETH_INDEX = 0;
  /// @dev Multiple of the market's tick spacing (4).
  uint256 internal constant TICK = 6000;
  /// @dev 1,000 USDC of debt at maturity.
  uint256 internal constant UNITS = 1_000e6;

  FixedTermPositionManager internal manager;
  Market internal market;
  bytes32 internal id;
  uint256 internal collateral;

  address internal lender;
  uint256 internal lenderKey;
  address internal otherLender;
  uint256 internal otherLenderKey;
  address internal borrower = makeAddr('borrower');
  address internal attacker = makeAddr('attacker');

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('base'), FORK_BLOCK);

    manager = new FixedTermPositionManager();

    CollateralParams[] memory collateralParams = new CollateralParams[](2);
    collateralParams[WETH_INDEX] =
      CollateralParams({token: address(WETH), lltv: WETH_LLTV, liquidationCursor: LIQUIDATION_CURSOR, oracle: WETH_ORACLE});
    collateralParams[1] =
      CollateralParams({token: address(USDC), lltv: USDC_LLTV, liquidationCursor: LIQUIDATION_CURSOR, oracle: USDC_ORACLE});
    market = Market({
      chainId: block.chainid,
      midnight: address(MIDNIGHT),
      loanToken: address(USDC),
      collateralParams: collateralParams,
      maturity: MATURITY,
      rcfThreshold: RCF_THRESHOLD,
      enterGate: address(0),
      liquidatorGate: address(0)
    });
    id = manager.marketId(market);

    // Guard against a stale fork setup: the market must be the live one and the ratifier must be Midnight's.
    assertEq(id, MARKET_ID, 'market id');
    assertGt(MIDNIGHT.tickSpacing(id), 0, 'market exists on Midnight');
    assertEq(RATIFIER.MIDNIGHT(), address(MIDNIGHT), 'ratifier bound to Midnight');
    assertEq(TICK % MIDNIGHT.tickSpacing(id), 0, 'tick spacing');

    collateral = _collateralFor(UNITS);

    (lender, lenderKey) = makeAddrAndKey('lender');
    (otherLender, otherLenderKey) = makeAddrAndKey('otherLender');
    _setUpMaker(lender);
    _setUpMaker(otherLender);

    vm.prank(borrower);
    MIDNIGHT.setIsAuthorized(address(manager), true, borrower);
  }

  // supplyCollateralAndBorrow

  function test_SupplyCollateralAndBorrow() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    uint256 expectedAssets = _assetsFor(UNITS);
    bytes memory ratifierData = _sign(offer, lenderKey);
    uint256 withdrawableBefore = MIDNIGHT.withdrawable(id);
    deal(address(WETH), borrower, collateral);

    vm.startPrank(borrower);
    WETH.approve(address(manager), collateral);
    vm.expectEmit(true, true, true, true, address(manager));
    emit Events.CollateralSuppliedAndBorrowed({
      user: borrower,
      id: id,
      collateralToken: address(WETH),
      collateralIndex: WETH_INDEX,
      collateralAssets: collateral,
      loanToken: address(USDC),
      units: UNITS,
      borrowedAssets: expectedAssets
    });
    uint256 borrowed = manager.supplyCollateralAndBorrow(offer, ratifierData, WETH_INDEX, collateral, UNITS, 0);
    vm.stopPrank();

    assertEq(borrowed, expectedAssets, 'borrowed assets');
    assertEq(USDC.balanceOf(borrower), expectedAssets, 'borrower loan balance');
    assertEq(MIDNIGHT.debt(id, borrower), UNITS, 'borrower debt');
    assertEq(MIDNIGHT.collateral(id, borrower, WETH_INDEX), collateral, 'borrower collateral');
    assertEq(MIDNIGHT.credit(id, lender), UNITS, 'lender credit');
    assertEq(MIDNIGHT.withdrawable(id), withdrawableBefore, 'withdrawable untouched');
    _assertManagerIsEmpty();
  }

  function testFuzz_SupplyCollateralAndBorrow(uint256 units) public {
    // 1 USDC .. 10M USDC
    units = bound(units, 1e6, 1e13);
    Offer memory offer = _lendOffer(lender, units);

    _borrow(offer, _sign(offer, lenderKey), _collateralFor(units), units);

    assertEq(MIDNIGHT.debt(id, borrower), units);
    assertTrue(MIDNIGHT.isHealthy(market, id, borrower));
    _assertManagerIsEmpty();
  }

  function test_RevertWhen_BorrowBelowMinAssets() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    bytes memory ratifierData = _sign(offer, lenderKey);
    uint256 expectedAssets = _assetsFor(UNITS);
    deal(address(WETH), borrower, collateral);

    vm.startPrank(borrower);
    WETH.approve(address(manager), collateral);
    vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientBorrowedAssets.selector, expectedAssets + 1, expectedAssets));
    manager.supplyCollateralAndBorrow(offer, ratifierData, WETH_INDEX, collateral, UNITS, expectedAssets + 1);
    vm.stopPrank();
  }

  function test_RevertWhen_InsufficientCollateral() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    bytes memory ratifierData = _sign(offer, lenderKey);
    uint256 halfCollateral = collateral / 2;
    deal(address(WETH), borrower, halfCollateral);

    vm.startPrank(borrower);
    WETH.approve(address(manager), halfCollateral);
    vm.expectRevert(IMidnight.SellerIsLiquidatable.selector);
    manager.supplyCollateralAndBorrow(offer, ratifierData, WETH_INDEX, halfCollateral, UNITS, 0);
    vm.stopPrank();
  }

  function test_RevertWhen_ManagerNotAuthorized() public {
    vm.prank(borrower);
    MIDNIGHT.setIsAuthorized(address(manager), false, borrower);

    Offer memory offer = _lendOffer(lender, UNITS);
    bytes memory ratifierData = _sign(offer, lenderKey);
    deal(address(WETH), borrower, collateral);

    vm.startPrank(borrower);
    WETH.approve(address(manager), collateral);
    vm.expectRevert(IMidnight.Unauthorized.selector);
    manager.supplyCollateralAndBorrow(offer, ratifierData, WETH_INDEX, collateral, UNITS, 0);
    vm.stopPrank();
  }

  function test_RevertWhen_ForgedSignature() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    bytes memory forged = _sign(offer, otherLenderKey);
    deal(address(WETH), borrower, collateral);

    vm.startPrank(borrower);
    WETH.approve(address(manager), collateral);
    vm.expectRevert(IEcrecoverRatifier.Unauthorized.selector);
    manager.supplyCollateralAndBorrow(offer, forged, WETH_INDEX, collateral, UNITS, 0);
    vm.stopPrank();
  }

  function test_RevertWhen_SellOffer() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    offer.buy = false;

    vm.prank(borrower);
    vm.expectRevert(Errors.NotABuyOffer.selector);
    manager.supplyCollateralAndBorrow(offer, '', WETH_INDEX, 0, UNITS, 0);
  }

  function test_RevertWhen_WrongMidnight() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    offer.market.midnight = address(0xBEEF);

    vm.prank(borrower);
    vm.expectRevert(abi.encodeWithSelector(Errors.WrongMidnight.selector, address(MIDNIGHT), address(0xBEEF)));
    manager.supplyCollateralAndBorrow(offer, '', WETH_INDEX, 0, UNITS, 0);
  }

  /// @dev Selling units first burns the seller's credit, so the same entry point lets a lender
  /// exit early by selling their credit into another lender's buy offer, without opening debt.
  function test_LenderEarlyExit() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    _borrow(offer, _sign(offer, lenderKey), collateral, UNITS);

    Offer memory exitOffer = _lendOffer(otherLender, UNITS);
    bytes memory ratifierData = _sign(exitOffer, otherLenderKey);
    uint256 expectedAssets = _assetsFor(UNITS);

    vm.startPrank(lender);
    MIDNIGHT.setIsAuthorized(address(manager), true, lender);
    uint256 balanceBefore = USDC.balanceOf(lender);
    manager.supplyCollateralAndBorrow(exitOffer, ratifierData, WETH_INDEX, 0, UNITS, expectedAssets);
    vm.stopPrank();

    assertEq(MIDNIGHT.credit(id, lender), 0, 'lender credit sold');
    assertEq(MIDNIGHT.debt(id, lender), 0, 'no debt opened');
    assertEq(MIDNIGHT.credit(id, otherLender), UNITS, 'credit moved to other lender');
    assertEq(USDC.balanceOf(lender) - balanceBefore, expectedAssets, 'exit proceeds');
  }

  // repayAndWithdraw

  function test_RepayAndWithdraw_FullPosition() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    _borrow(offer, _sign(offer, lenderKey), collateral, UNITS);
    uint256 withdrawableBefore = MIDNIGHT.withdrawable(id);
    vm.warp(MATURITY);
    _fundRepayment(borrower);

    vm.expectEmit(true, true, true, true, address(manager));
    emit Events.RepaidAndWithdrawn({
      user: borrower,
      id: id,
      loanToken: address(USDC),
      repaidUnits: UNITS,
      collateralToken: address(WETH),
      collateralIndex: WETH_INDEX,
      withdrawnAssets: collateral
    });
    vm.prank(borrower);
    (uint256 repaid, uint256 withdrawn) =
      manager.repayAndWithdraw(market, type(uint256).max, WETH_INDEX, type(uint256).max);

    assertEq(repaid, UNITS, 'repaid units');
    assertEq(withdrawn, collateral, 'withdrawn collateral');
    assertEq(MIDNIGHT.debt(id, borrower), 0, 'debt cleared');
    assertEq(MIDNIGHT.collateral(id, borrower, WETH_INDEX), 0, 'collateral cleared');
    assertEq(WETH.balanceOf(borrower), collateral, 'collateral returned');
    assertEq(MIDNIGHT.withdrawable(id) - withdrawableBefore, UNITS, 'repayment withdrawable for lenders');
    _assertManagerIsEmpty();
  }

  function test_RevertWhen_WithdrawLeavesPositionUnhealthy() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    _borrow(offer, _sign(offer, lenderKey), collateral, UNITS);

    vm.prank(borrower);
    vm.expectRevert(IMidnight.UnhealthyBorrower.selector);
    manager.repayAndWithdraw(market, 0, WETH_INDEX, collateral);
  }

  /// @dev The borrower authorized the manager, but every entry point acts on `msg.sender`,
  /// so a third party calling the manager can only ever touch their own (empty) position.
  function test_CannotTouchAnotherUsersPosition() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    _borrow(offer, _sign(offer, lenderKey), collateral, UNITS);

    vm.prank(attacker);
    (uint256 repaid, uint256 withdrawn) =
      manager.repayAndWithdraw(market, type(uint256).max, WETH_INDEX, type(uint256).max);

    assertEq(repaid, 0);
    assertEq(withdrawn, 0);
    assertEq(WETH.balanceOf(attacker), 0);
    assertEq(MIDNIGHT.collateral(id, borrower, WETH_INDEX), collateral, 'victim collateral untouched');
  }

  // redeem

  function test_Redeem_AfterRepayment() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    _borrow(offer, _sign(offer, lenderKey), collateral, UNITS);
    vm.warp(MATURITY);
    _fundRepayment(borrower);
    vm.prank(borrower);
    manager.repayAndWithdraw(market, type(uint256).max, WETH_INDEX, type(uint256).max);

    vm.startPrank(lender);
    MIDNIGHT.setIsAuthorized(address(manager), true, lender);
    uint256 balanceBefore = USDC.balanceOf(lender);
    vm.expectEmit(true, true, true, true, address(manager));
    emit Events.CreditRedeemed({user: lender, id: id, loanToken: address(USDC), units: UNITS});
    uint256 redeemed = manager.redeem(market, type(uint256).max);
    vm.stopPrank();

    assertEq(redeemed, UNITS, 'redeemed units');
    assertEq(USDC.balanceOf(lender) - balanceBefore, UNITS, '1 unit = 1 loan token');
    assertEq(MIDNIGHT.credit(id, lender), 0, 'credit cleared');
    _assertManagerIsEmpty();
  }

  /// @dev `otherLender` never bought units, so there is no credit to redeem even though the
  /// live market already has withdrawable liquidity from other borrowers' repayments.
  function test_RevertWhen_NothingToRedeem() public {
    vm.startPrank(otherLender);
    MIDNIGHT.setIsAuthorized(address(manager), true, otherLender);
    vm.expectRevert(Errors.NothingToRedeem.selector);
    manager.redeem(market, type(uint256).max);
    vm.stopPrank();
  }

  // views

  function test_MarketIdMatchesMidnight() public view {
    assertEq(manager.marketId(market), MARKET_ID);
  }

  function test_ImpliedRate() public view {
    assertEq(manager.impliedRate(UnitPrice.wrap(0.95e18), 365 days), 0.052631578947368421e18);
    assertEq(manager.impliedRate(UnitPrice.wrap(0.95e18), 182.5 days), 0.105263157894736842e18);
    assertEq(manager.impliedRate(UnitPrice.wrap(1e18), 30 days), 0);
  }

  function test_RevertWhen_ImpliedRateInvalidInputs() public {
    vm.expectRevert(abi.encodeWithSelector(Errors.InvalidUnitPrice.selector, 0));
    manager.impliedRate(UnitPrice.wrap(0), 365 days);

    vm.expectRevert(abi.encodeWithSelector(Errors.InvalidUnitPrice.selector, 1e18 + 1));
    manager.impliedRate(UnitPrice.wrap(1e18 + 1), 365 days);

    vm.expectRevert(Errors.ZeroTimeToMaturity.selector);
    manager.impliedRate(UnitPrice.wrap(0.95e18), 0);
  }

  // helpers

  /// @dev Loan tokens paid by a maker for `units` at `TICK`. The market charges no settlement fee.
  function _assetsFor(uint256 units) internal pure returns (uint256) {
    return (units * TickLib.tickToPrice(TICK)) / WAD;
  }

  /// @dev WETH needed to keep `units` of debt healthy at the fork's oracle price, plus a 1% buffer.
  /// Mirrors Midnight: `maxDebt = collateral * price / ORACLE_PRICE_SCALE * lltv / WAD`.
  function _collateralFor(uint256 units) internal view returns (uint256) {
    uint256 price = IOracle(WETH_ORACLE).price();
    return (units * ORACLE_PRICE_SCALE * WAD * 101) / (price * WETH_LLTV * 100) + 1;
  }

  function _setUpMaker(address maker) internal {
    deal(address(USDC), maker, 1e15);
    vm.startPrank(maker);
    MIDNIGHT.setIsAuthorized(address(RATIFIER), true, maker);
    USDC.approve(address(MIDNIGHT), type(uint256).max);
    vm.stopPrank();
  }

  function _lendOffer(address maker, uint256 maxUnits) internal view returns (Offer memory offer) {
    offer.market = market;
    offer.buy = true;
    offer.maker = maker;
    offer.start = block.timestamp;
    offer.expiry = block.timestamp + 1 days;
    offer.tick = TICK;
    offer.group = keccak256(abi.encode(maker, 'lend'));
    offer.ratifier = address(RATIFIER);
    // forge-lint: disable-next-line(unsafe-typecast) callers bound maxUnits far below 2^128.
    offer.maxUnits = uint128(maxUnits);
    offer.continuousFeeCap = type(uint256).max;
  }

  function _sign(Offer memory offer, uint256 privateKey) internal view returns (bytes memory) {
    bytes32 root = HashLib.hashOffer(offer);
    bytes32 structHash = keccak256(abi.encode(HashLib.offerTreeTypeHash(0), root));
    bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(RATIFIER)));
    (uint8 v, bytes32 r, bytes32 s) =
      vm.sign(privateKey, keccak256(bytes.concat('\x19\x01', domainSeparator, structHash)));
    return abi.encode(Signature({v: v, r: r, s: s}), root, uint256(0), new bytes32[](0));
  }

  function _borrow(Offer memory offer, bytes memory ratifierData, uint256 collateralAssets, uint256 units)
    internal
    returns (uint256)
  {
    deal(address(WETH), borrower, collateralAssets);
    vm.startPrank(borrower);
    WETH.approve(address(manager), collateralAssets);
    uint256 borrowed = manager.supplyCollateralAndBorrow(offer, ratifierData, WETH_INDEX, collateralAssets, units, 0);
    vm.stopPrank();
    return borrowed;
  }

  function _fundRepayment(address user) internal {
    deal(address(USDC), user, UNITS);
    vm.prank(user);
    USDC.approve(address(manager), UNITS);
  }

  function _assertManagerIsEmpty() internal view {
    assertEq(USDC.balanceOf(address(manager)), 0, 'manager loan balance');
    assertEq(WETH.balanceOf(address(manager)), 0, 'manager collateral balance');
    assertEq(USDC.allowance(address(manager), address(MIDNIGHT)), 0, 'manager loan allowance');
    assertEq(WETH.allowance(address(manager), address(MIDNIGHT)), 0, 'manager collateral allowance');
  }
}

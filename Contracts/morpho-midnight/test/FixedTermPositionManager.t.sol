// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Test} from 'forge-std/Test.sol';

// modules
import {FixedTermPositionManager, UnitPrice} from '../src/FixedTermPositionManager.sol';
import {Midnight} from 'midnight/Midnight.sol';
import {EcrecoverRatifier} from 'midnight/ratifiers/EcrecoverRatifier.sol';

// interfaces
import {IMidnight, Market, Offer, CollateralParams} from 'midnight/interfaces/IMidnight.sol';
import {
  IEcrecoverRatifier,
  Signature,
  EIP712_DOMAIN_TYPEHASH
} from 'midnight/ratifiers/interfaces/IEcrecoverRatifier.sol';

// libs
import {HashLib} from 'midnight/ratifiers/libraries/HashLib.sol';
import {TickLib} from 'midnight/libraries/TickLib.sol';

// mocks
import {ERC20} from 'midnight-test/erc20s/ERC20.sol';
import {Oracle} from 'midnight-test/helpers/Oracle.sol';

/// @dev Runs the manager against a local deployment of the real Midnight contract, with offers
/// signed through the production EcrecoverRatifier (single-offer tree: root = leaf, empty proof).
contract FixedTermPositionManagerTest is Test {
  uint256 internal constant LLTV = 0.77e18;
  uint256 internal constant LIQUIDATION_CURSOR = 0.3e18;
  uint256 internal constant TICK = 6000;
  uint256 internal constant UNITS = 1_000e18;
  uint256 internal constant COLLATERAL = 2_000e18;

  Midnight internal midnight;
  EcrecoverRatifier internal ratifier;
  FixedTermPositionManager internal manager;

  ERC20 internal loanToken;
  ERC20 internal collateralToken;
  Market internal market;
  bytes32 internal id;

  address internal lender;
  uint256 internal lenderKey;
  address internal otherLender;
  uint256 internal otherLenderKey;
  address internal borrower = makeAddr('borrower');
  address internal attacker = makeAddr('attacker');

  function setUp() public {
    midnight = new Midnight();
    ratifier = new EcrecoverRatifier(address(midnight));
    manager = new FixedTermPositionManager(IMidnight(address(midnight)));

    midnight.enableLltv(LLTV);
    midnight.enableLiquidationCursor(LIQUIDATION_CURSOR);

    loanToken = new ERC20('Loan', 'LOAN');
    collateralToken = new ERC20('Collateral', 'COLL');

    CollateralParams[] memory collateralParams = new CollateralParams[](1);
    collateralParams[0] = CollateralParams({
      token: address(collateralToken), lltv: LLTV, liquidationCursor: LIQUIDATION_CURSOR, oracle: address(new Oracle())
    });
    market = Market({
      chainId: block.chainid,
      midnight: address(midnight),
      loanToken: address(loanToken),
      collateralParams: collateralParams,
      maturity: block.timestamp + 30 days,
      rcfThreshold: 0,
      enterGate: address(0),
      liquidatorGate: address(0)
    });
    id = midnight.touchMarket(market);

    (lender, lenderKey) = makeAddrAndKey('lender');
    (otherLender, otherLenderKey) = makeAddrAndKey('otherLender');
    _setUpMaker(lender);
    _setUpMaker(otherLender);

    vm.prank(borrower);
    midnight.setIsAuthorized(address(manager), true, borrower);
  }

  // supplyCollateralAndBorrow

  function test_SupplyCollateralAndBorrow() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    uint256 expectedAssets = (UNITS * TickLib.tickToPrice(TICK)) / 1e18;

    uint256 borrowed = _borrow(offer, _sign(offer, lenderKey), COLLATERAL, UNITS);

    assertEq(borrowed, expectedAssets, 'borrowed assets');
    assertEq(loanToken.balanceOf(borrower), expectedAssets, 'borrower loan balance');
    assertEq(midnight.debt(id, borrower), UNITS, 'borrower debt');
    assertEq(midnight.collateral(id, borrower, 0), COLLATERAL, 'borrower collateral');
    assertEq(midnight.credit(id, lender), UNITS, 'lender credit');
    _assertManagerIsEmpty();
  }

  function testFuzz_SupplyCollateralAndBorrow(uint256 units) public {
    units = bound(units, 1e6, 1e27);
    uint256 collateral = (units * 1e18) / LLTV + 1;
    Offer memory offer = _lendOffer(lender, units);

    _borrow(offer, _sign(offer, lenderKey), collateral, units);

    assertEq(midnight.debt(id, borrower), units);
    assertTrue(midnight.isHealthy(market, id, borrower));
    _assertManagerIsEmpty();
  }

  function test_RevertWhen_BorrowBelowMinAssets() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    bytes memory ratifierData = _sign(offer, lenderKey);
    uint256 expectedAssets = (UNITS * TickLib.tickToPrice(TICK)) / 1e18;
    deal(address(collateralToken), borrower, COLLATERAL);

    vm.startPrank(borrower);
    collateralToken.approve(address(manager), COLLATERAL);
    vm.expectRevert(
      abi.encodeWithSelector(
        FixedTermPositionManager.InsufficientBorrowedAssets.selector, expectedAssets + 1, expectedAssets
      )
    );
    manager.supplyCollateralAndBorrow(offer, ratifierData, 0, COLLATERAL, UNITS, expectedAssets + 1);
    vm.stopPrank();
  }

  function test_RevertWhen_InsufficientCollateral() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    bytes memory ratifierData = _sign(offer, lenderKey);
    deal(address(collateralToken), borrower, 1_000e18);

    vm.startPrank(borrower);
    collateralToken.approve(address(manager), 1_000e18);
    vm.expectRevert(IMidnight.SellerIsLiquidatable.selector);
    manager.supplyCollateralAndBorrow(offer, ratifierData, 0, 1_000e18, UNITS, 0);
    vm.stopPrank();
  }

  function test_RevertWhen_ManagerNotAuthorized() public {
    vm.prank(borrower);
    midnight.setIsAuthorized(address(manager), false, borrower);

    Offer memory offer = _lendOffer(lender, UNITS);
    bytes memory ratifierData = _sign(offer, lenderKey);
    deal(address(collateralToken), borrower, COLLATERAL);

    vm.startPrank(borrower);
    collateralToken.approve(address(manager), COLLATERAL);
    vm.expectRevert(IMidnight.Unauthorized.selector);
    manager.supplyCollateralAndBorrow(offer, ratifierData, 0, COLLATERAL, UNITS, 0);
    vm.stopPrank();
  }

  function test_RevertWhen_ForgedSignature() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    bytes memory forged = _sign(offer, otherLenderKey);
    deal(address(collateralToken), borrower, COLLATERAL);

    vm.startPrank(borrower);
    collateralToken.approve(address(manager), COLLATERAL);
    vm.expectRevert(IEcrecoverRatifier.Unauthorized.selector);
    manager.supplyCollateralAndBorrow(offer, forged, 0, COLLATERAL, UNITS, 0);
    vm.stopPrank();
  }

  function test_RevertWhen_SellOffer() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    offer.buy = false;

    vm.prank(borrower);
    vm.expectRevert(FixedTermPositionManager.NotABuyOffer.selector);
    manager.supplyCollateralAndBorrow(offer, '', 0, 0, UNITS, 0);
  }

  function test_RevertWhen_WrongMidnight() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    offer.market.midnight = address(0xBEEF);

    vm.prank(borrower);
    vm.expectRevert(
      abi.encodeWithSelector(FixedTermPositionManager.WrongMidnight.selector, address(midnight), address(0xBEEF))
    );
    manager.supplyCollateralAndBorrow(offer, '', 0, 0, UNITS, 0);
  }

  /// @dev Selling units first burns the seller's credit, so the same entry point lets a lender
  /// exit early by selling their credit into another lender's buy offer, without opening debt.
  function test_LenderEarlyExit() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    _borrow(offer, _sign(offer, lenderKey), COLLATERAL, UNITS);

    Offer memory exitOffer = _lendOffer(otherLender, UNITS);
    bytes memory ratifierData = _sign(exitOffer, otherLenderKey);
    uint256 expectedAssets = (UNITS * TickLib.tickToPrice(TICK)) / 1e18;

    vm.startPrank(lender);
    midnight.setIsAuthorized(address(manager), true, lender);
    uint256 balanceBefore = loanToken.balanceOf(lender);
    manager.supplyCollateralAndBorrow(exitOffer, ratifierData, 0, 0, UNITS, expectedAssets);
    vm.stopPrank();

    assertEq(midnight.credit(id, lender), 0, 'lender credit sold');
    assertEq(midnight.debt(id, lender), 0, 'no debt opened');
    assertEq(midnight.credit(id, otherLender), UNITS, 'credit moved to other lender');
    assertEq(loanToken.balanceOf(lender) - balanceBefore, expectedAssets, 'exit proceeds');
  }

  // repayAndWithdraw

  function test_RepayAndWithdraw_FullPosition() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    _borrow(offer, _sign(offer, lenderKey), COLLATERAL, UNITS);
    vm.warp(market.maturity);
    _fundRepayment(borrower);

    vm.prank(borrower);
    (uint256 repaid, uint256 withdrawn) = manager.repayAndWithdraw(market, type(uint256).max, 0, type(uint256).max);

    assertEq(repaid, UNITS, 'repaid units');
    assertEq(withdrawn, COLLATERAL, 'withdrawn collateral');
    assertEq(midnight.debt(id, borrower), 0, 'debt cleared');
    assertEq(midnight.collateral(id, borrower, 0), 0, 'collateral cleared');
    assertEq(collateralToken.balanceOf(borrower), COLLATERAL, 'collateral returned');
    assertEq(midnight.withdrawable(id), UNITS, 'withdrawable for lenders');
    _assertManagerIsEmpty();
  }

  function test_RevertWhen_WithdrawLeavesPositionUnhealthy() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    _borrow(offer, _sign(offer, lenderKey), COLLATERAL, UNITS);

    vm.prank(borrower);
    vm.expectRevert(IMidnight.UnhealthyBorrower.selector);
    manager.repayAndWithdraw(market, 0, 0, COLLATERAL);
  }

  /// @dev The borrower authorized the manager, but every entry point acts on `msg.sender`,
  /// so a third party calling the manager can only ever touch their own (empty) position.
  function test_CannotTouchAnotherUsersPosition() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    _borrow(offer, _sign(offer, lenderKey), COLLATERAL, UNITS);

    vm.prank(attacker);
    (uint256 repaid, uint256 withdrawn) = manager.repayAndWithdraw(market, type(uint256).max, 0, type(uint256).max);

    assertEq(repaid, 0);
    assertEq(withdrawn, 0);
    assertEq(collateralToken.balanceOf(attacker), 0);
    assertEq(midnight.collateral(id, borrower, 0), COLLATERAL, 'victim collateral untouched');
  }

  // redeem

  function test_Redeem_AfterRepayment() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    _borrow(offer, _sign(offer, lenderKey), COLLATERAL, UNITS);
    vm.warp(market.maturity);
    _fundRepayment(borrower);
    vm.prank(borrower);
    manager.repayAndWithdraw(market, type(uint256).max, 0, type(uint256).max);

    vm.startPrank(lender);
    midnight.setIsAuthorized(address(manager), true, lender);
    uint256 balanceBefore = loanToken.balanceOf(lender);
    uint256 redeemed = manager.redeem(market, type(uint256).max);
    vm.stopPrank();

    assertEq(redeemed, UNITS, 'redeemed units');
    assertEq(loanToken.balanceOf(lender) - balanceBefore, UNITS, '1 unit = 1 loan token');
    assertEq(midnight.credit(id, lender), 0, 'credit cleared');
    _assertManagerIsEmpty();
  }

  function test_RevertWhen_NothingToRedeem() public {
    Offer memory offer = _lendOffer(lender, UNITS);
    _borrow(offer, _sign(offer, lenderKey), COLLATERAL, UNITS);

    vm.startPrank(lender);
    midnight.setIsAuthorized(address(manager), true, lender);
    vm.expectRevert(FixedTermPositionManager.NothingToRedeem.selector);
    manager.redeem(market, type(uint256).max);
    vm.stopPrank();
  }

  // views

  function test_MarketIdMatchesMidnight() public view {
    assertEq(manager.marketId(market), id);
  }

  function test_ImpliedRate() public view {
    assertEq(manager.impliedRate(UnitPrice.wrap(0.95e18), 365 days), 0.052631578947368421e18);
    assertEq(manager.impliedRate(UnitPrice.wrap(0.95e18), 182.5 days), 0.105263157894736842e18);
    assertEq(manager.impliedRate(UnitPrice.wrap(1e18), 30 days), 0);
  }

  function test_RevertWhen_ImpliedRateInvalidInputs() public {
    vm.expectRevert(abi.encodeWithSelector(FixedTermPositionManager.InvalidUnitPrice.selector, 0));
    manager.impliedRate(UnitPrice.wrap(0), 365 days);

    vm.expectRevert(abi.encodeWithSelector(FixedTermPositionManager.InvalidUnitPrice.selector, 1e18 + 1));
    manager.impliedRate(UnitPrice.wrap(1e18 + 1), 365 days);

    vm.expectRevert(FixedTermPositionManager.ZeroTimeToMaturity.selector);
    manager.impliedRate(UnitPrice.wrap(0.95e18), 0);
  }

  // helpers

  function _setUpMaker(address maker) internal {
    deal(address(loanToken), maker, 1e30);
    vm.startPrank(maker);
    midnight.setIsAuthorized(address(ratifier), true, maker);
    loanToken.approve(address(midnight), type(uint256).max);
    vm.stopPrank();
  }

  function _lendOffer(address maker, uint256 maxUnits) internal view returns (Offer memory offer) {
    offer.market = market;
    offer.buy = true;
    offer.maker = maker;
    offer.expiry = block.timestamp + 1 days;
    offer.tick = TICK;
    offer.group = keccak256(abi.encode(maker, 'lend'));
    offer.ratifier = address(ratifier);
    // forge-lint: disable-next-line(unsafe-typecast) callers bound maxUnits far below 2^128.
    offer.maxUnits = uint128(maxUnits);
    offer.continuousFeeCap = type(uint256).max;
  }

  function _sign(Offer memory offer, uint256 privateKey) internal view returns (bytes memory) {
    bytes32 root = HashLib.hashOffer(offer);
    bytes32 structHash = keccak256(abi.encode(HashLib.offerTreeTypeHash(0), root));
    bytes32 domainSeparator = keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, block.chainid, address(ratifier)));
    (uint8 v, bytes32 r, bytes32 s) =
      vm.sign(privateKey, keccak256(bytes.concat('\x19\x01', domainSeparator, structHash)));
    return abi.encode(Signature(v, r, s), root, uint256(0), new bytes32[](0));
  }

  function _borrow(Offer memory offer, bytes memory ratifierData, uint256 collateral, uint256 units)
    internal
    returns (uint256)
  {
    deal(address(collateralToken), borrower, collateral);
    vm.startPrank(borrower);
    collateralToken.approve(address(manager), collateral);
    uint256 borrowed = manager.supplyCollateralAndBorrow(offer, ratifierData, 0, collateral, units, 0);
    vm.stopPrank();
    return borrowed;
  }

  function _fundRepayment(address user) internal {
    deal(address(loanToken), user, UNITS);
    vm.prank(user);
    loanToken.approve(address(manager), UNITS);
  }

  function _assertManagerIsEmpty() internal view {
    assertEq(loanToken.balanceOf(address(manager)), 0, 'manager loan balance');
    assertEq(collateralToken.balanceOf(address(manager)), 0, 'manager collateral balance');
    assertEq(loanToken.allowance(address(manager), address(midnight)), 0, 'manager loan allowance');
    assertEq(collateralToken.allowance(address(manager), address(midnight)), 0, 'manager collateral allowance');
  }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// interfaces
import {IMidnight, Market, Offer} from 'midnight/interfaces/IMidnight.sol';

// libs
import {IdLib} from 'midnight/libraries/IdLib.sol';
import {SafeTransferLib} from 'midnight/libraries/SafeTransferLib.sol';
import {SafeApproveLib} from 'midnight/periphery/libraries/SafeApproveLib.sol';

// errors & events
import './Errors.sol' as Errors;
import './Events.sol' as Events;

// types & constants
import {UnitPrice} from './Types.sol';
import {WAD, MIDNIGHT_BASE_MAINNET} from './Constants.sol';

/// @title FixedTermPositionManager
/// @author Jean Cavallera (CJ42)
/// @notice Bundles common Morpho Midnight borrower and lender flows into single transactions.
/// Every action is performed for `msg.sender`, who must first authorize this contract on
/// Midnight with `setIsAuthorized(address(manager), true, msg.sender)`.
///
/// @dev Stateless and non-custodial: tokens only transit through this contract within a call,
/// and approvals to Midnight are for the exact amount pulled, so no allowance is left behind.
/// Because Midnight's authorization is all-or-nothing, every entry point hard-codes
/// `msg.sender` as both `onBehalf` and receiver, so a caller can only ever act on their own position.
///
/// The manager is bound at compile time to the Midnight deployment on Base mainnet, so there is
/// nothing to configure at deployment.
contract FixedTermPositionManager {
  /// @notice The Midnight instance every market must point to.
  IMidnight public constant MIDNIGHT = IMidnight(MIDNIGHT_BASE_MAINNET);

  /// @notice Supply collateral and borrow at a fixed rate by selling `units` into a lender's buy offer.
  ///
  /// @dev Collateral is supplied before the take, so Midnight's seller health check at the end of
  /// `take` already accounts for it. The maker pays for the units; loan tokens go to `msg.sender`.
  ///
  /// Midnight nets a sale against existing credit first: if `msg.sender` already holds credit in
  /// this market, it is burned before any debt is opened. With `collateralAssets == 0`, this
  /// function therefore doubles as an early exit for lenders.
  ///
  /// @param offer A maker offer with `buy == true` (the maker lends by buying units).
  /// @param ratifierData Data checked by `offer.ratifier` (e.g. signature + Merkle proof for the ecrecover ratifier).
  /// @param collateralIndex Index of the collateral in `offer.market.collateralParams`.
  /// @param collateralAssets Collateral to supply first. Can be 0 to borrow against existing collateral.
  /// @param units Units to sell, each one an obligation to repay 1 loan token at maturity.
  /// @param minBorrowedAssets Minimum loan tokens to receive, protecting against settlement fee changes.
  /// @return borrowedAssets Loan tokens received by `msg.sender`.
  function supplyCollateralAndBorrow(
    Offer calldata offer,
    bytes calldata ratifierData,
    uint256 collateralIndex,
    uint256 collateralAssets,
    uint256 units,
    uint256 minBorrowedAssets
  ) external returns (uint256 borrowedAssets) {
    _checkMarket(offer.market);
    require(offer.buy, Errors.NotABuyOffer());

    address collateralToken = offer.market.collateralParams[collateralIndex].token;

    if (collateralAssets > 0) {
      _pullAndApprove(collateralToken, collateralAssets);
      MIDNIGHT.supplyCollateral({
        market: offer.market, collateralIndex: collateralIndex, assets: collateralAssets, onBehalf: msg.sender
      });
    }

    (, borrowedAssets) = MIDNIGHT.take({
      offer: offer,
      ratifierData: ratifierData,
      units: units,
      taker: msg.sender,
      receiverIfTakerIsSeller: msg.sender,
      takerCallback: address(0),
      takerCallbackData: ''
    });
    require(borrowedAssets >= minBorrowedAssets, Errors.InsufficientBorrowedAssets(minBorrowedAssets, borrowedAssets));

    emit Events.CollateralSuppliedAndBorrowed({
      user: msg.sender,
      id: IdLib.toId(offer.market),
      collateralToken: collateralToken,
      collateralIndex: collateralIndex,
      collateralAssets: collateralAssets,
      loanToken: offer.market.loanToken,
      units: units,
      borrowedAssets: borrowedAssets
    });
  }

  /// @notice Repay debt and withdraw collateral in a single transaction.
  /// @dev Each debt unit costs exactly 1 loan token, pulled from `msg.sender`.
  /// Midnight reverts the withdrawal if the remaining position would be unhealthy.
  /// @param market The Midnight market of the position.
  /// @param units Debt units to repay. `type(uint256).max` repays the full debt.
  /// @param collateralIndex Index of the collateral to withdraw in `market.collateralParams`.
  /// @param collateralAssets Collateral to withdraw to `msg.sender`. `type(uint256).max` withdraws all of it.
  /// @return repaidUnits Debt units actually repaid.
  /// @return withdrawnAssets Collateral actually withdrawn.
  function repayAndWithdraw(Market calldata market, uint256 units, uint256 collateralIndex, uint256 collateralAssets)
    external
    returns (uint256 repaidUnits, uint256 withdrawnAssets)
  {
    _checkMarket(market);
    bytes32 id = IdLib.toId(market);

    repaidUnits = units == type(uint256).max ? MIDNIGHT.debt(id, msg.sender) : units;
    withdrawnAssets =
      collateralAssets == type(uint256).max ? MIDNIGHT.collateral(id, msg.sender, collateralIndex) : collateralAssets;

    if (repaidUnits > 0) {
      _pullAndApprove(market.loanToken, repaidUnits);
      MIDNIGHT.repay({market: market, units: repaidUnits, onBehalf: msg.sender, callback: address(0), data: ''});
    }

    if (withdrawnAssets > 0) {
      MIDNIGHT.withdrawCollateral({
        market: market,
        collateralIndex: collateralIndex,
        assets: withdrawnAssets,
        onBehalf: msg.sender,
        receiver: msg.sender
      });
    }

    emit Events.RepaidAndWithdrawn({
      user: msg.sender,
      id: id,
      loanToken: market.loanToken,
      repaidUnits: repaidUnits,
      collateralToken: market.collateralParams[collateralIndex].token,
      collateralIndex: collateralIndex,
      withdrawnAssets: withdrawnAssets
    });
  }

  /// @notice Redeem credit for loan tokens, 1 unit = 1 loan token, sent to `msg.sender`.
  /// @dev Redemption draws on the market's `withdrawable` liquidity, which fills up as borrowers
  /// repay or get liquidated, so credit may only be partially redeemable before maturity.
  /// @param market The Midnight market of the position.
  /// @param units Credit units to redeem. `type(uint256).max` redeems as much as currently possible.
  /// @return redeemedUnits Credit units actually redeemed.
  function redeem(Market calldata market, uint256 units) external returns (uint256 redeemedUnits) {
    _checkMarket(market);
    bytes32 id = IdLib.toId(market);

    if (units == type(uint256).max) {
      (uint128 credit,,) = MIDNIGHT.updatePositionView(market, id, msg.sender);
      uint256 withdrawable = MIDNIGHT.withdrawable(id);
      redeemedUnits = credit < withdrawable ? credit : withdrawable;
    } else {
      redeemedUnits = units;
    }
    require(redeemedUnits > 0, Errors.NothingToRedeem());

    MIDNIGHT.withdraw({market: market, units: redeemedUnits, onBehalf: msg.sender, receiver: msg.sender});

    emit Events.CreditRedeemed({user: msg.sender, id: id, loanToken: market.loanToken, units: redeemedUnits});
  }

  /// @notice Annualized fixed rate implied by a unit price, as simple (non-compounding) interest.
  /// @param price Unit price in WAD, in the range `(0, 1e18]`.
  /// @param timeToMaturity Seconds remaining until the market's maturity.
  /// @return rate Annual rate in WAD (e.g. `0.05e18` = 5% APR).
  function impliedRate(UnitPrice price, uint256 timeToMaturity) external pure returns (uint256 rate) {
    uint256 rawPrice = UnitPrice.unwrap(price);
    require(rawPrice > 0 && rawPrice <= WAD, Errors.InvalidUnitPrice(price));
    require(timeToMaturity > 0, Errors.ZeroTimeToMaturity());

    uint256 periodRate = (WAD * WAD) / rawPrice - WAD;
    rate = (periodRate * 365 days) / timeToMaturity;
  }

  /// @notice The id Midnight uses to key `market` in its storage getters.
  function marketId(Market calldata market) external pure returns (bytes32) {
    return IdLib.toId(market);
  }

  function _pullAndApprove(address token, uint256 amount) internal {
    SafeTransferLib.safeTransferFrom(token, msg.sender, address(this), amount);
    SafeApproveLib.safeApprove(token, address(MIDNIGHT), amount);
  }

  function _checkMarket(Market calldata market) internal pure {
    require(market.midnight == address(MIDNIGHT), Errors.WrongMidnight(address(MIDNIGHT), market.midnight));
  }
}

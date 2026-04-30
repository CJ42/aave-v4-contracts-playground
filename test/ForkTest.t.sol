// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

// import {ChainIds, ChainHelpers} from 'solidity-utils/src/contracts/utils/ChainHelpers.sol';
import {Test, console} from 'forge-std/Test.sol';

// interfaces
import {IERC20} from 'forge-std/interfaces/IERC20.sol';
import {ISpoke} from 'aave-v4/src/spoke/interfaces/ISpoke.sol';
import {IPriceOracle} from 'aave-v4/src/spoke/interfaces/IPriceOracle.sol';

// libs
import {EthereumSpokes} from 'src/libraries/EthereumSpokes.sol';
import {MainSpokeReserveIds} from 'src/libraries/Reserves.sol';

// helpers
import 'src/libraries/UserData.sol' as UserDataLib;

using {UserDataLib.getHealthFactor} for ISpoke;

// types
import {HealthFactor} from 'src/Types.sol';

contract ForkTest is Test {
  address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

  ISpoke constant MAIN_SPOKE = EthereumSpokes.MAIN_SPOKE;

  string internal constant USER = 'User';
  address internal user = makeAddr(USER);

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('mainnet'), 24975000);

    // equivalent of 100$ worth of ETH
    uint256 suppliedAmount = 44000000000000000;

    deal(address(WETH), user, suppliedAmount + 100 gwei);

    vm.prank(user);
    IERC20(WETH).approve(address(MAIN_SPOKE), suppliedAmount);

    vm.prank(user);
    MAIN_SPOKE.supply(MainSpokeReserveIds.WETH, suppliedAmount, user);

    vm.prank(user);
    MAIN_SPOKE.setUsingAsCollateral(MainSpokeReserveIds.WETH, true, user);
  }

  /// @dev This test assumes user already deposited WETH into the main spoke
  function test_UserPositionSuppliedWETH() public view {
    // struct UserPosition {
    //     uint128 drawnShares;
    //     uint128 realizedPremium;
    //     //
    //     uint128 premiumShares;
    //     uint128 premiumOffset;
    //     //
    //     uint128 suppliedShares;
    //     uint16 configKey; // key of the last user config
    // }
    ISpoke.UserPosition memory userPosition = MAIN_SPOKE.getUserPosition({
      reserveId: MainSpokeReserveIds.WETH,
      user: user
    });

    assertGt(userPosition.suppliedShares, 0);

    uint256 assetsSupplied = MAIN_SPOKE.getUserSuppliedAssets(
      MainSpokeReserveIds.WETH,
      user
    );
    assertGt(assetsSupplied, 0);

    // shares must be lower than the actual assets amount
    assertLt(userPosition.suppliedShares, assetsSupplied);

    console.log('drawnShares', userPosition.drawnShares);
    console.log('premiumShares', userPosition.premiumShares);
    //
    console.log('premiumOffsetRay', userPosition.premiumOffsetRay);
    //
    console.log('suppliedShares', userPosition.suppliedShares);
    console.log('dynamicConfigKey', userPosition.dynamicConfigKey);
  }

  function test_BorrowUsdc() public {
    // CHECK nothing was borrowed
    ISpoke.UserPosition memory userPosition = MAIN_SPOKE.getUserPosition({
      reserveId: MainSpokeReserveIds.USDC,
      user: user
    });
    assertEq(userPosition.drawnShares, 0);

    // CHECK health factor
    uint256 healthFactorBefore = HealthFactor.unwrap(
      MAIN_SPOKE.getHealthFactor(user)
    );

    // If user has no debt, `getUserAccountData` should return `type(uint256).max`
    /// @dev See `Spoke.sol`, function: `_processUserAccountData(address,bool)`
    assertEq(healthFactorBefore, type(uint256).max);

    uint256 assetsBorrowed = MAIN_SPOKE.getUserTotalDebt(
      MainSpokeReserveIds.USDC,
      user
    );
    assertEq(assetsBorrowed, 0);

    uint256 initialUsdcBalance = USDC.balanceOf(user);

    // USDC has 6 decimal, but the interface is always the source of truth
    uint256 amountToBorrow = 20 * (10 ** USDC.decimals());

    vm.prank(user);
    MAIN_SPOKE.borrow(MainSpokeReserveIds.USDC, amountToBorrow, user);

    uint256 finalUsdcBalance = USDC.balanceOf(user);
    assertGt(finalUsdcBalance, initialUsdcBalance);
    assertEq(initialUsdcBalance + amountToBorrow, finalUsdcBalance);

    userPosition = MAIN_SPOKE.getUserPosition({
      reserveId: MainSpokeReserveIds.USDC,
      user: user
    });
    assertGt(userPosition.drawnShares, 0);
    assertLt(userPosition.drawnShares, amountToBorrow);
  }
}

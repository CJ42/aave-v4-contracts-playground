// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

// import {ChainIds, ChainHelpers} from 'solidity-utils/src/contracts/utils/ChainHelpers.sol';
import {Test, console} from 'forge-std/Test.sol';

// interfaces
import {IERC20} from 'forge-std/interfaces/IERC20.sol';
import {ISpoke} from 'aave-v4/src/spoke/interfaces/ISpoke.sol';

// libs
import {EthereumSpokes} from 'src/libraries/EthereumSpokes.sol';
import {MainSpokeReserveIds} from 'src/libraries/Reserves.sol';
contract ForkTest is Test {
  address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

  ISpoke constant MAIN_SPOKE = EthereumSpokes.MAIN_SPOKE;

  /// @dev Using immutable type here allows to bypass the Solidity compiler error flagging the initial value
  /// must be a compile-time constant. While also reducing the level of setup (since this address is never changed)
  address immutable USER = vm.envAddress('USER');

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
      user: USER
    });

    assertGt(userPosition.suppliedShares, 0);

    uint256 assetsSupplied = MAIN_SPOKE.getUserSuppliedAssets(
      MainSpokeReserveIds.WETH,
      USER
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
      user: USER
    });
    assertEq(userPosition.drawnShares, 0);

    uint256 assetsBorrowed = MAIN_SPOKE.getUserTotalDebt(
      MainSpokeReserveIds.USDC,
      USER
    );
    assertEq(assetsBorrowed, 0);

    uint256 initialUsdcBalance = USDC.balanceOf(USER);

    // USDC has 6 decimal, but the interface is always the source of truth
    uint256 amountToBorrow = 80 * (10 ** USDC.decimals());

    vm.prank(USER);
    MAIN_SPOKE.borrow(MainSpokeReserveIds.USDC, amountToBorrow, USER);

    uint256 finalUsdcBalance = USDC.balanceOf(USER);
    assertGt(finalUsdcBalance, initialUsdcBalance);
    assertEq(initialUsdcBalance + amountToBorrow, finalUsdcBalance);

    userPosition = MAIN_SPOKE.getUserPosition({
      reserveId: MainSpokeReserveIds.USDC,
      user: USER
    });
    assertGt(userPosition.drawnShares, 0);
    assertLt(userPosition.drawnShares, amountToBorrow);
    console.log('drawnShares', userPosition.drawnShares);
    console.log('premiumShares', userPosition.premiumShares);
    console.log('premiumOffsetRay', userPosition.premiumOffsetRay);
    console.log('suppliedShares', userPosition.suppliedShares);
    console.log('dynamicConfigKey', userPosition.dynamicConfigKey);
  }
}

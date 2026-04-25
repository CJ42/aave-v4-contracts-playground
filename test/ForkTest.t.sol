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
contract ForkTest is Test {
  address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

  ISpoke constant MAIN_SPOKE = EthereumSpokes.MAIN_SPOKE;

  /// @dev Using immutable type here allows to bypass the Solidity compiler error flagging the initial value
  /// must be a compile-time constant. While also reducing the level of setup (since this address is never changed)
  address immutable USER = vm.envAddress('USER');

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('mainnet'));
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

    // CHECK health factor
    ISpoke.UserAccountData memory userAccountData = MAIN_SPOKE
      .getUserAccountData(USER);
    uint256 healthFactorBefore = userAccountData.healthFactor;

    // If user has no debt, `getUserAccountData` should return `type(uint256).max`
    /// @dev See `Spoke.sol`, function: `_processUserAccountData(address,bool)`
    assertEq(healthFactorBefore, type(uint256).max);

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

    // TODO: optionally write to a JSON file to easily read the data in a spreadsheet
    console.log('drawnShares', userPosition.drawnShares);
    console.log('premiumShares', userPosition.premiumShares);
    console.log('premiumOffsetRay', userPosition.premiumOffsetRay);
    console.log('suppliedShares', userPosition.suppliedShares);
    console.log('dynamicConfigKey', userPosition.dynamicConfigKey);

    userAccountData = MAIN_SPOKE.getUserAccountData(USER);
    uint256 healthFactorAfter = userAccountData.healthFactor;

    // CHECK health factor decreased after borrowing
    assertLt(healthFactorAfter, healthFactorBefore);
    console.log('healthFactorAfter', healthFactorAfter);

    // Get the right number of decimals to simulate the returned price drop
    uint256 reservePriceDecimals = IPriceOracle(MAIN_SPOKE.ORACLE()).decimals();

    // To simulate the health factor dropping, we need to lower the ETH/USD price
    // We can do this by mocking the price returned by the ETH/USD price feed oracle
    vm.mockCall(
      address(MAIN_SPOKE.ORACLE()),
      abi.encodeCall(IPriceOracle.getReservePrice, (MainSpokeReserveIds.WETH)),
      // 📉 answer (ETH price dropped to $1,500)
      // TODO: refactor to make the price drop dynamically by 30%, not a fixed value
      abi.encode(uint256(1500 * (10 ** reservePriceDecimals)))
    );

    // CHECK health factor decreased after lowering the ETH/USD price
    userAccountData = MAIN_SPOKE.getUserAccountData(USER);
    uint256 healthFactorAfterDrop = userAccountData.healthFactor;
    console.log('healthFactorAfterDrop', healthFactorAfterDrop);
    // assertLt(healthFactorAfterDrop, healthFactorAfter);
  }
}

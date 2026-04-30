// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Test environnement
import {Test} from 'forge-std/Test.sol';
import {EIP712Helpers} from 'aave-v4/tests/helpers/spoke/EIP712Helpers.sol';
import {SetupHelpers} from 'aave-v4/tests/helpers/commons/SetupHelpers.sol';

// modules
import {LiquidationProtectionManager} from '../src/LiquidationProtectionManager.sol';

// interfaces
import {IERC20} from 'forge-std/interfaces/IERC20.sol';
import {IPriceOracle} from 'aave-v4/src/spoke/interfaces/IPriceOracle.sol';
import {ISpoke} from 'aave-v4/src/spoke/interfaces/ISpoke.sol';
import {ISignatureGateway} from 'aave-v4/src/position-manager/interfaces/ISignatureGateway.sol';

// libs
import {EthereumSpokes} from 'src/libraries/EthereumSpokes.sol';
import {MainSpokeReserveIds} from 'src/libraries/Reserves.sol';
import 'src/libraries/UserData.sol' as UserDataLib;

using {UserDataLib.getHealthFactor} for ISpoke;

// types
import '../src/Types.sol';

contract LiquidationProtectionManagerTest is Test, EIP712Helpers, SetupHelpers {
  /// @dev Taken from https://github.com/aave/aave-v4/blob/af1f0f2ba323ac6fbaaee3abf6be060c78e22d35/tests/setup/BaseState.sol#L80
  uint256 public constant MAX_SKIP_TIME = 10_000 days;

  ISpoke constant MAIN_SPOKE = EthereumSpokes.MAIN_SPOKE;
  IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
  address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

  address constant MAIN_SPOKE_CONFIGURATOR = 0x9BFFf48BFb5A7AE70c348d4d4cb97E8DEFa5389a;

  LiquidationProtectionManager public positionManager;

  string internal constant USER = 'User';
  address internal user = makeAddr(USER);
  uint256 internal userPrivateKey = _makeKey(USER);
  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('mainnet'));

    positionManager = new LiquidationProtectionManager(user);

    vm.prank(user);
    positionManager.registerOperator(address(this), true);

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

  function test_Deployment() public view {
    assertEq(positionManager.owner(), user);
  }

  function test_registerSpokeInPositionManager() public {
    assertFalse(
      positionManager.isSpokeRegistered(address(EthereumSpokes.MAIN_SPOKE))
    );

    vm.prank(user);
    positionManager.registerSpoke(address(EthereumSpokes.MAIN_SPOKE), true);

    assertTrue(
      positionManager.isSpokeRegistered(address(EthereumSpokes.MAIN_SPOKE))
    );
  }

  function _registerPositionManagerInSpoke() public {
    assertFalse(
      EthereumSpokes.MAIN_SPOKE.isPositionManager(
        user,
        address(positionManager)
      )
    );

    // First register the spoke
    vm.prank(user);
    positionManager.registerSpoke(address(EthereumSpokes.MAIN_SPOKE), true);

    ISpoke.PositionManagerUpdate[]
      memory updates = new ISpoke.PositionManagerUpdate[](1);

    // use named params in struct for readability of field `true` passed. This helps when `p` is referenced below when
    // calling the function `setSelfAsUserPositionManagerWithSig(...)`.
    updates[0] = ISpoke.PositionManagerUpdate({
      positionManager: address(positionManager),
      approve: true
    });

    uint192 nonceKey = 1;

    ISpoke.SetUserPositionManagers memory p = ISpoke.SetUserPositionManagers({
      onBehalfOf: user,
      updates: updates,
      nonce: EthereumSpokes.MAIN_SPOKE.nonces(user, nonceKey),
      // deadline: _warpBeforeRandomDeadline(MAX_SKIP_TIME)
      deadline: block.timestamp + 100 days
    });

    // use overloaded function below
    // function _getTypedDataHash(
    //     ISpoke spoke,
    //     ISpoke.SetUserPositionManagers memory setUserPositionManagers
    // ) internal view returns (bytes32) {
    //
    /// @dev See: https://github.com/aave/aave-v4/blob/af1f0f2ba323ac6fbaaee3abf6be060c78e22d35/tests/helpers/spoke/EIP712Helpers.sol#L34-L46
    bytes32 signatureDigest = _getTypedDataHashLocal(
      EthereumSpokes.MAIN_SPOKE,
      p
    );

    bytes memory signature = _sign(userPrivateKey, signatureDigest);

    vm.prank(user);
    positionManager.setSelfAsUserPositionManagerWithSig({
      spoke: address(EthereumSpokes.MAIN_SPOKE),
      onBehalfOf: p.onBehalfOf,
      approve: p.updates[0].approve,
      nonce: p.nonce,
      deadline: p.deadline,
      signature: signature
    });

    _assertNonceIncrement(
      ISignatureGateway(address(EthereumSpokes.MAIN_SPOKE)),
      user,
      p.nonce
    ); // note: nonce consumed on Main Spoke

    vm.prank(MAIN_SPOKE_CONFIGURATOR);
    MAIN_SPOKE.updatePositionManager(address(positionManager), true);

    // CHECK the position manager is now registered in the Spoke
    assertTrue(
      EthereumSpokes.MAIN_SPOKE.isPositionManager(
        user,
        address(positionManager)
      )
    );
  }

  function test_LiquidationProtectionManager() public {
    uint256 assetsBorrowed = MAIN_SPOKE.getUserTotalDebt(
      MainSpokeReserveIds.USDC,
      user
    );
    assertEq(assetsBorrowed, 0);

    uint256 healthFactorBefore = HealthFactor.unwrap(
      MAIN_SPOKE.getHealthFactor(user)
    );
    uint256 initialUsdcBalance = USDC.balanceOf(user);

    // USDC has 6 decimal, but the interface is always the source of truth
    uint256 amountToBorrow = 80 * (10 ** USDC.decimals());

    vm.prank(user);
    MAIN_SPOKE.borrow(MainSpokeReserveIds.USDC, amountToBorrow, user);

    uint256 finalUsdcBalance = USDC.balanceOf(user);
    assertGt(finalUsdcBalance, initialUsdcBalance);
    assertEq(initialUsdcBalance + amountToBorrow, finalUsdcBalance);

    ISpoke.UserPosition memory userPosition = MAIN_SPOKE.getUserPosition({
      reserveId: MainSpokeReserveIds.USDC,
      user: user
    });
    assertGt(userPosition.drawnShares, 0);
    assertLt(userPosition.drawnShares, amountToBorrow);

    uint256 healthFactorAfter = HealthFactor.unwrap(
      MAIN_SPOKE.getHealthFactor(user)
    );

    // CHECK health factor decreased after borrowing
    assertLt(healthFactorAfter, healthFactorBefore);

    // Get the right number of decimals to simulate the returned price drop
    uint256 reservePriceDecimals = IPriceOracle(MAIN_SPOKE.ORACLE()).decimals();

    // To simulate the health factor dropping, we need to lower the ETH/USD price
    // We can do this by mocking the price returned by the ETH/USD price feed oracle
    vm.mockCall(
      address(MAIN_SPOKE.ORACLE()),
      abi.encodeCall(IPriceOracle.getReservePrice, (MainSpokeReserveIds.WETH)),
      // 📉 answer (ETH price dropped to $1,500)
      abi.encode(uint256(1500 * (10 ** reservePriceDecimals)))
    );

    // CHECK health factor decreased after lowering the ETH/USD price
    uint256 healthFactorAfterDrop = HealthFactor.unwrap(
      MAIN_SPOKE.getHealthFactor(user)
    );
    assertLt(healthFactorAfterDrop, healthFactorAfter);

    // --------------------
    // Position Manager functionalities
    // --------------------
    _registerPositionManagerInSpoke();

    deal(address(USDC), user, 300 * (10 ** USDC.decimals()));
    
    // Deposit USDC in Position Manager to repay debt
    // 50% of the amount initially borrowed
    uint256 repayAmount = 40 * (10 ** USDC.decimals());

    vm.prank(user);
    IERC20(USDC).approve(address(positionManager), repayAmount);

    vm.prank(user);
    positionManager.depositFunds(address(USDC), repayAmount);

    // Execute protection
    positionManager.executeProtection(
      MAIN_SPOKE,
      MainSpokeReserveIds.USDC,
      repayAmount
    );

    uint256 newHealthFactor = HealthFactor.unwrap(
      MAIN_SPOKE.getHealthFactor(user)
    );
    assertGt(newHealthFactor, healthFactorAfterDrop);
  }

  /// @dev Workaround to not use the `EIP712Helpers` contract from `aave-v4` as the `JsonBindings.sol` are not available locally
  function _getTypedDataHashLocal(
    ISpoke spoke,
    ISpoke.SetUserPositionManagers memory setUserPositionManagers
  ) internal view returns (bytes32) {
    return
      keccak256(
        abi.encodePacked(
          '\x19\x01',
          spoke.DOMAIN_SEPARATOR(),
          vm.eip712HashStruct(
            // hardcoded type hashes
            'SetUserPositionManagers(address onBehalfOf,PositionManagerUpdate[] updates,uint256 nonce,uint256 deadline)PositionManagerUpdate(address positionManager,bool approve)',
            abi.encode(setUserPositionManagers)
          )
        )
      );
  }
}

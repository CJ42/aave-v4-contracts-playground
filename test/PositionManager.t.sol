// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Test environnement
import {Test} from 'forge-std/Test.sol';
import {EIP712Helpers} from 'aave-v4/tests/helpers/spoke/EIP712Helpers.sol';
import {SetupHelpers} from 'aave-v4/tests/helpers/commons/SetupHelpers.sol';
// import {Base as AaveV4BaseTest} from 'aave-v4/tests/setup/Base.t.sol';

// import 'tests/setup/Base.t.sol';

// modules
import {LiquidationProtectionManager} from '../src/LiquidationProtectionManager.sol';

// interfaces
import {ISpoke} from 'aave-v4/src/spoke/interfaces/ISpoke.sol';
import {ISignatureGateway} from 'aave-v4/src/position-manager/interfaces/ISignatureGateway.sol';

// libs
import {EthereumSpokes} from 'src/libraries/EthereumSpokes.sol';

contract PositionManagerTest is Test, EIP712Helpers, SetupHelpers {
  /// @dev Taken from https://github.com/aave/aave-v4/blob/af1f0f2ba323ac6fbaaee3abf6be060c78e22d35/tests/setup/BaseState.sol#L80
  uint256 public constant MAX_SKIP_TIME = 10_000 days;

  LiquidationProtectionManager public positionManager;

  string internal constant USER = 'User';
  address internal user = makeAddr(USER);
  uint256 internal userPrivateKey = _makeKey(USER);
  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('mainnet'));

    positionManager = new LiquidationProtectionManager(user);
  }

  function test_Deployment() public {
    assertEq(positionManager.owner(), user);
  }

  function test_registerSpokeInPositionManager() public {
    assertFalse(
      positionManager.isSpokeRegistered(address(EthereumSpokes.MAIN_SPOKE))
    );

    positionManager.registerSpoke(address(EthereumSpokes.MAIN_SPOKE), true);

    assertTrue(
      positionManager.isSpokeRegistered(address(EthereumSpokes.MAIN_SPOKE))
    );
  }

  function test_registerPositionManagerInSpoke() public {
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

    ISpoke.SetUserPositionManagers memory p = ISpoke.SetUserPositionManagers({
      onBehalfOf: user,
      updates: updates,
      nonce: EthereumSpokes.MAIN_SPOKE.nonces(user, _randomNonceKey()),
      deadline: _warpBeforeRandomDeadline(MAX_SKIP_TIME)
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

    // CHECK the position manager is now registered in the Spoke
    assertTrue(
      EthereumSpokes.MAIN_SPOKE.isPositionManager(
        user,
        address(positionManager)
      )
    );
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

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import {Test} from 'forge-std/Test.sol';
import {ReserveUtilization} from '../src/ReserveUtilization.sol';
import {ISpoke} from 'aave-v4/src/spoke/interfaces/ISpoke.sol';

contract ReserveUtilizationTest is Test {
  ReserveUtilization internal reserveUtilization;
  ISpoke internal spoke;
  uint256 internal reserveId;

  function setUp() public {
    vm.createSelectFork(vm.envString("RPC_URL"));

    address spokeAddress = vm.envAddress("SPOKE_ADDRESS");
    require(spokeAddress != address(0), "SPOKE_ADDRESS not set");
    reserveId = vm.envUint("RESERVE_ID");

    spoke = ISpoke(spokeAddress);
    reserveUtilization = new ReserveUtilization(spokeAddress);
  }

  function test_getReserveUtilizationMatchesSpoke() public view {
    (uint256 suppliedAssets, uint256 totalDebt, uint256 utilizationWad) =
      reserveUtilization.getReserveUtilization(reserveId);

    uint256 expectedAssets = spoke.getReserveSuppliedAssets(reserveId);
    uint256 expectedDebt = spoke.getReserveTotalDebt(reserveId);
    uint256 expectedUtilization = expectedAssets == 0
      ? 0
      : (expectedDebt * 1e18) / expectedAssets;

    assertEq(suppliedAssets, expectedAssets, "suppliedAssets mismatch");
    assertEq(totalDebt, expectedDebt, "totalDebt mismatch");
    assertEq(utilizationWad, expectedUtilization, "utilization mismatch");
  }
}

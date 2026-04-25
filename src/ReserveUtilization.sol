// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

// import {ISpoke} from 'aave-v4/src/spoke/interfaces/ISpoke.sol';

// contract ReserveUtilization {
//   ISpoke public immutable SPOKE;

//   constructor(address spoke) {
//     require(spoke != address(0), 'INVALID_SPOKE');
//     SPOKE = ISpoke(spoke);
//   }

//   function getReserveUtilization(
//     uint256 reserveId
//   )
//     external
//     view
//     returns (uint256 suppliedAssets, uint256 totalDebt, uint256 utilization)
//   {
//     suppliedAssets = SPOKE.getReserveSuppliedAssets(reserveId);
//     totalDebt = SPOKE.getReserveTotalDebt(reserveId);

//     if (suppliedAssets == 0) {
//       utilization = 0;
//     } else {
//       utilization = (totalDebt * 1e18) / suppliedAssets;
//     }
//   }
// }

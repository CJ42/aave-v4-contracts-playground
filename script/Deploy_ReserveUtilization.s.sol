// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import {Script} from 'forge-std/Script.sol';
import {console} from 'forge-std/Test.sol';
import {ReserveUtilization} from '../src/ReserveUtilization.sol';

contract DeployReserveUtilization is Script {
  function run() external {
    address spoke = vm.envAddress('SPOKE_ADDRESS');
    console.log('Deploying ReserveUtilization', spoke);

    uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
    vm.startBroadcast(deployerPrivateKey);
    ReserveUtilization reserveUtilization = new ReserveUtilization(spoke);
    vm.stopBroadcast();

    console.log('ReserveUtilization deployed at', address(reserveUtilization));
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MonadPay} from "../src/MonadPay.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        MonadPay pay = new MonadPay();
        vm.stopBroadcast();
        console.log("MonadPay:", address(pay));
    }
}

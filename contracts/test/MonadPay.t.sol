// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MonadPay} from "../src/MonadPay.sol";

contract MonadPayTest is Test {
    MonadPay pay;
    address payable merchant = payable(address(0xBEEF));
    address payer = address(0xCAFE);

    event Paid(address indexed merchant, bytes32 indexed invoiceId, address indexed payer, uint256 amount, string memo);

    function setUp() public {
        pay = new MonadPay();
        vm.deal(payer, 10 ether);
    }

    function test_PayForwardsAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit Paid(merchant, bytes32("inv1"), payer, 1 ether, "Coffee");
        vm.prank(payer);
        pay.pay{value: 1 ether}(merchant, bytes32("inv1"), "Coffee");
        assertEq(merchant.balance, 1 ether);
        assertEq(address(pay).balance, 0);
    }

    function test_RevertZero() public {
        vm.prank(payer);
        vm.expectRevert(MonadPay.ZeroAmount.selector);
        pay.pay(merchant, bytes32("x"), "");
    }
}

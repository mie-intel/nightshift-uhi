// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DemoToken} from "../../src/mocks/DemoToken.sol";
import {DemoFaucet} from "../../src/mocks/DemoFaucet.sol";

contract DemoFaucetTest is Test {
    DemoToken stock;
    DemoToken usd;
    DemoFaucet faucet;
    address alice = makeAddr("alice");

    function setUp() public {
        stock = new DemoToken("Demo Stock", "dSTOCK", 18);
        usd = new DemoToken("Demo USD", "dUSD", 6);
        faucet = new DemoFaucet(stock, usd, 10e18, 2000e6, 6 hours);
        stock.setMinter(address(faucet), true);
        usd.setMinter(address(faucet), true);
    }

    function test_claim_mintsBoth() public {
        vm.expectEmit(true, false, false, true, address(faucet));
        emit DemoFaucet.Claimed(alice, 10e18, 2000e6);
        vm.prank(alice);
        faucet.claim();
        assertEq(stock.balanceOf(alice), 10e18);
        assertEq(usd.balanceOf(alice), 2000e6);
    }

    function test_claim_cooldown() public {
        vm.startPrank(alice);
        faucet.claim();
        vm.expectRevert(abi.encodeWithSelector(DemoFaucet.TooSoon.selector, block.timestamp + 6 hours));
        faucet.claim();
        vm.warp(block.timestamp + 6 hours);
        faucet.claim();
        vm.stopPrank();
        assertEq(stock.balanceOf(alice), 20e18);
    }

    function test_nextClaimAt() public {
        assertEq(faucet.nextClaimAt(alice), 0);
        vm.prank(alice);
        faucet.claim();
        assertEq(faucet.nextClaimAt(alice), block.timestamp + 6 hours);
    }

    function test_claim_revert_withoutMinterRole() public {
        stock.setMinter(address(faucet), false);
        vm.prank(alice);
        vm.expectRevert(DemoToken.NotMinter.selector);
        faucet.claim();
    }
}

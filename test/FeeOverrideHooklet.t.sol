// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import { FeeOverrideHooklet } from "../src/FeeOverrideHooklet.sol";
import { PoolId } from "v4-core/src/types/PoolId.sol";

contract FeeOverrideHookletTest is Test {

    uint256 unichainFork;
    FeeOverrideHooklet public feeOverrideHooklet;
    address constant bunniHub = 0x00000091Cb2d7914C9cd196161Da0943aB7b92E1;

    function setUp() public {
        unichainFork = vm.createFork(vm.rpcUrl("unichain"));
        vm.selectFork(unichainFork);
        feeOverrideHooklet = new FeeOverrideHooklet(bunniHub);
    }

    function test1() public {
        PoolId poolId = PoolId.wrap(0xeec51c6b1a9e7c4bb4fc4fa9a02fc4fff3fe94efd044f895d98b5bfbd2ff9433);
        address bunniTokenOwner = 0x9a8FEe232DCF73060Af348a1B62Cdb0a19852d13;
        uint24 newFee = 10000;

        address nonOwner = address(1);
        vm.startPrank(nonOwner);
        vm.expectRevert(FeeOverrideHooklet.FeeOverrideHooklet__NotBunniTokenOwner.selector);
        feeOverrideHooklet.setFeeOverride(poolId, true, newFee, true, newFee);
        vm.stopPrank();

        vm.startPrank(bunniTokenOwner);
        feeOverrideHooklet.setFeeOverride(poolId, true, newFee, true, newFee);
        (bool overrideZeroToOne, uint24 feeZeroToOne, bool overrideOneToZero, uint24 feeOneToZero) = feeOverrideHooklet.feeOverrides(poolId);
        assertEq(overrideZeroToOne, true);
        assertEq(feeZeroToOne, newFee);
        assertEq(overrideOneToZero, true);
        assertEq(feeOneToZero, newFee);
        vm.stopPrank();
    }
}

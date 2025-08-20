// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {LibString} from "solady/utils/LibString.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {HookletLib} from "bunni-v2/src/lib/HookletLib.sol";

import {CREATE3Script} from "./base/CREATE3Script.sol";
import {L2MEVHooklet} from "../src/L2MEVHooklet.sol";

contract DeployL2MEVHookletScript is CREATE3Script {
    using LibString for uint256;
    using SafeCastLib for uint256;

    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run() external returns (L2MEVHooklet l2mevHooklet, bytes32 l2mevHookletSalt) {
        address deployer = vm.envAddress("DEPLOYER");

        address bunniHub = vm.envAddress(string.concat("BUNNI_HUB_", block.chainid.toString()));
        address weth = vm.envAddress(string.concat("WETH_", block.chainid.toString()));

        l2mevHookletSalt = getCreate3SaltFromEnv("L2MEVHooklet");

        uint256 l2mevHookletFlags = HookletLib.BEFORE_SWAP_FLAG + HookletLib.BEFORE_SWAP_OVERRIDE_FEE_FLAG;
        address l2mevHookletDeployed = create3.getDeployed(deployer, l2mevHookletSalt);
        require(
            uint160(bytes20(l2mevHookletDeployed)) & HookletLib.ALL_FLAGS_MASK == l2mevHookletFlags
                && l2mevHookletDeployed.code.length == 0,
            "hooklet address invalid"
        );

        vm.startBroadcast(deployer);

        l2mevHooklet = L2MEVHooklet(
            create3.deploy(l2mevHookletSalt, bytes.concat(type(L2MEVHooklet).creationCode, abi.encode(bunniHub, weth)))
        );

        vm.stopBroadcast();
    }
}

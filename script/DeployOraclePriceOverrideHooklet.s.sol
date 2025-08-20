// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {LibString} from "solady/utils/LibString.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {HookletLib} from "bunni-v2/src/lib/HookletLib.sol";

import {CREATE3Script} from "./base/CREATE3Script.sol";
import {OraclePriceOverrideHooklet} from "../src/OraclePriceOverrideHooklet.sol";

contract DeployOraclePriceOverrideHookletScript is CREATE3Script {
    using LibString for uint256;
    using SafeCastLib for uint256;

    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run()
        external
        returns (OraclePriceOverrideHooklet oraclePriceOverrideHooklet, bytes32 oraclePriceOverrideHookletSalt)
    {
        address deployer = vm.envAddress("DEPLOYER");

        address bunniHub = vm.envAddress(string.concat("BUNNI_HUB_", block.chainid.toString()));
        address weth = vm.envAddress(string.concat("WETH_", block.chainid.toString()));

        oraclePriceOverrideHookletSalt = getCreate3SaltFromEnv("OraclePriceOverrideHooklet");

        uint256 oraclePriceOverrideHookletFlags = HookletLib.BEFORE_SWAP_FLAG + HookletLib.BEFORE_SWAP_OVERRIDE_FEE_FLAG
            + HookletLib.BEFORE_SWAP_OVERRIDE_PRICE_FLAG;
        address oraclePriceOverrideHookletDeployed = create3.getDeployed(deployer, oraclePriceOverrideHookletSalt);
        require(
            uint160(bytes20(oraclePriceOverrideHookletDeployed)) & HookletLib.ALL_FLAGS_MASK
                == oraclePriceOverrideHookletFlags && oraclePriceOverrideHookletDeployed.code.length == 0,
            "hooklet address invalid"
        );

        vm.startBroadcast(deployer);

        oraclePriceOverrideHooklet = OraclePriceOverrideHooklet(
            create3.deploy(
                oraclePriceOverrideHookletSalt,
                bytes.concat(type(OraclePriceOverrideHooklet).creationCode, abi.encode(bunniHub, weth))
            )
        );

        vm.stopBroadcast();
    }
}

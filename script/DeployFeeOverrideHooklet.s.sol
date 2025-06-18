// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {LibString} from "solady/utils/LibString.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {HookletLib} from "bunni-v2/src/lib/HookletLib.sol";

import {CREATE3Script} from "./base/CREATE3Script.sol";
import {FeeOverrideHooklet} from "../src/FeeOverrideHooklet.sol";

contract DeployFeeOverrideHookletScript is CREATE3Script {
    using LibString for uint256;
    using SafeCastLib for uint256;

    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run() external returns (FeeOverrideHooklet feeOverrideHooklet, bytes32 feeOverrideHookletSalt) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        address deployer = vm.addr(deployerPrivateKey);

        address bunniHub = vm.envAddress(string.concat("BUNNI_HUB_", block.chainid.toString()));

        feeOverrideHookletSalt = getCreate3SaltFromEnv("FeeOverrideHooklet");

        uint256 feeOverrideHookletFlags = HookletLib.BEFORE_SWAP_FLAG + HookletLib.BEFORE_SWAP_OVERRIDE_FEE_FLAG;
        address feeOverrideHookletDeployed = create3.getDeployed(deployer, feeOverrideHookletSalt);
        require(
            uint160(bytes20(feeOverrideHookletDeployed)) & HookletLib.ALL_FLAGS_MASK == feeOverrideHookletFlags && feeOverrideHookletDeployed.code.length == 0,
            "hooklet address invalid"
        );

        vm.startBroadcast(deployerPrivateKey);

        feeOverrideHooklet = FeeOverrideHooklet(
            create3.deploy(
                feeOverrideHookletSalt,
                bytes.concat(
                    type(FeeOverrideHooklet).creationCode,
                    abi.encode(bunniHub)
                )
            )
        );

        vm.stopBroadcast();
    }
}

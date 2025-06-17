// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {LibString} from "solady/utils/LibString.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";

import {CREATE3Script} from "./base/CREATE3Script.sol";
import {FeeOverrideHooklet} from "../src/FeeOverrideHooklet.sol";

contract DeployFeeOverrideHookletScript is CREATE3Script {
    using LibString for uint256;
    using SafeCastLib for uint256;

    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run() external returns (FeeOverrideHooklet feeOverrideHooklet, bytes32 feeOverrideHookletSalt) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        address bunniHub = vm.envAddress(string.concat("BUNNI_HUB_", block.chainid.toString()));

        feeOverrideHookletSalt = getCreate3SaltFromEnv("FeeOverrideHooklet");

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

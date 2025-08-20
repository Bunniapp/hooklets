pragma solidity ^0.8.13;

import {CREATE3Script} from "./base/CREATE3Script.sol";
import {BaseEthUsdcOracle} from "../src/oracles/BaseEthUsdcOracle.sol";

contract DeployBaseEthUsdcOracleScript is CREATE3Script {
    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run() external returns (BaseEthUsdcOracle oracle, bytes32 oracleSalt) {
        oracleSalt = getCreate3SaltFromEnv("BaseEthUsdcOracle");

        vm.startBroadcast(vm.envAddress("DEPLOYER"));

        oracle = BaseEthUsdcOracle(
            create3.deploy(
                oracleSalt, bytes.concat(type(BaseEthUsdcOracle).creationCode, abi.encode(vm.envAddress("ORACLE")))
            )
        );

        vm.stopBroadcast();
    }
}

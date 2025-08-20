// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {IPriceOracle} from "euler-price-oracle/interfaces/IPriceOracle.sol";

contract BaseEthUsdcOracle is IPriceOracle {
    IPriceOracle public immutable baseOracle;

    address internal constant eth = address(0);
    address internal constant usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant weth = 0x4200000000000000000000000000000000000006;
    address internal constant usd = 0x0000000000000000000000000000000000000348;

    constructor(IPriceOracle _baseOracle) {
        baseOracle = _baseOracle;
    }

    function name() external pure returns (string memory) {
        return "Base ETH-USDC Oracle";
    }

    function getQuote(uint256 inAmount, address base, address quote) external view returns (uint256) {
        return baseOracle.getQuote(inAmount, _convertAddress(base), _convertAddress(quote));
    }

    function getQuotes(uint256 inAmount, address base, address quote) external view returns (uint256, uint256) {
        return baseOracle.getQuotes(inAmount, _convertAddress(base), _convertAddress(quote));
    }

    function _convertAddress(address token) internal pure returns (address) {
        if (token == eth) return weth;
        if (token == usdc) return usd;
        return token;
    }
}

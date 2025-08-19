// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {IHooklet} from "bunni-v2/src/interfaces/IHooklet.sol";
import {IBunniHub} from "bunni-v2/src/interfaces/IBunniHub.sol";
import {IBunniHook} from "bunni-v2/src/interfaces/IBunniHook.sol";
import {IBunniToken} from "bunni-v2/src/interfaces/IBunniToken.sol";
import {SWAP_FEE_BASE} from "bunni-v2/src/base/Constants.sol";

import {LibMulticaller} from "multicaller/src/LibMulticaller.sol";

import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

import "v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

import {IPriceOracle} from "euler-price-oracle/interfaces/IPriceOracle.sol";

/// @notice Extremely rudimentary anti-MEV hooklet targeting L2s with priority-fee ordering.
/// Implements MEV tax on swaps using priority fees, which only supports pairs with ETH/WETH as one asset.
/// Also implements spot price override using Euler IPriceOracle contracts.
contract L2MEVHooklet is IHooklet {
    using TickMath for *;
    using FixedPointMathLib for *;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    struct PoolConfig {
        bool overrideZeroToOne;
        uint24 feeZeroToOne;
        bool overrideOneToZero;
        uint24 feeOneToZero;
        uint32 priorityFeeMultiplier; // 3 decimals
        IPriceOracle oracle;
    }

    uint24 internal constant TWAP_DURATION = 5 minutes;
    uint256 internal constant PRIO_FEE_MULT_BASE = 1000;
    uint256 internal constant Q64 = 1 << 64;
    uint256 internal constant Q160 = 1 << 160; // Q96 * Q64
    uint256 internal constant Q192 = 1 << 192; // Q96 * Q96
    uint256 internal constant ORACLE_MIN_ETH_IN = 0.1 ether;

    IBunniHub public immutable bunniHub;
    Currency public immutable weth;

    mapping(PoolId => PoolConfig) public poolConfigs;
    mapping(PoolId => uint256) public lastSwapBlock;

    constructor(address bunniHub_, address weth_) {
        bunniHub = IBunniHub(bunniHub_);
        weth = Currency.wrap(weth_);
    }

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error L2MEVHooklet__InvalidSwapFee();
    error L2MEVHooklet__InvalidTokenPair();
    error L2MEVHooklet__NotBunniTokenOwner();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event SetPoolConfig(PoolId indexed id, PoolConfig config);

    /// -----------------------------------------------------------
    /// Override Functions
    /// -----------------------------------------------------------

    function setPoolConfig(PoolKey calldata key, PoolConfig calldata newConfig) public {
        /// -----------------------------------------------------------------------
        /// Validation
        /// -----------------------------------------------------------------------

        // fee must be valid
        if (newConfig.feeZeroToOne >= SWAP_FEE_BASE || newConfig.feeOneToZero >= SWAP_FEE_BASE) {
            revert L2MEVHooklet__InvalidSwapFee();
        }

        // must be called by bunni token owner
        PoolId id = key.toId();
        IBunniToken bunniToken = bunniHub.bunniTokenOfPool(id);
        address owner = bunniToken.owner();
        address msgSender = LibMulticaller.senderOrSigner();
        if (msgSender != owner) {
            revert L2MEVHooklet__NotBunniTokenOwner();
        }

        // one of the tokens must be ETH or WETH if priority fee and/or oracle is set
        if (
            (newConfig.priorityFeeMultiplier != 0 || address(newConfig.oracle) != address(0))
                && !(key.currency0 == CurrencyLibrary.ADDRESS_ZERO || key.currency0 == weth || key.currency1 == weth)
        ) {
            revert L2MEVHooklet__InvalidTokenPair();
        }

        /// -----------------------------------------------------------------------
        /// State updates
        /// -----------------------------------------------------------------------

        poolConfigs[id] = newConfig;

        emit SetPoolConfig(id, newConfig);
    }

    /// -----------------------------------------------------------------------
    /// Before Swap Hooklet
    /// -----------------------------------------------------------------------

    function beforeSwap(address, /* sender */ PoolKey calldata key, IPoolManager.SwapParams calldata params)
        external
        returns (bytes4 selector, bool feeOverriden, uint24 fee, bool priceOverridden, uint160 sqrtPriceX96)
    {
        selector = IHooklet.beforeSwap.selector;
        PoolId poolId = key.toId();
        (feeOverriden, fee, priceOverridden, sqrtPriceX96) = _beforeSwap(poolId, key, params);

        // update last swap block
        lastSwapBlock[poolId] = block.number;
    }

    function beforeSwapView(address, /* sender */ PoolKey calldata key, IPoolManager.SwapParams calldata params)
        external
        view
        returns (bytes4 selector, bool feeOverriden, uint24 fee, bool priceOverridden, uint160 sqrtPriceX96)
    {
        selector = IHooklet.beforeSwapView.selector;
        PoolId poolId = key.toId();
        (feeOverriden, fee, priceOverridden, sqrtPriceX96) = _beforeSwap(poolId, key, params);
    }

    function _beforeSwap(PoolId poolId, PoolKey calldata key, IPoolManager.SwapParams calldata params)
        internal
        view
        returns (bool feeOverriden, uint24 fee, bool priceOverridden, uint160 sqrtPriceX96)
    {
        PoolConfig memory config = poolConfigs[poolId];
        bool exactIn = params.amountSpecified < 0;

        // get isTopOfBlockSwap status
        bool isTopOfBlockSwap = block.number != lastSwapBlock[poolId];

        // override price for top-of-block swap if oracle is set
        if (address(config.oracle) != address(0) && isTopOfBlockSwap) {
            // override price using oracle
            // always use the specified amount as inAmount, since if it's an exact output swap then we compute the price via a
            // hypothetical outputToken => inputToken swap
            bool currency0IsEth = key.currency0.isAddressZero() || key.currency0 == weth;
            bool currency0IsSpecified = exactIn == params.zeroForOne;

            uint256 inAmount = params.amountSpecified.abs(); // in base token

            // enforce minimum oracle input amount to ensure the price has enough precision
            if (currency0IsEth == currency0IsSpecified) {
                // ETH is the specified currency
                inAmount = FixedPointMathLib.max(inAmount, ORACLE_MIN_ETH_IN);
            } else {
                // ETH is the unspecified currency
                inAmount = FixedPointMathLib.max(inAmount, _convert(key, currency0IsEth, ORACLE_MIN_ETH_IN));
            }

            (address base, address quote) = currency0IsSpecified
                ? (Currency.unwrap(key.currency0), Currency.unwrap(key.currency1))
                : (Currency.unwrap(key.currency1), Currency.unwrap(key.currency0));
            uint256 outAmount = config.oracle.getQuote(inAmount, base, quote); // in quote token
            (uint256 amount0, uint256 amount1) = currency0IsSpecified ? (inAmount, outAmount) : (outAmount, inAmount);
            if (amount0 == 0) {
                // divide by zero error
                // don't override price
                priceOverridden = false;
                sqrtPriceX96 = 0;
            } else {
                // compute sqrtPriceX96 candidate
                uint256 sqrtPriceX96_ = amount1.fullMulDiv(Q192, amount0).sqrt(); // unit: sqrt(token1 / token0) in Q96

                if (sqrtPriceX96_ >= TickMath.MIN_SQRT_PRICE && sqrtPriceX96_ <= TickMath.MAX_SQRT_PRICE) {
                    // candidate is valid
                    priceOverridden = true;
                    sqrtPriceX96 = uint160(sqrtPriceX96_);
                } else {
                    // candidate is invalid
                    // don't override price
                    priceOverridden = false;
                    sqrtPriceX96 = 0;
                }
            }
        } else {
            // don't override price
            priceOverridden = false;
            sqrtPriceX96 = 0;
        }

        // basic fee override
        feeOverriden = params.zeroForOne ? config.overrideZeroToOne : config.overrideOneToZero;
        fee = params.zeroForOne ? config.feeZeroToOne : config.feeOneToZero;

        // add priority fee on top
        if (config.priorityFeeMultiplier != 0) {
            uint256 priorityFeeInWei = (tx.gasprice - block.basefee) * gasleft();
            bool currency0IsEth = key.currency0.isAddressZero() || key.currency0 == weth;

            uint256 swapAmountInWei;
            bool amountSpecifiedIsInETH;
            {
                bool zeroForOne = params.zeroForOne;
                assembly ("memory-safe") {
                    amountSpecifiedIsInETH := xor(exactIn, xor(currency0IsEth, zeroForOne))
                }
            }
            if (amountSpecifiedIsInETH) {
                // amountSpecified is in ETH
                // directly use the specified amount to compute the fee rate
                swapAmountInWei = params.amountSpecified.abs();
            } else {
                // the unspecified amount is in ETH
                swapAmountInWei = _convert(key, !currency0IsEth, params.amountSpecified.abs());
            }
            if (swapAmountInWei != 0) {
                // uint24 cast is safe since fee is capped at SWAP_FEE_BASE - 1
                fee += uint24(
                    FixedPointMathLib.min(
                        priorityFeeInWei.mulDivUp(SWAP_FEE_BASE, swapAmountInWei).mulDivUp(
                            config.priorityFeeMultiplier, PRIO_FEE_MULT_BASE
                        ),
                        SWAP_FEE_BASE - 1 - fee
                    )
                );
            }
        }
    }

    /// -----------------------------------------------------------
    /// Unused IHooklet Functions
    /// -----------------------------------------------------------

    function beforeTransfer(
        address, /* sender */
        PoolKey calldata, /* key */
        IBunniToken, /* bunniToken */
        address, /* from */
        address, /* to */
        uint256 /* amount */
    ) external pure returns (bytes4 selector) {
        return IHooklet.beforeTransfer.selector;
    }

    function afterTransfer(
        address, /* sender */
        PoolKey calldata, /* key */
        IBunniToken, /* bunniToken */
        address, /* from */
        address, /* to */
        uint256 /* amount */
    ) external pure returns (bytes4 selector) {
        return IHooklet.afterTransfer.selector;
    }

    function beforeInitialize(address, /* sender */ IBunniHub.DeployBunniTokenParams calldata /* params */ )
        external
        pure
        returns (bytes4 selector)
    {
        return IHooklet.beforeInitialize.selector;
    }

    function afterInitialize(
        address, /* sender */
        IBunniHub.DeployBunniTokenParams calldata, /* params */
        InitializeReturnData calldata /* returnData */
    ) external pure returns (bytes4 selector) {
        return IHooklet.afterInitialize.selector;
    }

    function beforeDeposit(address, /* sender */ IBunniHub.DepositParams calldata /* params */ )
        external
        pure
        returns (bytes4 selector)
    {
        return IHooklet.beforeDeposit.selector;
    }

    function beforeDepositView(address, /* sender */ IBunniHub.DepositParams calldata /* params */ )
        external
        pure
        returns (bytes4 selector)
    {
        return IHooklet.beforeDepositView.selector;
    }

    function afterDeposit(
        address, /* sender */
        IBunniHub.DepositParams calldata, /* params */
        DepositReturnData calldata /* returnData */
    ) external pure returns (bytes4 selector) {
        return IHooklet.afterDeposit.selector;
    }

    function afterDepositView(
        address, /* sender */
        IBunniHub.DepositParams calldata, /* params */
        DepositReturnData calldata /* returnData */
    ) external pure returns (bytes4 selector) {
        return IHooklet.afterDepositView.selector;
    }

    function beforeWithdraw(address, /* sender */ IBunniHub.WithdrawParams calldata /* params */ )
        external
        pure
        returns (bytes4 selector)
    {
        return IHooklet.beforeWithdraw.selector;
    }

    function beforeWithdrawView(address, /* sender */ IBunniHub.WithdrawParams calldata /* params */ )
        external
        pure
        returns (bytes4 selector)
    {
        return IHooklet.beforeWithdrawView.selector;
    }

    function afterWithdraw(
        address, /* sender */
        IBunniHub.WithdrawParams calldata, /* params */
        WithdrawReturnData calldata /* returnData */
    ) external pure returns (bytes4 selector) {
        return IHooklet.afterWithdraw.selector;
    }

    function afterWithdrawView(
        address, /* sender */
        IBunniHub.WithdrawParams calldata, /* params */
        WithdrawReturnData calldata /* returnData */
    ) external pure returns (bytes4 selector) {
        return IHooklet.afterWithdrawView.selector;
    }

    function afterSwap(
        address, /* sender */
        PoolKey calldata, /* key */
        IPoolManager.SwapParams calldata, /* params */
        SwapReturnData calldata /* returnData */
    ) external pure returns (bytes4 selector) {
        return IHooklet.afterSwap.selector;
    }

    function afterSwapView(
        address, /* sender */
        PoolKey calldata, /* key */
        IPoolManager.SwapParams calldata, /* params */
        SwapReturnData calldata /* returnData */
    ) external pure returns (bytes4 selector) {
        return IHooklet.afterSwapView.selector;
    }

    function afterRebalance(
        PoolKey calldata, /* key */
        bool, /* orderOutputIsCurrency0 */
        uint256, /* orderInputAmount */
        uint256 /* orderOutputAmount */
    ) external pure returns (bytes4 selector) {
        return IHooklet.afterRebalance.selector;
    }

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    function _convert(PoolKey calldata key, bool zeroToOne, uint256 fromAmount)
        internal
        view
        returns (uint256 toAmount)
    {
        // use TWAP sqrtPriceX96 to compute the corresponding ETH value
        // and then compute the fee rate
        uint160 sqrtPriceX96_ = _getTwap(key).getSqrtPriceAtTick();
        if (!zeroToOne) {
            uint256 invSqrtPriceX64 = Q160 / sqrtPriceX96_; // unit: sqrt(token0 / token1) in Q64
            // squaring invSqrtPriceX64 is safe because log2((Q160 / MIN_SQRT_PRICE)^2) = 255.9998915435 < 256
            uint256 priceOf1In0X64 = invSqrtPriceX64.mulDiv(invSqrtPriceX64, Q64); // unit: token0 / token1 in Q64
            return fromAmount.fullMulDiv(priceOf1In0X64, Q64);
        } else {
            uint256 sqrtPriceX64 = sqrtPriceX96_ >> 32; // unit: sqrt(token1 / token0) in Q64
            // squaring sqrtPriceX64 is safe because log2((MAX_SQRT_PRICE >> 32)^2) = 255.9998915440 < 256
            uint256 priceOf0In1X64 = sqrtPriceX64.mulDiv(sqrtPriceX64, Q64); // unit: token1 / token0 in Q64
            return fromAmount.fullMulDiv(priceOf0In1X64, Q64);
        }
    }

    function _getTwap(PoolKey calldata poolKey) internal view returns (int24 arithmeticMeanTick) {
        IBunniHook hook = IBunniHook(address(poolKey.hooks));
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = TWAP_DURATION;
        secondsAgos[1] = 0;
        int56[] memory tickCumulatives = hook.observe(poolKey, secondsAgos);
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        return int24(tickCumulativesDelta / int56(uint56(TWAP_DURATION)));
    }
}

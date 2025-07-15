// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IHooklet } from "bunni-v2/src/interfaces/IHooklet.sol";
import { IBunniHub } from "bunni-v2/src/interfaces/IBunniHub.sol";
import { IBunniToken } from "bunni-v2/src/interfaces/IBunniToken.sol";
import { SWAP_FEE_BASE } from "bunni-v2/src/base/Constants.sol";

import { PoolId, PoolIdLibrary } from "v4-core/src/types/PoolId.sol";
import { PoolKey } from "v4-core/src/types/PoolKey.sol";
import { IPoolManager } from "v4-core/src/interfaces/IPoolManager.sol";

contract FeeOverrideHooklet is IHooklet {

    struct FeeOverride {
        IHooklet.BeforeSwapFeeOverride zeroToOne;
        IHooklet.BeforeSwapFeeOverride oneToZero;
    }

    IBunniHub public immutable bunniHub;
    mapping(PoolId => FeeOverride) public feeOverrides;

    constructor(address bunniHub_) {
        bunniHub = IBunniHub(bunniHub_);
    }

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error FeeOverrideHooklet__InvalidSwapFee();
    error FeeOverrideHooklet__NotBunniTokenOwner();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event SetFeeOverride(PoolId indexed id, bool overrideZeroToOne, uint24 feeZeroToOne, bool overrideOneToZero, uint24 feeOneToZero);

    /// -----------------------------------------------------------
    /// Override Functions
    /// -----------------------------------------------------------

    function setFeeOverride(
        PoolId id,
        bool overrideZeroToOne,
        uint24 feeZeroToOne,
        bool overrideOneToZero,
        uint24 feeOneToZero
    ) public {
        if (feeZeroToOne >= SWAP_FEE_BASE || feeOneToZero >= SWAP_FEE_BASE) {
            revert FeeOverrideHooklet__InvalidSwapFee();
        }

        IBunniToken bunniToken = bunniHub.bunniTokenOfPool(id);
        address owner = bunniToken.owner();

        if (msg.sender != owner) {
            revert FeeOverrideHooklet__NotBunniTokenOwner();
        }

        FeeOverride storage feeOverride = feeOverrides[id];
        feeOverride.zeroToOne.overridden = overrideZeroToOne;
        feeOverride.zeroToOne.fee = feeZeroToOne;
        feeOverride.oneToZero.overridden = overrideOneToZero;
        feeOverride.oneToZero.fee = feeOneToZero;

        emit SetFeeOverride(id, overrideZeroToOne, feeZeroToOne, overrideOneToZero, feeOneToZero);
    }


    /// -----------------------------------------------------------
    /// IHooklet Functions
    /// -----------------------------------------------------------

    function beforeTransfer(
        address /* sender */,
        PoolKey calldata /* key */,
        IBunniToken /* bunniToken */,
        address /* from */,
        address /* to */,
        uint256 /* amount */
    ) external pure returns (bytes4 selector) {
        return IHooklet.beforeTransfer.selector;
    }

    function afterTransfer(
        address /* sender */,
        PoolKey calldata /* key */,
        IBunniToken /* bunniToken */,
        address /* from */,
        address /* to */,
        uint256 /* amount */
    ) external pure returns (bytes4 selector) {
        return IHooklet.afterTransfer.selector;
    }

    function beforeInitialize(
        address /* sender */,
        IBunniHub.DeployBunniTokenParams calldata /* params */
    ) external pure returns (bytes4 selector) {
        return IHooklet.beforeInitialize.selector;
    }

    function afterInitialize(
        address /* sender */,
        IBunniHub.DeployBunniTokenParams calldata /* params */,
        InitializeReturnData calldata /* returnData */
    ) external pure returns (bytes4 selector) {
        return IHooklet.afterInitialize.selector;
    }

    function beforeDeposit(
        address /* sender */,
        IBunniHub.DepositParams calldata /* params */
    ) external pure returns (bytes4 selector) {
        return IHooklet.beforeDeposit.selector;
    }

    function beforeDepositView(
        address /* sender */,
        IBunniHub.DepositParams calldata /* params */
    ) external pure returns (bytes4 selector) {
        return IHooklet.beforeDepositView.selector;
    }

    function afterDeposit(
        address /* sender */,
        IBunniHub.DepositParams calldata /* params */,
        DepositReturnData calldata /* returnData */
    ) external pure returns (bytes4 selector) {
        return IHooklet.afterDeposit.selector;
    }

    function afterDepositView(
        address /* sender */,
        IBunniHub.DepositParams calldata /* params */,
        DepositReturnData calldata /* returnData */
    ) external pure returns (bytes4 selector) {
        return IHooklet.afterDepositView.selector;
    }

    function beforeWithdraw(
        address /* sender */,
        IBunniHub.WithdrawParams calldata /* params */
    ) external pure returns (bytes4 selector) {
        return IHooklet.beforeWithdraw.selector;
    }

    function beforeWithdrawView(
        address /* sender */,
        IBunniHub.WithdrawParams calldata /* params */
    ) external pure returns (bytes4 selector) {
        return IHooklet.beforeWithdrawView.selector;
    }

    function afterWithdraw(
        address /* sender */,
        IBunniHub.WithdrawParams calldata /* params */,
        WithdrawReturnData calldata /* returnData */
    ) external pure returns (bytes4 selector) {
        return IHooklet.afterWithdraw.selector;
    }

    function afterWithdrawView(
        address /* sender */,
        IBunniHub.WithdrawParams calldata /* params */,
        WithdrawReturnData calldata /* returnData */
    ) external pure returns (bytes4 selector) {
        return IHooklet.afterWithdrawView.selector;
    }

    function beforeSwap(
        address /* sender */,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params
    ) external view returns (bytes4 selector, bool feeOverriden, uint24 fee, bool priceOverridden, uint160 sqrtPriceX96) {
        selector = IHooklet.beforeSwap.selector;
        (feeOverriden, fee, priceOverridden, sqrtPriceX96) = _beforeSwap(key, params);
    }

    function beforeSwapView(
        address /* sender */,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params
    ) external view returns (bytes4 selector, bool feeOverriden, uint24 fee, bool priceOverridden, uint160 sqrtPriceX96) {
        selector = IHooklet.beforeSwapView.selector;
        (feeOverriden, fee, priceOverridden, sqrtPriceX96) = _beforeSwap(key, params);
    }

    function afterSwap(
        address /* sender */,
        PoolKey calldata /* key */,
        IPoolManager.SwapParams calldata /* params */,
        SwapReturnData calldata /* returnData */
    ) external pure returns (bytes4 selector) {
        return IHooklet.afterSwap.selector;
    }

    function afterSwapView(
        address /* sender */,
        PoolKey calldata /* key */,
        IPoolManager.SwapParams calldata /* params */,
        SwapReturnData calldata /* returnData */
    ) external pure returns (bytes4 selector) {
        return IHooklet.afterSwapView.selector;
    }

    function afterRebalance(
        PoolKey calldata /* key */,
        bool /* orderOutputIsCurrency0 */,
        uint256 /* orderInputAmount */,
        uint256 /* orderOutputAmount */
    ) external pure returns (bytes4 selector) {
        return IHooklet.afterRebalance.selector;
    }

    /// -----------------------------------------------------------
    /// Internal Functions
    /// -----------------------------------------------------------

    function _beforeSwap(
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params
    ) internal view returns (bool feeOverriden, uint24 fee, bool priceOverridden, uint160 sqrtPriceX96) {
        PoolId poolId = PoolIdLibrary.toId(key);
        FeeOverride memory feeOverride = feeOverrides[poolId];

        feeOverriden = params.zeroForOne ? feeOverride.zeroToOne.overridden : feeOverride.oneToZero.overridden;
        fee = params.zeroForOne ? feeOverride.zeroToOne.fee : feeOverride.oneToZero.fee;
        priceOverridden = false;
        sqrtPriceX96 = 0;
    }
}

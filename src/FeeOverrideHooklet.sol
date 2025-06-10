// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IHooklet } from "bunni-v2/src/interfaces/IHooklet.sol";
import { IBunniHub } from "bunni-v2/src/interfaces/IBunniHub.sol";
import { IBunniToken } from "bunni-v2/src/interfaces/IBunniToken.sol";

import { PoolId, PoolIdLibrary } from "v4-core/src/types/PoolId.sol";
import { PoolKey } from "v4-core/src/types/PoolKey.sol";
import { IPoolManager } from "v4-core/src/interfaces/IPoolManager.sol";

contract FeeOverrideHooklet is IHooklet {

    struct FeeOverride {
        bool overrideZeroToOne;
        uint24 feeZeroToOne;
        bool overrideOneToZero;
        uint24 feeOneToZero;
    }

    mapping(PoolId => FeeOverride) public feeOverrides;

    /// -----------------------------------------------------------
    /// Override Functions
    /// -----------------------------------------------------------

    function setFeeOverride(
        PoolId id,
        IBunniHub bunniHub,
        bool overrideZeroToOne,
        uint24 feeZeroToOne,
        bool overrideOneToZero,
        uint24 feeOneToZero
    ) public {
        // 1- get the bunnitoken
        // 2- get the owner fo the bunnitoken
        // 3- make sure the msg.sender is the owner of the bunni token
        // 4- if yes, then set the overrides
        IBunniToken bunniToken = bunniHub.bunniTokenOfPool(id);
        address owner = bunniToken.owner();

        require(msg.sender == owner, "Not the BunniToken owner");

        FeeOverride storage feeOverride = feeOverrides[id];
        feeOverride.overrideZeroToOne = overrideZeroToOne;
        feeOverride.feeZeroToOne = feeZeroToOne;
        feeOverride.overrideOneToZero = overrideOneToZero;
        feeOverride.feeOneToZero = feeOneToZero;
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
        PoolId poolId = PoolIdLibrary.toId(key);
        FeeOverride memory feeOverride = feeOverrides[poolId];

        selector = IHooklet.beforeSwap.selector;
        feeOverriden = params.zeroForOne ? feeOverride.overrideZeroToOne : feeOverride.overrideOneToZero;
        fee = params.zeroForOne ? feeOverride.feeZeroToOne : feeOverride.feeOneToZero;
        priceOverridden = false;
        sqrtPriceX96 = 0;
    }

    function beforeSwapView(
        address /* sender */,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params
    ) external view returns (bytes4 selector, bool feeOverriden, uint24 fee, bool priceOverridden, uint160 sqrtPriceX96) {
        PoolId poolId = PoolIdLibrary.toId(key);
        FeeOverride memory feeOverride = feeOverrides[poolId];

        selector = IHooklet.beforeSwapView.selector;
        feeOverriden = params.zeroForOne ? feeOverride.overrideZeroToOne : feeOverride.overrideOneToZero;
        fee = params.zeroForOne ? feeOverride.feeZeroToOne : feeOverride.feeOneToZero;
        priceOverridden = false;
        sqrtPriceX96 = 0;
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
}

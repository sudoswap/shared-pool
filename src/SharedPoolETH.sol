// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {LSSVMPairETH} from "lssvm2/LSSVMPairETH.sol";

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import "./SharedPool.sol";

abstract contract SharedPoolETH is SharedPool {
    function token() public pure override returns (ERC20) {
        return ERC20(address(0));
    }

    function _getTokenInput(bytes calldata) internal view override returns (uint256 tokenInput) {
        return msg.value;
    }

    function _pullTokensFromSender(ERC20, address to, uint256 amount) internal override {
        if (amount == 0) return;
        SafeTransferLib.safeTransferETH(to, amount);
    }

    function _pushTokens(ERC20, address to, uint256 amount) internal override {
        if (amount == 0) return;
        SafeTransferLib.safeTransferETH(to, amount);
    }

    function _withdrawTokensFromPair(ERC20, LSSVMPair _pair, uint256 amount) internal override {
        if (amount == 0) return;
        LSSVMPairETH(payable(address(_pair))).withdrawETH(amount);
    }

    function _getTokenReserve(ERC20, LSSVMPair _pair) internal view override returns (uint256 tokenReserve) {
        return address(_pair).balance;
    }
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import "./SharedPool.sol";

abstract contract SharedPoolERC20Test is SharedPoolTest {
    function _deal(address to, uint256 amount) internal override {
        deal(address(testERC20), to, amount);
    }

    function _tokenBalanceOf(address user) internal view override returns (uint256) {
        return testERC20.balanceOf(user);
    }

    function _withdrawAllTokensFromSplitter(Splitter s) internal override {
        s.withdrawAllTokens(testERC20);
    }
}

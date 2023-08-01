// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import "./SharedPool.sol";

abstract contract SharedPoolETHTest is SharedPoolTest {
    function _deal(address to, uint256 amount) internal override {
        deal(to, amount);
    }

    function _tokenBalanceOf(address user) internal view override returns (uint256) {
        return user.balance;
    }

    function _withdrawAllTokensFromSplitter(Splitter s) internal override {
        s.withdrawAllETHInSplitter();
    }
}

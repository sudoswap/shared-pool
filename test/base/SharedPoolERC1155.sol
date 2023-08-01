// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import "./SharedPool.sol";

abstract contract SharedPoolERC1155Test is SharedPoolTest {
    uint256 internal constant ERC1155_ID = 0x69;

    function _approveNFT(address to) internal override {
        testERC1155.setApprovalForAll(to, true);
    }

    function _mintNFT(address to, uint256 numNfts, uint256) internal override {
        testERC1155.mint(to, ERC1155_ID, numNfts);
    }

    function _nftBalanceOf(address user) internal view override returns (uint256) {
        return testERC1155.balanceOf(user, ERC1155_ID);
    }

    function _nftAddress() internal view override returns (address) {
        return address(testERC1155);
    }
}

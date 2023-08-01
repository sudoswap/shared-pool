// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import "./SharedPool.sol";

abstract contract SharedPoolERC721Test is SharedPoolTest {
    function _approveNFT(address to) internal override {
        testERC721.setApprovalForAll(to, true);
    }

    function _mintNFT(address to, uint256 numNfts, uint256 start) internal override {
        uint256[] memory idList = _getIdList(start, numNfts);
        for (uint256 i; i < numNfts; i++) {
            testERC721.safeMint(to, idList[i]);
        }
    }

    function _nftBalanceOf(address user) internal view override returns (uint256) {
        return testERC721.balanceOf(user);
    }

    function _nftAddress() internal view override returns (address) {
        return address(testERC721);
    }
}

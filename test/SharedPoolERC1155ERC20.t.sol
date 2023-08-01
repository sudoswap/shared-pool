// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import "./base/SharedPoolERC1155.sol";
import "./base/SharedPoolERC20.sol";

contract SharedPoolERC1155ERC20Test is SharedPoolERC1155Test, SharedPoolERC20Test {
    function _deposit(SharedPool pool, uint256 numNfts, uint256 tokenAmount)
        internal
        override
        returns (uint256 amountNft, uint256 amountToken, uint256 liquidity)
    {
        testERC20.approve(address(pool), tokenAmount);
        return SharedPoolERC1155ERC20(payable(address(pool))).deposit(
            numNfts, 0, 0, address(this), block.timestamp, abi.encode(tokenAmount)
        );
    }

    function _redeem(SharedPool pool, uint256 burnAmount, uint256)
        internal
        override
        returns (uint256 numNftOutput, uint256 tokenOutput)
    {
        return SharedPoolERC1155ERC20(payable(address(pool))).redeem(burnAmount, 0, 0, address(this), block.timestamp);
    }

    function _createSharedPool(uint256 delta, uint256 spotPrice, uint256 fee, address, address settings_)
        internal
        override
        returns (SharedPool)
    {
        return factory.createSharedPoolERC1155ERC20(
            testERC20,
            testERC1155,
            uint128(delta),
            uint128(spotPrice),
            uint96(fee),
            ERC1155_ID,
            settings_,
            "Shared Pool",
            "SUDO-POOL"
        );
    }

    function _buyNFTsFromPool(SharedPool pool, uint256 numNfts, uint256 inputAmount) internal override {
        testERC20.approve(address(pool.pair()), inputAmount);
        uint256[] memory idList = new uint256[](1);
        idList[0] = numNfts;
        pool.pair().swapTokenForSpecificNFTs(idList, inputAmount, address(this), false, address(0));
    }
}

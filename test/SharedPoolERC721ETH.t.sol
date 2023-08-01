// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import "./base/SharedPoolERC721.sol";
import "./base/SharedPoolETH.sol";

contract SharedPoolERC721ETHTest is SharedPoolERC721Test, SharedPoolETHTest {
    function _deposit(SharedPool pool, uint256 numNfts, uint256 tokenAmount)
        internal
        override
        returns (uint256 amountNft, uint256 amountToken, uint256 liquidity)
    {
        return SharedPoolERC721ETH(payable(address(pool))).deposit{value: tokenAmount}(
            _getIdList(1, numNfts), 0, 0, address(this), block.timestamp, bytes("")
        );
    }

    function _redeem(SharedPool pool, uint256 burnAmount, uint256 numNfts)
        internal
        override
        returns (uint256 numNftOutput, uint256 tokenOutput)
    {
        return SharedPoolERC721ETH(payable(address(pool))).redeem(
            burnAmount, _getIdList(1, numNfts), 0, 0, address(this), block.timestamp
        );
    }

    function _createSharedPool(
        uint256 delta,
        uint256 spotPrice,
        uint256 fee,
        address propertyChecker,
        address settings_
    ) internal override returns (SharedPool) {
        return factory.createSharedPoolERC721ETH(
            testERC721,
            uint128(delta),
            uint128(spotPrice),
            uint96(fee),
            propertyChecker,
            settings_,
            "Shared Pool",
            "SUDO-POOL"
        );
    }

    function _buyNFTsFromPool(SharedPool pool, uint256 numNfts, uint256 inputAmount) internal override {
        pool.pair().swapTokenForSpecificNFTs{value: inputAmount}(
            _getIdList(1, numNfts), inputAmount, address(this), false, address(0)
        );
    }
}
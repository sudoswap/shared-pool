// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {ERC1155, ERC1155TokenReceiver} from "solmate/tokens/ERC1155.sol";

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import "./SharedPool.sol";

abstract contract SharedPoolERC1155 is SharedPool, ERC1155TokenReceiver {
    /// -----------------------------------------------------------------------
    /// Immutable args
    /// -----------------------------------------------------------------------

    function nftId() public pure returns (uint256) {
        return _getArgUint256(0x5C);
    }

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    function deposit(uint256 numNfts, uint256 minLiquidity, address recipient, bytes calldata extraData)
        external
        payable
        returns (uint256 liquidity)
    {
        LSSVMPair _pair = pair();
        uint256 tokenInput = _getTokenInput(extraData);
        liquidity = _deposit(_pair, numNfts, minLiquidity, tokenInput, recipient);

        /// -----------------------------------------------------------------------
        /// Effects
        /// -----------------------------------------------------------------------

        // transfer NFTs from msg.sender to pair
        ERC1155(nft()).safeTransferFrom(msg.sender, address(_pair), nftId(), numNfts, "");

        // transfer tokens to pair
        _pullTokensFromSender(token(), address(_pair), tokenInput);
    }

    function redeem(uint256 liquidity, uint256 minNumNftOutput, uint256 minTokenOutput, address recipient)
        external
        returns (uint256 numNftOutput, uint256 tokenOutput)
    {
        LSSVMPair _pair = pair();
        uint256 _nftId = nftId();
        (numNftOutput, tokenOutput) = _redeem(_pair, liquidity, minNumNftOutput, minTokenOutput, _nftId);

        /// -----------------------------------------------------------------------
        /// Effects
        /// -----------------------------------------------------------------------

        // withdraw NFTs from pair
        address _nft = nft();
        {
            uint256[] memory ids = new uint256[](1);
            ids[0] = _nftId;
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = numNftOutput;
            _pair.withdrawERC1155(IERC1155(_nft), ids, amounts);
        }

        // withdraw tokens from pair
        ERC20 _token = token();
        _withdrawTokensFromPair(_token, _pair, tokenOutput);

        // transfer NFTs to recipient
        ERC1155(nft()).safeTransferFrom(address(this), recipient, _nftId, numNftOutput, "");

        // transfer tokens to recipient
        _pushTokens(_token, recipient, tokenOutput);
    }
}

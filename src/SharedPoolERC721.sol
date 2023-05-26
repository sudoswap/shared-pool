// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {ERC721, ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./SharedPool.sol";

contract SharedPoolERC721 is SharedPool, ERC721TokenReceiver {
    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error SharedPoolERC721__NftIdsTooShort();

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    function deposit(uint256[] calldata nftIds, uint256 minLiquidity, address recipient)
        external
        payable
        returns (uint256 liquidity)
    {
        LSSVMPair _pair = pair();
        uint256 numNfts = nftIds.length;
        liquidity = _deposit(_pair, numNfts, minLiquidity, recipient);

        /// -----------------------------------------------------------------------
        /// Effects
        /// -----------------------------------------------------------------------

        {
            // transfer NFTs from msg.sender to pair
            ERC721 _nft = ERC721(nft());
            for (uint256 i; i < numNfts;) {
                _nft.safeTransferFrom(msg.sender, address(_pair), nftIds[i]);

                unchecked {
                    ++i;
                }
            }
        }

        // transfer ETH to pair
        SafeTransferLib.safeTransferETH(address(_pair), msg.value);
    }

    function redeem(
        uint256 liquidity,
        uint256[] memory nftIds,
        uint256 minNumNftOutput,
        uint256 minTokenOutput,
        address recipient
    ) external returns (uint256 numNftOutput, uint256 tokenOutput) {
        LSSVMPairETH _pair = pair();
        (numNftOutput, tokenOutput) = _redeem(_pair, liquidity, minNumNftOutput, minTokenOutput, nftIds[0]);

        /// -----------------------------------------------------------------------
        /// Effects
        /// -----------------------------------------------------------------------

        // revert if nftIds is too short
        if (numNftOutput > nftIds.length) revert SharedPoolERC721__NftIdsTooShort();

        // withdraw NFTs from pair
        address _nft = nft();
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(nftIds, numNftOutput) // update length of array
        }
        _pair.withdrawERC721(IERC721(_nft), nftIds);

        // withdraw tokens from pair
        _pair.withdrawETH(tokenOutput);

        // transfer NFTs to recipient
        for (uint256 i; i < numNftOutput;) {
            ERC721(_nft).safeTransferFrom(address(this), recipient, nftIds[i]);

            unchecked {
                ++i;
            }
        }

        // transfer tokens to recipient
        SafeTransferLib.safeTransferETH(recipient, tokenOutput);
    }
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {ERC721, ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./SharedPool.sol";

abstract contract SharedPoolERC721 is SharedPool, ERC721TokenReceiver {
    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error SharedPoolERC721__NftIdsTooShort();

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    /// @notice Deposits NFTs into the Sudo pair and mints LP tokens.
    /// @param nftIds The list of NFT IDs to deposit
    /// @param minLiquidity Used for slippage checking. The minimum acceptable amount of LP tokens minted.
    /// @param recipient The recipient of the minted tokens
    /// @param extraData Used by SharedPoolERC20 to store the amount of tokens to deposit. Leave empty for SharedPoolETH.
    /// @param liquidity The amount of LP tokens minted
    function deposit(uint256[] calldata nftIds, uint256 minLiquidity, address recipient, bytes calldata extraData)
        external
        payable
        nonReentrant
        returns (uint256 liquidity)
    {
        LSSVMPair _pair = pair();
        uint256 numNfts = nftIds.length;
        uint256 tokenInput = _getTokenInput(extraData);
        liquidity = _deposit(_pair, numNfts, minLiquidity, tokenInput, recipient);

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

        // transfer tokens to pair
        _pullTokensFromSender(token(), address(_pair), tokenInput);
    }

    /// @notice Burns LP tokens to withdrawn NFTs and tokens.
    /// @dev Performs fractional swap to ensure whole NFTs are withdrawn. Will change the price
    /// of the Sudo pair as a normal swap would.
    /// @param liquidity The amount of LP tokens to burn
    /// @param nftIds The list of NFTs to withdraw. If the NFT output is less than the list's length, the front of the list will be used.
    /// @param minNumNftOutput Used for slippage checking. The minimum acceptable number of NFTs withdrawn.
    /// @param minTokenOutput Used for slippage checking. The minimum acceptable amount of tokens withdrawn.
    /// @param recipient The recipient of the NFTs and tokens withdrawn
    /// @return numNftOutput The number of NFTs withdrawn
    /// @return tokenOutput The amount of tokens withdrawn
    function redeem(
        uint256 liquidity,
        uint256[] memory nftIds,
        uint256 minNumNftOutput,
        uint256 minTokenOutput,
        address recipient
    ) external nonReentrant returns (uint256 numNftOutput, uint256 tokenOutput) {
        LSSVMPair _pair = pair();
        address payable[] memory royaltyRecipients;
        uint256[] memory royaltyAmounts;
        uint256 royaltyAmount;
        uint256 protocolFeeAmount;
        (numNftOutput, tokenOutput, royaltyRecipients, royaltyAmounts, royaltyAmount, protocolFeeAmount) =
            _redeem(_pair, liquidity, minNumNftOutput, minTokenOutput, nftIds[0]);

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
        ERC20 _token = token();
        _withdrawTokensFromPair(_token, _pair, tokenOutput + royaltyAmount + protocolFeeAmount);

        // transfer NFTs to recipient
        for (uint256 i; i < numNftOutput;) {
            ERC721(_nft).safeTransferFrom(address(this), recipient, nftIds[i]);

            unchecked {
                ++i;
            }
        }

        // transfer tokens to recipient
        _pushTokens(_token, recipient, tokenOutput);

        // transfer protocol fees to factory
        _pushTokens(_token, address(pairFactory()), protocolFeeAmount);

        // transfer royalties
        if (royaltyAmount != 0) {
            for (uint256 i; i < royaltyRecipients.length;) {
                _pushTokens(_token, royaltyRecipients[i], royaltyAmounts[i]);
                unchecked {
                    ++i;
                }
            }
        }
    }

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    function _getNftReserve(address _nft, LSSVMPair _pair) internal view override returns (uint256 nftReserve) {
        return ERC721(_nft).balanceOf(address(_pair));
    }
}

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

    /// @notice Deposits NFTs into the Sudo pair and mints LP tokens.
    /// @param numNfts The number of NFTs to deposit
    /// @param minLiquidity Used for slippage checking. The minimum acceptable amount of LP tokens minted.
    /// @param recipient The recipient of the minted tokens
    /// @param extraData Used by SharedPoolERC20 to store the amount of tokens to deposit. Leave empty for SharedPoolETH.
    /// @param liquidity The amount of LP tokens minted
    function deposit(uint256 numNfts, uint256 minLiquidity, address recipient, bytes calldata extraData)
        external
        payable
        nonReentrant
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

    /// @notice Burns LP tokens to withdrawn NFTs and tokens.
    /// @dev Performs fractional swap to ensure whole NFTs are withdrawn. Will change the price
    /// of the Sudo pair as a normal swap would.
    /// @param liquidity The amount of LP tokens to burn
    /// @param minNumNftOutput Used for slippage checking. The minimum acceptable number of NFTs withdrawn.
    /// @param minTokenOutput Used for slippage checking. The minimum acceptable amount of tokens withdrawn.
    /// @param recipient The recipient of the NFTs and tokens withdrawn
    /// @return numNftOutput The number of NFTs withdrawn
    /// @return tokenOutput The amount of tokens withdrawn
    function redeem(uint256 liquidity, uint256 minNumNftOutput, uint256 minTokenOutput, address recipient)
        external
        nonReentrant
        returns (uint256 numNftOutput, uint256 tokenOutput)
    {
        LSSVMPair _pair = pair();
        uint256 _nftId = nftId();
        address payable[] memory royaltyRecipients;
        uint256[] memory royaltyAmounts;
        uint256 royaltyAmount;
        uint256 protocolFeeAmount;
        (numNftOutput, tokenOutput, royaltyRecipients, royaltyAmounts, royaltyAmount, protocolFeeAmount) =
            _redeem(_pair, liquidity, minNumNftOutput, minTokenOutput, _nftId);

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
        return ERC1155(_nft).balanceOf(address(_pair), nftId());
    }
}

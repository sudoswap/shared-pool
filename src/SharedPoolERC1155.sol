// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {Clone} from "@clones/Clone.sol";

import {LSSVMPair} from "lssvm2/LSSVMPair.sol";
import {LSSVMPairETH} from "lssvm2/LSSVMPairETH.sol";
import {LSSVMPairFactory} from "lssvm2/LSSVMPairFactory.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC1155, ERC1155TokenReceiver} from "solmate/tokens/ERC1155.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import "./lib/Math.sol";

contract SharedPoolERC1155 is Clone, ERC20("Sudoswap Shared Pool", "SUDO-POOL", 18), ERC1155TokenReceiver {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using SafeCastLib for uint256;
    using FixedPointMathLib for uint256;

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    uint256 internal constant BASE = 1e18;
    uint256 internal constant HALF_BASE = 5e17;
    uint256 internal constant MINIMUM_LIQUIDITY = 1e3;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error SharedPool__InsufficientOutput();
    error SharedPool__InsufficientLiquidityMinted();

    /// -----------------------------------------------------------------------
    /// Immutable args
    /// -----------------------------------------------------------------------

    /// @notice The Sudo XYK curve pool used to provide liquidity
    function pair() public pure returns (LSSVMPairETH pair_) {
        return LSSVMPairETH(payable(_getArgAddress(0x00)));
    }

    /// @notice The initial delta value of the Sudo XYK curve pool. Used for computing NFT balance
    /// changes in the Sudo pool, since the delta stores the virtual NFT balance.
    function initialDelta() public pure returns (uint128 initialDelta_) {
        return _getArgUint128(0x14);
    }

    /// @notice The initial delta value of the Sudo XYK curve pool. Used for computing token balance
    /// changes in the Sudo pool, since the spot price stores the virtual token balance.
    function initialSpotPrice() public pure returns (uint128) {
        return _getArgUint128(0x24);
    }

    function nft() public pure returns (address) {
        return _getArgAddress(0x34);
    }

    function pairFactory() public pure returns (LSSVMPairFactory) {
        return LSSVMPairFactory(payable(_getArgAddress(0x48)));
    }

    function nftId() public pure returns (uint256) {
        return _getArgUint256(0x5C);
    }

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    function deposit(uint256 numNfts, uint256 minLiquidity, address recipient)
        external
        payable
        returns (uint256 liquidity)
    {
        /// -----------------------------------------------------------------------
        /// Storage loads
        /// -----------------------------------------------------------------------

        LSSVMPairETH _pair = pair();
        uint128 virtualNftReserve = _pair.delta();
        uint128 virtualTokenReserve = _pair.spotPrice();

        /// -----------------------------------------------------------------------
        /// State updates
        /// -----------------------------------------------------------------------

        {
            uint256 nftReserve = _getNftReserve(virtualNftReserve);
            uint256 tokenReserve = _getTokenReserve(virtualTokenReserve);
            uint256 _totalSupply = totalSupply;

            // mint liquidity tokens
            if (_totalSupply == 0) {
                liquidity = (numNfts * BASE * msg.value).sqrt() - MINIMUM_LIQUIDITY;
                _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
            } else {
                liquidity =
                    min(numNfts.mulDivDown(_totalSupply, nftReserve), msg.value.mulDivDown(_totalSupply, tokenReserve));
            }
            if (liquidity < minLiquidity) revert SharedPool__InsufficientLiquidityMinted();
            _mint(recipient, liquidity);
        }

        /// -----------------------------------------------------------------------
        /// Effects
        /// -----------------------------------------------------------------------

        // update pair params
        _pair.changeDelta((virtualNftReserve + numNfts).safeCastTo128());
        _pair.changeSpotPrice((virtualTokenReserve + msg.value).safeCastTo128());

        // transfer NFTs from msg.sender to pair
        ERC1155(nft()).safeTransferFrom(msg.sender, address(_pair), nftId(), numNfts, "");
    }

    function redeem(uint256 liquidity, uint256 minNumNftOutput, uint256 minTokenOutput, address recipient)
        external
        returns (uint256 numNftOutput, uint256 tokenOutput)
    {
        /// -----------------------------------------------------------------------
        /// Variable loads
        /// -----------------------------------------------------------------------

        LSSVMPairETH _pair = pair();
        uint128 virtualNftReserve = _pair.delta();
        uint128 virtualTokenReserve = _pair.spotPrice();
        uint256 _nftId = nftId();

        /// -----------------------------------------------------------------------
        /// State updates
        /// -----------------------------------------------------------------------

        // compute asset amounts corresponding to liquidity
        uint256 decimalNftAmount;
        {
            uint256 _totalSupply = totalSupply;
            decimalNftAmount = liquidity.mulDivDown(_getNftReserve(virtualNftReserve) * BASE, _totalSupply); // likely not a whole number, 18 decimals
            tokenOutput = liquidity.mulDivDown(_getTokenReserve(virtualTokenReserve), _totalSupply);
        }

        {
            // modify asset amounts so that the NFT amount is a whole number
            // this is done by simulating swapping the fractional amount (either round up or down)
            uint256 fractionalNftAmount = decimalNftAmount % BASE;
            if (fractionalNftAmount >= HALF_BASE) {
                // round up by simulating buying fractional NFT
                numNftOutput = (decimalNftAmount - fractionalNftAmount) / BASE + 1;
                uint256 fractionalBuyNumItems = BASE - fractionalNftAmount;
                uint256 inputValueWithoutFee =
                    (fractionalBuyNumItems * virtualTokenReserve) / (virtualNftReserve * BASE - fractionalBuyNumItems);
                (,, uint256 royaltyAmount) = _pair.calculateRoyaltiesView(_nftId, inputValueWithoutFee);
                tokenOutput -= inputValueWithoutFee.mulWadUp(BASE + pairFactory().protocolFeeMultiplier() + _pair.fee())
                    + royaltyAmount;
            } else {
                // round down by simulating selling fractional NFT
                numNftOutput = (decimalNftAmount - fractionalNftAmount) / BASE;
                uint256 outputValue = (
                    (fractionalNftAmount * virtualTokenReserve) / (virtualNftReserve * BASE + fractionalNftAmount)
                ).mulWadDown(BASE - pairFactory().protocolFeeMultiplier() - _pair.fee());
                (,, uint256 royaltyAmount) = _pair.calculateRoyaltiesView(_nftId, outputValue);
                tokenOutput += outputValue - royaltyAmount;
            }
        }

        // slippage check
        if (numNftOutput < minNumNftOutput || tokenOutput < minTokenOutput) revert SharedPool__InsufficientOutput();

        // burn liquidity tokens from msg.sender
        _burn(msg.sender, liquidity);

        /// -----------------------------------------------------------------------
        /// Effects
        /// -----------------------------------------------------------------------

        // update pair params
        _pair.changeDelta((virtualNftReserve - numNftOutput).safeCastTo128());
        _pair.changeSpotPrice((virtualTokenReserve - tokenOutput).safeCastTo128());

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
        _pair.withdrawETH(tokenOutput);

        // transfer NFTs to recipient
        ERC1155(nft()).safeTransferFrom(address(this), recipient, _nftId, numNftOutput, "");

        // transfer tokens to recipient
        SafeTransferLib.safeTransferETH(recipient, tokenOutput);
    }

    function getNftReserve() external view returns (uint256 nftReserve) {
        return _getNftReserve(pair().delta());
    }

    function getTokenReserve() external view returns (uint256 tokenReserve) {
        return _getTokenReserve(pair().spotPrice());
    }

    receive() external payable {}

    fallback() external payable {}

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    /// @notice Reads an immutable arg with type uint128
    /// @param argOffset The offset of the arg in the packed data
    /// @return arg The arg value
    function _getArgUint128(uint256 argOffset) internal pure returns (uint128 arg) {
        uint256 offset = _getImmutableArgsOffset();
        // solhint-disable-next-line no-inline-assembly
        assembly {
            arg := shr(0x80, calldataload(add(offset, argOffset)))
        }
    }

    function _getNftReserve(uint128 delta) internal pure returns (uint256 nftReserve) {
        // TODO: handle negative edge case
        return delta - initialDelta();
    }

    function _getTokenReserve(uint128 spotPrice) internal pure returns (uint256 tokenReserve) {
        // TODO: handle negative edge case
        return spotPrice - initialSpotPrice();
    }
}
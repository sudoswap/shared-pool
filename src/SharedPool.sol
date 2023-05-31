// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {Clone} from "@clones/Clone.sol";

import {LSSVMPair} from "lssvm2/LSSVMPair.sol";
import {LSSVMPairFactory} from "lssvm2/LSSVMPairFactory.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import "./lib/Math.sol";

abstract contract SharedPool is Clone, ERC20("Sudoswap Shared Pool", "SUDO-POOL", 18) {
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
    function pair() public pure returns (LSSVMPair pair_) {
        return LSSVMPair(payable(_getArgAddress(0x00)));
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

    function token() public pure virtual returns (ERC20);

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    function getNftReserve() external view returns (uint256 nftReserve) {
        return _getNftReserve(nft(), pair());
    }

    function getTokenReserve() external view returns (uint256 tokenReserve) {
        return _getTokenReserve(token(), pair());
    }

    receive() external payable {}

    fallback() external payable {}

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    function _deposit(LSSVMPair _pair, uint256 numNfts, uint256 minLiquidity, uint256 tokenInput, address recipient)
        internal
        returns (uint256 liquidity)
    {
        /// -----------------------------------------------------------------------
        /// Variable loads
        /// -----------------------------------------------------------------------

        uint256 nftReserve = _getNftReserve(nft(), _pair);
        uint256 tokenReserve = _getTokenReserve(token(), _pair);

        /// -----------------------------------------------------------------------
        /// State updates
        /// -----------------------------------------------------------------------

        {
            uint256 _totalSupply = totalSupply;

            // mint liquidity tokens
            if (_totalSupply == 0) {
                liquidity = (numNfts * BASE * tokenInput).sqrt() - MINIMUM_LIQUIDITY;
                _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
            } else {
                liquidity =
                    min(numNfts.mulDivDown(_totalSupply, nftReserve), tokenInput.mulDivDown(_totalSupply, tokenReserve));
            }
            if (liquidity < minLiquidity) revert SharedPool__InsufficientLiquidityMinted();
            _mint(recipient, liquidity);
        }

        /// -----------------------------------------------------------------------
        /// Effects
        /// -----------------------------------------------------------------------

        // update pair params
        uint256 _initialDelta = initialDelta();
        uint256 _initialSpotPrice = initialSpotPrice();
        _pair.changeDelta((_initialDelta + nftReserve + numNfts).safeCastTo128());
        _pair.changeSpotPrice((_initialSpotPrice + tokenReserve + tokenInput).safeCastTo128());
    }

    function _redeem(
        LSSVMPair _pair,
        uint256 liquidity,
        uint256 minNumNftOutput,
        uint256 minTokenOutput,
        uint256 royaltyAssetId
    ) internal returns (uint256 numNftOutput, uint256 tokenOutput) {
        /// -----------------------------------------------------------------------
        /// Variable loads
        /// -----------------------------------------------------------------------

        uint256 virtualNftReserve;
        uint256 virtualTokenReserve;

        /// -----------------------------------------------------------------------
        /// State updates
        /// -----------------------------------------------------------------------

        // compute asset amounts corresponding to liquidity
        uint256 decimalNftAmount;
        {
            uint256 nftReserve = _getNftReserve(nft(), _pair);
            uint256 tokenReserve = _getTokenReserve(token(), _pair);
            uint256 _totalSupply = totalSupply;
            decimalNftAmount = liquidity.mulDivDown(nftReserve * BASE, _totalSupply); // likely not a whole number, 18 decimals
            tokenOutput = liquidity.mulDivDown(tokenReserve, _totalSupply);
            virtualNftReserve = initialDelta() + nftReserve;
            virtualTokenReserve = initialSpotPrice() + tokenReserve;
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
                (,, uint256 royaltyAmount) = _pair.calculateRoyaltiesView(royaltyAssetId, inputValueWithoutFee);
                tokenOutput -= inputValueWithoutFee.mulWadUp(BASE + pairFactory().protocolFeeMultiplier() + _pair.fee())
                    + royaltyAmount;
            } else {
                // round down by simulating selling fractional NFT
                numNftOutput = (decimalNftAmount - fractionalNftAmount) / BASE;
                uint256 outputValue = (
                    (fractionalNftAmount * virtualTokenReserve) / (virtualNftReserve * BASE + fractionalNftAmount)
                ).mulWadDown(BASE - pairFactory().protocolFeeMultiplier() - _pair.fee());
                (,, uint256 royaltyAmount) = _pair.calculateRoyaltiesView(royaltyAssetId, outputValue);
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
    }

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

    function _getNftReserve(address _nft, LSSVMPair _pair) internal view virtual returns (uint256 nftReserve);

    function _getTokenReserve(ERC20 _token, LSSVMPair _pair) internal view virtual returns (uint256 tokenReserve);

    function _getTokenInput(bytes calldata extraData) internal view virtual returns (uint256 tokenInput);

    function _pullTokensFromSender(ERC20 _token, address to, uint256 amount) internal virtual;

    function _pushTokens(ERC20 _token, address to, uint256 amount) internal virtual;

    function _withdrawTokensFromPair(ERC20 _token, LSSVMPair _pair, uint256 amount) internal virtual;
}

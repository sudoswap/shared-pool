// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {Clone} from "@clones/Clone.sol";

import {LSSVMPair} from "lssvm2/LSSVMPair.sol";
import {LSSVMPairFactory} from "lssvm2/LSSVMPairFactory.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeCastLib} from "solmate/utils/SafeCastLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import "./lib/Math.sol";
import "./lib/ReentrancyGuard.sol";

/// @title SharedPool
/// @author zefram.eth
/// @notice Shared Sudoswap pair using the XYK curve. Represents liquidity shares using an ERC20 token.
/// @dev Performs fractional swap during redemption to ensure only whole NFTs are withdrawn.
abstract contract SharedPool is Clone, ERC20("Sudoswap Shared Pool", "SUDO-POOL", 18), ReentrancyGuard {
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

    error SharedPool__ZeroInput();
    error SharedPool__DeadlinePassed();
    error SharedPool__InsufficientOutput();
    error SharedPool__RedeemAmountTooSmall();
    error SharedPool__InsufficientNftAmount();
    error SharedPool__InsufficientTokenAmount();

    /// -----------------------------------------------------------------------
    /// Modifiers
    /// -----------------------------------------------------------------------

    modifier beforeDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert SharedPool__DeadlinePassed();
        _;
    }

    /// -----------------------------------------------------------------------
    /// Initialization
    /// -----------------------------------------------------------------------

    /// @notice Initializes the contract.
    /// @dev ReentrancyGuard requires initializing the flag to 1 to save gas during
    /// subsequent calls.
    function initialize() external {
        // no need to check if the contract is already initialized
        // since __ReentrancyGuard_init() already does that
        __ReentrancyGuard_init();
    }

    /// -----------------------------------------------------------------------
    /// Immutable args
    /// -----------------------------------------------------------------------

    /// @notice The Sudo XYK curve pool used to provide liquidity
    function pair() public pure returns (LSSVMPair pair_) {
        return LSSVMPair(payable(_getArgAddress(0x00)));
    }

    /// @notice The initial delta value of the Sudo XYK curve pool. Used for computing NFT balance
    /// changes in the Sudo pair, since the delta stores the virtual NFT balance.
    function initialDelta() public pure returns (uint128 initialDelta_) {
        return _getArgUint128(0x14);
    }

    /// @notice The initial delta value of the Sudo XYK curve pool. Used for computing token balance
    /// changes in the Sudo pair, since the spot price stores the virtual token balance.
    function initialSpotPrice() public pure returns (uint128) {
        return _getArgUint128(0x24);
    }

    /// @notice The NFT used by the Sudo pair.
    function nft() public pure returns (address) {
        return _getArgAddress(0x34);
    }

    /// @notice The Sudoswap LSSVMPairFactory contract
    function pairFactory() public pure returns (LSSVMPairFactory) {
        return LSSVMPairFactory(payable(_getArgAddress(0x48)));
    }

    /// @notice The token used by the Sudo pair. Returns 0 for ETH pools.
    function token() public pure virtual returns (ERC20);

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    /// @notice Syncs the Sudo pair's parameters to match the current balances. Usually used
    /// for adding trade fees to the XYK curve reserves. deposit() and redeem() automatically
    /// syncs the reserves so this function is not called often in practice.
    function sync() external nonReentrant {
        LSSVMPair _pair = pair();
        uint256 nftReserve = _getNftReserve(nft(), _pair);
        uint256 tokenReserve = _getTokenReserve(token(), _pair);
        uint256 _initialDelta = initialDelta();
        uint256 _initialSpotPrice = initialSpotPrice();
        _pair.changeDelta((_initialDelta + nftReserve).safeCastTo128());
        _pair.changeSpotPrice((_initialSpotPrice + tokenReserve).safeCastTo128());
    }

    /// @notice Returns the number of NFTs in the Sudo pair.
    function getNftReserve() external view returns (uint256 nftReserve) {
        return _getNftReserve(nft(), pair());
    }

    /// @notice Returns the token balance of the Sudo pair.
    function getTokenReserve() external view returns (uint256 tokenReserve) {
        return _getTokenReserve(token(), pair());
    }

    /// @dev Included to silence compiler warnings
    receive() external payable {}

    /// @dev Clone contracts with immutable args must use fallback() to receive Ether since the calldata is never empty.
    fallback() external payable {}

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    function _deposit(
        LSSVMPair _pair,
        uint256 amountNftDesired,
        uint256 amountTokenDesired,
        uint256 amountNftMin,
        uint256 amountTokenMin,
        address recipient
    ) internal returns (uint256 amountNft, uint256 amountToken, uint256 liquidity) {
        /// -----------------------------------------------------------------------
        /// Verification
        /// -----------------------------------------------------------------------

        if (amountNftDesired == 0 && amountTokenDesired == 0) revert SharedPool__ZeroInput();

        /// -----------------------------------------------------------------------
        /// Variable loads
        /// -----------------------------------------------------------------------

        uint256 nftReserve = _getNftReserve(nft(), _pair);
        uint256 tokenReserve = _getTokenReserve(token(), _pair);
        uint256 virtualNftReserve = initialDelta() + nftReserve;
        uint256 virtualTokenReserve = initialSpotPrice() + tokenReserve;

        /// -----------------------------------------------------------------------
        /// State updates
        /// -----------------------------------------------------------------------

        // compute the correct amount of NFTs and tokens to add so that the current proportion of assets in the pool is maintained
        {
            uint256 amountTokenOptimal = amountNftDesired.mulDivUp(virtualTokenReserve, virtualNftReserve);
            if (amountTokenOptimal <= amountTokenDesired) {
                if (amountTokenOptimal < amountTokenMin) revert SharedPool__InsufficientTokenAmount();
                (amountNft, amountToken) = (amountNftDesired, amountTokenOptimal);
            } else {
                uint256 amountNftOptimal = amountTokenDesired.mulDivUp(virtualNftReserve, virtualTokenReserve);
                assert(amountNftOptimal <= amountNftDesired);
                if (amountNftOptimal < amountNftMin) revert SharedPool__InsufficientNftAmount();
                (amountNft, amountToken) = (amountNftOptimal, amountTokenDesired);
            }
        }

        // mint liquidity tokens
        {
            uint256 _totalSupply = totalSupply;

            if (_totalSupply == 0) {
                liquidity = (amountNft * BASE * amountToken).sqrt() - MINIMUM_LIQUIDITY;
                _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
            } else {
                liquidity = min(
                    amountNft.mulDivDown(_totalSupply, nftReserve), amountToken.mulDivDown(_totalSupply, tokenReserve)
                );
            }
            _mint(recipient, liquidity);
        }

        /// -----------------------------------------------------------------------
        /// Effects
        /// -----------------------------------------------------------------------

        // update pair params
        _pair.changeDelta((virtualNftReserve + amountNft).safeCastTo128());
        _pair.changeSpotPrice((virtualTokenReserve + amountToken).safeCastTo128());
    }

    function _redeem(
        LSSVMPair _pair,
        uint256 liquidity,
        uint256 minNumNftOutput,
        uint256 minTokenOutput,
        uint256 royaltyAssetId
    )
        internal
        returns (
            uint256 numNftOutput,
            uint256 tokenOutput,
            address payable[] memory royaltyRecipients,
            uint256[] memory royaltyAmounts,
            uint256 royaltyAmount,
            uint256 protocolFeeAmount
        )
    {
        /// -----------------------------------------------------------------------
        /// Verification
        /// -----------------------------------------------------------------------

        if (liquidity == 0) revert SharedPool__ZeroInput();

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
            if (decimalNftAmount == 0 && tokenOutput == 0) revert SharedPool__RedeemAmountTooSmall();
            virtualNftReserve = initialDelta() + nftReserve;
            virtualTokenReserve = initialSpotPrice() + tokenReserve;
        }

        {
            // modify asset amounts so that the NFT amount is a whole number
            // this is done by simulating swapping the fractional amount (either round up or down)
            uint256 protocolFeeMultiplier = pairFactory().protocolFeeMultiplier();
            uint256 fractionalNftAmount = decimalNftAmount % BASE;
            uint256 fractionalTokenAmount =
                decimalNftAmount == 0 ? 0 : fractionalNftAmount.mulDivDown(tokenOutput, decimalNftAmount);
            if (fractionalNftAmount >= HALF_BASE) {
                // round up by simulating buying fractional NFT
                // steps:
                // 1. remove whole NFTs & corresponding tokens from liquidity
                // 2. use part of removed tokens to buy the remaining fractional NFT
                numNftOutput = (decimalNftAmount - fractionalNftAmount) / BASE + 1;
                uint256 fractionalBuyNumItems = BASE - fractionalNftAmount;
                uint256 inputValueWithoutFee = (
                    fractionalBuyNumItems * (virtualTokenReserve - tokenOutput + fractionalTokenAmount)
                ) / ((virtualNftReserve * BASE - decimalNftAmount + fractionalNftAmount) - fractionalBuyNumItems);
                (royaltyRecipients, royaltyAmounts, royaltyAmount) =
                    _pair.calculateRoyaltiesView(royaltyAssetId, inputValueWithoutFee);
                protocolFeeAmount = inputValueWithoutFee.mulWadUp(protocolFeeMultiplier);
                uint256 inputValue =
                    inputValueWithoutFee.mulWadUp(BASE + protocolFeeMultiplier + _pair.fee()) + royaltyAmount;
                if (tokenOutput >= inputValue) {
                    tokenOutput -= inputValue;
                } else {
                    // token output isn't enough to purchase fractional NFT & round up
                    // sell fractional NFT & round down instead
                    // steps:
                    // 1. remove fractional NFT & corresponding tokens from liquidity
                    // 2. sell fractional NFT to remaining liquidity
                    numNftOutput -= 1;
                    uint256 outputValueWithoutFee = (
                        fractionalNftAmount * (virtualTokenReserve - fractionalTokenAmount)
                    ) / (virtualNftReserve * BASE);
                    protocolFeeAmount = outputValueWithoutFee.mulWadUp(protocolFeeMultiplier);
                    uint256 outputValue = outputValueWithoutFee.mulWadDown(BASE - protocolFeeMultiplier - _pair.fee());
                    (royaltyRecipients, royaltyAmounts, royaltyAmount) =
                        _pair.calculateRoyaltiesView(royaltyAssetId, outputValue);
                    tokenOutput += outputValue - royaltyAmount;
                }
            } else if (fractionalNftAmount == 0) {
                // withdrawing whole NFTs
                numNftOutput = decimalNftAmount / BASE;
            } else {
                // round down by simulating selling fractional NFT
                // steps:
                // 1. remove fractional NFT & corresponding tokens from liquidity
                // 2. sell fractional NFT to remaining liquidity
                numNftOutput = (decimalNftAmount - fractionalNftAmount) / BASE;
                uint256 outputValueWithoutFee =
                    (fractionalNftAmount * (virtualTokenReserve - fractionalTokenAmount)) / (virtualNftReserve * BASE);
                protocolFeeAmount = outputValueWithoutFee.mulWadUp(protocolFeeMultiplier);
                uint256 outputValue = outputValueWithoutFee.mulWadDown(BASE - protocolFeeMultiplier - _pair.fee());
                (royaltyRecipients, royaltyAmounts, royaltyAmount) =
                    _pair.calculateRoyaltiesView(royaltyAssetId, outputValue);
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

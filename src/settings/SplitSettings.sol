// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {Clone} from "clones-with-immutable-args/Clone.sol";
import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {ERC1155TokenReceiver} from "solmate/tokens/ERC1155.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import {IOwnershipTransferReceiver} from "lssvm2/lib/IOwnershipTransferReceiver.sol";
import {OwnableWithTransferCallback} from "lssvm2/lib/OwnableWithTransferCallback.sol";

import {ILSSVMPair} from "lssvm2/ILSSVMPair.sol";
import {LSSVMPair} from "lssvm2/LSSVMPair.sol";
import {LSSVMPairETH} from "lssvm2/LSSVMPairETH.sol";
import {ILSSVMPairFactoryLike} from "lssvm2/ILSSVMPairFactoryLike.sol";
import {ISettings} from "lssvm2/settings/ISettings.sol";
import {Splitter} from "lssvm2/settings/Splitter.sol";
import {LSSVMPairERC1155} from "lssvm2/erc1155/LSSVMPairERC1155.sol";

contract SplitSettings is
    IOwnershipTransferReceiver,
    OwnableWithTransferCallback,
    Clone,
    ISettings,
    ERC721TokenReceiver,
    ERC1155TokenReceiver
{
    using ClonesWithImmutableArgs for address;
    using SafeTransferLib for address;
    using SafeTransferLib for ERC20;

    uint96 constant MAX_SETTABLE_FEE = 0.2e18; // Max fee of 20% (0.2)

    struct SimplePairInfo {
        address prevOwner;
        address prevFeeRecipient;
    }

    mapping(address => SimplePairInfo) public pairInfos;
    address payable public settingsFeeRecipient;

    Splitter immutable splitterImplementation;
    ILSSVMPairFactoryLike immutable pairFactory;

    event SplitSettings__PairAddedSettings(address indexed pairAddress);
    event SplitSettings__PairRemovedSettings(address indexed pairAddress);

    constructor(Splitter _splitterImplementation, ILSSVMPairFactoryLike _pairFactory) {
        splitterImplementation = _splitterImplementation;
        pairFactory = _pairFactory;
    }

    function initialize(address _owner, address payable _settingsFeeRecipient) public {
        require(owner() == address(0), "Initialized");
        __Ownable_init(_owner);
        settingsFeeRecipient = _settingsFeeRecipient;
    }

    // Immutable params

    /**
     * @return Returns the trade fee split for the duration of the Settings, in bps
     */
    function getFeeSplitBps() public pure returns (uint64) {
        return _getArgUint64(0);
    }

    /**
     * @return Returns the modified royalty amount for the duration of the Settings, in bps
     */
    function getSettingsRoyaltyBps() public pure returns (uint64) {
        return _getArgUint64(8);
    }

    // Admin functions

    /**
     * @param newFeeRecipient The address to receive all payments plus trade fees
     */
    function setSettingsFeeRecipient(address payable newFeeRecipient) public onlyOwner {
        settingsFeeRecipient = newFeeRecipient;
    }

    // View functions

    /**
     * @param pairAddress The address of the pair to look up
     * @return Returns the previously set fee recipient address for a pair
     */
    function getPrevFeeRecipientForPair(address pairAddress) public view returns (address) {
        return pairInfos[pairAddress].prevFeeRecipient;
    }

    /**
     * @notice Fetches the royalty info for a pair address
     * @param pairAddress The address of the pair to look up
     * @return Returns whether the royalty is enabled and the royalty bps if enabled
     */
    function getRoyaltyInfo(address pairAddress) external view returns (bool, uint96) {
        if (LSSVMPair(pairAddress).owner() == address(this)) {
            return (true, getSettingsRoyaltyBps());
        }
        return (false, 0);
    }

    // Functions intended to be called by the pair or pair owner

    /**
     * @notice Callback after ownership is transferred to this contract from a pair
     * This function performs the following:
     * - upfront payment, if any, is taken
     * - pair verification and nft verification (done in pair factory external call)
     * - the modified royalty bps is set (done in pair factory external call)
     * - the previous fee recipient / owner parameters are recorded and saved
     * - a new fee splitter clone is deployed
     * - the fee recipient of the pair is set to the fee splitter
     * @param prevOwner The owner of the pair calling transferOwnership
     */
    function onOwnershipTransferred(address prevOwner, bytes calldata) public payable {
        ILSSVMPair pair = ILSSVMPair(msg.sender);

        require(msg.value == 0, "0");

        // Only for trade pairs
        require(pair.poolType() == ILSSVMPair.PoolType.TRADE, "Only TRADE pairs");

        // Prevent high-fee trading pairs
        require(pair.fee() <= MAX_SETTABLE_FEE, "Fee too high");

        // Enable settings in factory contract. This also validates that msg.sender is a valid pair.
        try pairFactory.enableSettingsForPair(address(this), msg.sender) {}
        catch {
            revert("Pair verification failed");
        }

        // Store the original owner, unlock date, and old fee recipient
        pairInfos[msg.sender] =
            SimplePairInfo({prevOwner: prevOwner, prevFeeRecipient: ILSSVMPair(msg.sender).getFeeRecipient()});

        // Deploy the fee splitter clone
        // param1 = parent Settings address, i.e. address(this)
        // param2 = pair address, i.e. msg.sender
        bytes memory data = abi.encodePacked(address(this), msg.sender);
        address splitterAddress = address(splitterImplementation).clone(data);

        // Set the asset (i.e. fee) recipient to be the splitter clone
        ILSSVMPair(msg.sender).changeAssetRecipient(payable(splitterAddress));

        emit SplitSettings__PairAddedSettings(msg.sender);
    }

    /**
     * @notice Transfers ownership of the pair back to the original owner
     * @param pairAddress The address of the pair to reclaim ownership
     */
    function reclaimPair(address pairAddress) public {
        SimplePairInfo memory pairInfo = pairInfos[pairAddress];

        ILSSVMPair pair = ILSSVMPair(pairAddress);

        // Verify that the caller is the previous pair owner or admin of the NFT collection
        if (msg.sender != pairInfo.prevOwner && !pairFactory.authAllowedForToken(address(pair.nft()), msg.sender)) {
            revert("Not prev owner or authed");
        }

        // Split fees (if applicable)
        ILSSVMPairFactoryLike.PairTokenType pairTokenType = pairFactory.getPairTokenType(pairAddress);
        if (pairTokenType == ILSSVMPairFactoryLike.PairTokenType.ETH) {
            Splitter(payable(pair.getFeeRecipient())).withdrawAllETHInSplitter();
        } else if (pairTokenType == ILSSVMPairFactoryLike.PairTokenType.ERC20) {
            Splitter(payable(pair.getFeeRecipient())).withdrawAllBaseQuoteTokens();
        }

        // Change the fee recipient back
        pair.changeAssetRecipient(payable(pairInfo.prevFeeRecipient));

        // Disable the royalty override
        pairFactory.disableSettingsForPair(address(this), pairAddress);

        // Transfer ownership back to original pair owner
        OwnableWithTransferCallback(pairAddress).transferOwnership(pairInfo.prevOwner, "");

        // Remove pairInfo entry
        delete pairInfos[pairAddress];

        emit SplitSettings__PairRemovedSettings(pairAddress);
    }

    /**
     * @notice Allows a pair owner to adjust fee % even while a pair has Settings enabled
     * @param pairAddress The address of the pair to change fee
     * @param newFee The new fee to set the pair to, subject to MAX_FEE or less
     */
    function changeFee(address pairAddress, uint96 newFee) external {
        // Verify that the caller is the previous owner of the pair
        require(msg.sender == pairInfos[pairAddress].prevOwner, "Not prev owner");
        require(newFee <= MAX_SETTABLE_FEE, "Fee too high");
        ILSSVMPair(pairAddress).changeFee(newFee);
    }

    /**
     * @notice Allows a pair owner to adjust spot price / delta even while a pair is in an Settings, subject to liquidity considerations
     * @param pairAddress The address of the pair to change spot price and delta for
     * @param newSpotPrice The new spot price
     * @param newDelta The new delta
     */
    function changeSpotPriceAndDelta(address pairAddress, uint128 newSpotPrice, uint128 newDelta) external {
        // Verify that the caller is the previous owner of the pair
        require(msg.sender == pairInfos[pairAddress].prevOwner, "Not prev owner");

        ILSSVMPair pair = ILSSVMPair(pairAddress);
        pair.changeSpotPrice(newSpotPrice);
        pair.changeDelta(newDelta);
    }

    /**
     * @notice Allows owners or pair owners to bulk withdraw trade fees from a series of Splitters
     * @param splitterAddresses List of addresses of Splitters to withdraw from
     * @param isETHPair If the underlying Splitter's pair is an ETH pair or not
     */
    function bulkWithdrawFees(address[] calldata splitterAddresses, bool[] calldata isETHPair) external {
        for (uint256 i; i < splitterAddresses.length;) {
            Splitter splitter = Splitter(payable(splitterAddresses[i]));
            if (isETHPair[i]) {
                splitter.withdrawAllETHInSplitter();
            } else {
                splitter.withdrawAllBaseQuoteTokens();
            }
            unchecked {
                ++i;
            }
        }
    }

    function withdrawETH(address pairAddress, uint256 amount, address recipient) external {
        // Verify that the caller is the previous owner of the pair
        require(msg.sender == pairInfos[pairAddress].prevOwner, "Not prev owner");

        LSSVMPairETH(payable(pairAddress)).withdrawETH(amount);
        recipient.safeTransferETH(amount);
    }

    function withdrawERC20(address pairAddress, ERC20 token, uint256 amount, address recipient) external {
        // Verify that the caller is the previous owner of the pair
        require(msg.sender == pairInfos[pairAddress].prevOwner, "Not prev owner");

        LSSVMPair(pairAddress).withdrawERC20(token, amount);
        token.safeTransfer(recipient, amount);
    }

    function withdrawERC721(address pairAddress, IERC721 nft, uint256[] calldata nftIds, address recipient) external {
        // Verify that the caller is the previous owner of the pair
        require(msg.sender == pairInfos[pairAddress].prevOwner, "Not prev owner");

        LSSVMPair(pairAddress).withdrawERC721(nft, nftIds);
        uint256 numNfts = nftIds.length;
        unchecked {
            for (uint256 i; i < numNfts; ++i) {
                nft.safeTransferFrom(address(this), recipient, nftIds[i]);
            }
        }
    }

    function withdrawERC1155(
        address pairAddress,
        IERC1155 nft,
        uint256[] calldata nftIds,
        uint256[] calldata amounts,
        address recipient
    ) external {
        // Verify that the caller is the previous owner of the pair
        require(msg.sender == pairInfos[pairAddress].prevOwner, "Not prev owner");

        LSSVMPair(pairAddress).withdrawERC1155(nft, nftIds, amounts);
        nft.safeBatchTransferFrom(address(this), recipient, nftIds, amounts, bytes(""));
    }

    fallback() external payable {}
}

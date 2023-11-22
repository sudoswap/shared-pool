// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {ICurve} from "lssvm2/bonding-curves/ICurve.sol";
import {LSSVMPair} from "lssvm2/LSSVMPair.sol";
import {LSSVMPairERC721ETH} from "lssvm2/erc721/LSSVMPairERC721ETH.sol";
import {LSSVMPairERC721ERC20} from "lssvm2/erc721/LSSVMPairERC721ERC20.sol";
import {LSSVMPairERC1155ETH} from "lssvm2/erc1155/LSSVMPairERC1155ETH.sol";
import {LSSVMPairERC1155ERC20} from "lssvm2/erc1155/LSSVMPairERC1155ERC20.sol";

interface ILSSVMPairFactory {
    function createPairERC721ETH(
        IERC721 _nft,
        ICurve _bondingCurve,
        address payable _assetRecipient,
        LSSVMPair.PoolType _poolType,
        uint128 _delta,
        uint96 _fee,
        uint128 _spotPrice,
        address _propertyChecker,
        uint256[] calldata _initialNFTIDs
    ) external payable returns (LSSVMPairERC721ETH pair);

    struct CreateERC721ERC20PairParams {
        ERC20 token;
        IERC721 nft;
        ICurve bondingCurve;
        address payable assetRecipient;
        LSSVMPair.PoolType poolType;
        uint128 delta;
        uint96 fee;
        uint128 spotPrice;
        address propertyChecker;
        uint256[] initialNFTIDs;
        uint256 initialTokenBalance;
    }

    function createPairERC721ERC20(
        CreateERC721ERC20PairParams calldata params
    ) external returns (LSSVMPairERC721ERC20 pair);

    function createPairERC1155ETH(
        IERC1155 _nft,
        ICurve _bondingCurve,
        address payable _assetRecipient,
        LSSVMPairERC1155ETH.PoolType _poolType,
        uint128 _delta,
        uint96 _fee,
        uint128 _spotPrice,
        uint256 _nftId,
        uint256 _initialNFTBalance
    ) external payable returns (LSSVMPairERC1155ETH pair);

    struct CreateERC1155ERC20PairParams {
        ERC20 token;
        IERC1155 nft;
        ICurve bondingCurve;
        address payable assetRecipient;
        LSSVMPairERC1155ERC20.PoolType poolType;
        uint128 delta;
        uint96 fee;
        uint128 spotPrice;
        uint256 nftId;
        uint256 initialNFTBalance;
        uint256 initialTokenBalance;
    }

    function createPairERC1155ERC20(
        CreateERC1155ERC20PairParams calldata params
    ) external returns (LSSVMPairERC1155ERC20 pair);
}

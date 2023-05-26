// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {ClonesWithImmutableArgs} from "@clones/ClonesWithImmutableArgs.sol";
import {LSSVMPairFactory, LSSVMPair, ICurve} from "lssvm2/LSSVMPairFactory.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {ERC1155} from "solmate/tokens/ERC1155.sol";

import {SharedPoolERC721} from "./SharedPoolERC721.sol";
import {SharedPoolERC1155} from "./SharedPoolERC1155.sol";

/// @title SharedPoolFactory
/// @author zefram.eth
/// @notice Factory for deploying SharedPool contracts cheaply
contract SharedPoolFactory {
    /// -----------------------------------------------------------------------
    /// Library usage
    /// -----------------------------------------------------------------------

    using ClonesWithImmutableArgs for address;

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event CreateSharedPoolERC721(SharedPoolERC721 sharedPool);
    event CreateSharedPoolERC1155(SharedPoolERC1155 sharedPool);

    /// -----------------------------------------------------------------------
    /// Immutable parameters
    /// -----------------------------------------------------------------------

    /// @notice The contract used as the template for all SharedPoolERC721 contracts created
    SharedPoolERC721 internal immutable implementation;

    /// @notice The contract used as the template for all SharedPoolERC1155 contracts created
    SharedPoolERC1155 internal immutable implementationERC1155;

    /// @notice The LSSVMPairFactory contract used for deploying pairs
    LSSVMPairFactory internal immutable pairFactory;

    /// @notice The bonding curve used by the pair (should be XYK curve)
    ICurve internal immutable xykCurve;

    constructor(
        SharedPoolERC721 implementation_,
        SharedPoolERC1155 implementationERC1155_,
        LSSVMPairFactory pairFactory_,
        ICurve xykCurve_
    ) {
        implementation = implementation_;
        implementationERC1155 = implementationERC1155_;
        pairFactory = pairFactory_;
        xykCurve = xykCurve_;
    }

    /// @notice Creates a SharedPoolERC721 contract
    /// @dev Uses a modified minimal proxy contract that stores immutable parameters in code and
    /// passes them in through calldata. See ClonesWithImmutableArgs.
    /// @param nft The NFT used by the LSSVMPair
    /// @param delta The initial delta value of the pair
    /// @param spotPrice The initial spotPrice value of the pair
    /// @param fee The trade fee value of the pair
    /// @param propertyChecker The property checker used by the pair
    /// @return sharedPool The created SharedPool contract
    function createSharedPoolERC721(ERC721 nft, uint128 delta, uint128 spotPrice, uint96 fee, address propertyChecker)
        external
        returns (SharedPoolERC721 sharedPool)
    {
        // deploy trade pair with XYK curve
        uint256[] memory empty;
        LSSVMPair pair = pairFactory.createPairERC721ETH(
            IERC721(address(nft)),
            xykCurve,
            payable(address(0)),
            LSSVMPair.PoolType.TRADE,
            delta,
            fee,
            spotPrice,
            propertyChecker,
            empty
        );

        // deploy SharedPoolERC721
        bytes memory data = abi.encodePacked(pair, delta, spotPrice, nft, pairFactory);
        sharedPool = SharedPoolERC721(payable(address(implementation).clone(data)));

        // transfer ownership of pair to SharedPool
        pair.transferOwnership(address(sharedPool), "");

        emit CreateSharedPoolERC721(sharedPool);
    }

    /// @notice Creates a SharedPoolERC1155 contract
    /// @dev Uses a modified minimal proxy contract that stores immutable parameters in code and
    /// passes them in through calldata. See ClonesWithImmutableArgs.
    /// @param nft The NFT used by the LSSVMPair
    /// @param delta The initial delta value of the pair
    /// @param spotPrice The initial spotPrice value of the pair
    /// @param fee The trade fee value of the pair
    /// @param nftId The nftId used by the pair
    /// @return sharedPool The created SharedPool contract
    function createSharedPoolERC1155(ERC1155 nft, uint128 delta, uint128 spotPrice, uint96 fee, uint256 nftId)
        external
        returns (SharedPoolERC1155 sharedPool)
    {
        // deploy trade pair with XYK curve
        LSSVMPair pair = pairFactory.createPairERC1155ETH(
            IERC1155(address(nft)),
            xykCurve,
            payable(address(0)),
            LSSVMPair.PoolType.TRADE,
            delta,
            fee,
            spotPrice,
            nftId,
            0
        );

        // deploy SharedPool
        bytes memory data = abi.encodePacked(pair, delta, spotPrice, nft, pairFactory, nftId);
        sharedPool = SharedPoolERC1155(payable(address(implementationERC1155).clone(data)));

        // transfer ownership of pair to SharedPool
        pair.transferOwnership(address(sharedPool), "");

        emit CreateSharedPoolERC1155(sharedPool);
    }
}

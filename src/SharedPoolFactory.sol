// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {ClonesWithImmutableArgs} from "@clones/ClonesWithImmutableArgs.sol";
import {LSSVMPair, ICurve} from "lssvm2/LSSVMPairFactory.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import {LibString} from "solady/src/utils/LibString.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {ERC1155} from "solmate/tokens/ERC1155.sol";

import {SharedPoolERC721ETH} from "./SharedPoolERC721ETH.sol";
import {SharedPoolERC721ERC20} from "./SharedPoolERC721ERC20.sol";
import {SharedPoolERC1155ETH} from "./SharedPoolERC1155ETH.sol";
import {SharedPoolERC1155ERC20} from "./SharedPoolERC1155ERC20.sol";
import {ILSSVMPairFactory} from "./ILSSVMPairFactory.sol";

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

    event CreateSharedPoolERC721ETH(SharedPoolERC721ETH sharedPool);
    event CreateSharedPoolERC721ERC20(SharedPoolERC721ERC20 sharedPool);
    event CreateSharedPoolERC1155ETH(SharedPoolERC1155ETH sharedPool);
    event CreateSharedPoolERC1155ERC20(SharedPoolERC1155ERC20 sharedPool);

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    error SharedPoolFactory__StringTooLong();

    /// -----------------------------------------------------------------------
    /// Immutable parameters
    /// -----------------------------------------------------------------------

    /// @notice The contract used as the template for all SharedPoolERC721ETH contracts created
    SharedPoolERC721ETH internal immutable implementationERC721ETH;

    /// @notice The contract used as the template for all SharedPoolERC721ERC20 contracts created
    SharedPoolERC721ERC20 internal immutable implementationERC721ERC20;

    /// @notice The contract used as the template for all SharedPoolERC1155ETH contracts created
    SharedPoolERC1155ETH internal immutable implementationERC1155ETH;

    /// @notice The contract used as the template for all SharedPoolERC1155ERC20 contracts created
    SharedPoolERC1155ERC20 internal immutable implementationERC1155ERC20;

    /// @notice The LSSVMPairFactory contract used for deploying pairs
    ILSSVMPairFactory internal immutable pairFactory;

    /// @notice The bonding curve used by the pair (should be XYK curve)
    ICurve internal immutable xykCurve;

    constructor(
        SharedPoolERC721ETH implementationERC721ETH_,
        SharedPoolERC721ERC20 implementationERC721ERC20_,
        SharedPoolERC1155ETH implementationERC1155ETH_,
        SharedPoolERC1155ERC20 implementationERC1155ERC20_,
        ILSSVMPairFactory pairFactory_,
        ICurve xykCurve_
    ) {
        implementationERC721ETH = implementationERC721ETH_;
        implementationERC721ERC20 = implementationERC721ERC20_;
        implementationERC1155ETH = implementationERC1155ETH_;
        implementationERC1155ERC20 = implementationERC1155ERC20_;
        pairFactory = pairFactory_;
        xykCurve = xykCurve_;
    }

    /// @notice Creates a SharedPoolERC721ETH contract
    /// @dev Uses a modified minimal proxy contract that stores immutable parameters in code and
    /// passes them in through calldata. See ClonesWithImmutableArgs.
    /// @param nft The NFT used by the LSSVMPair
    /// @param delta The initial delta value of the pair
    /// @param spotPrice The initial spotPrice value of the pair
    /// @param fee The trade fee value of the pair
    /// @param propertyChecker The property checker used by the pair
    /// @return sharedPool The created SharedPool contract
    function createSharedPoolERC721ETH(
        ERC721 nft,
        uint128 delta,
        uint128 spotPrice,
        uint96 fee,
        address propertyChecker,
        address settings,
        string calldata name,
        string calldata symbol
    ) external returns (SharedPoolERC721ETH sharedPool) {
        if (bytes(name).length > 31 || bytes(symbol).length > 31) revert SharedPoolFactory__StringTooLong();

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

        // deploy shared pool
        bytes memory data = abi.encodePacked(
            pair, delta, spotPrice, nft, pairFactory, settings, LibString.packOne(name), LibString.packOne(symbol)
        );
        sharedPool = SharedPoolERC721ETH(payable(address(implementationERC721ETH).clone(data)));

        // transfer ownership of pair to SharedPool
        pair.transferOwnership(address(sharedPool), "");

        // initialize shared pool
        sharedPool.initialize();

        emit CreateSharedPoolERC721ETH(sharedPool);
    }

    /// @notice Creates a SharedPoolERC721ERC20 contract
    /// @dev Uses a modified minimal proxy contract that stores immutable parameters in code and
    /// passes them in through calldata. See ClonesWithImmutableArgs.
    /// @param token The ERC20 token the pair trades
    /// @param nft The NFT used by the LSSVMPair
    /// @param delta The initial delta value of the pair
    /// @param spotPrice The initial spotPrice value of the pair
    /// @param fee The trade fee value of the pair
    /// @param propertyChecker The property checker used by the pair
    /// @return sharedPool The created SharedPool contract
    function createSharedPoolERC721ERC20(
        ERC20 token,
        ERC721 nft,
        uint128 delta,
        uint128 spotPrice,
        uint96 fee,
        address propertyChecker,
        address settings,
        string calldata name,
        string calldata symbol
    ) external returns (SharedPoolERC721ERC20 sharedPool) {
        if (bytes(name).length > 31 || bytes(symbol).length > 31) revert SharedPoolFactory__StringTooLong();

        // deploy trade pair with XYK curve
        uint256[] memory empty;
        LSSVMPair pair = pairFactory.createPairERC721ERC20(
            ILSSVMPairFactory.CreateERC721ERC20PairParams(
                token,
                IERC721(address(nft)),
                xykCurve,
                payable(address(0)),
                LSSVMPair.PoolType.TRADE,
                delta,
                fee,
                spotPrice,
                propertyChecker,
                empty,
                0
            )
        );

        // deploy shared pool
        bytes memory data = abi.encodePacked(
            pair,
            delta,
            spotPrice,
            nft,
            pairFactory,
            settings,
            LibString.packOne(name),
            LibString.packOne(symbol),
            token
        );
        sharedPool = SharedPoolERC721ERC20(payable(address(implementationERC721ERC20).clone(data)));

        // transfer ownership of pair to SharedPool
        pair.transferOwnership(address(sharedPool), "");

        // initialize shared pool
        sharedPool.initialize();

        emit CreateSharedPoolERC721ERC20(sharedPool);
    }

    /// @notice Creates a SharedPoolERC1155ETH contract
    /// @dev Uses a modified minimal proxy contract that stores immutable parameters in code and
    /// passes them in through calldata. See ClonesWithImmutableArgs.
    /// @param nft The NFT used by the LSSVMPair
    /// @param delta The initial delta value of the pair
    /// @param spotPrice The initial spotPrice value of the pair
    /// @param fee The trade fee value of the pair
    /// @param nftId The nftId used by the pair
    /// @return sharedPool The created SharedPool contract
    function createSharedPoolERC1155ETH(
        ERC1155 nft,
        uint128 delta,
        uint128 spotPrice,
        uint96 fee,
        uint256 nftId,
        address settings,
        string calldata name,
        string calldata symbol
    ) external returns (SharedPoolERC1155ETH sharedPool) {
        if (bytes(name).length > 31 || bytes(symbol).length > 31) revert SharedPoolFactory__StringTooLong();

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
        bytes memory data = abi.encodePacked(
            pair,
            delta,
            spotPrice,
            nft,
            pairFactory,
            settings,
            LibString.packOne(name),
            LibString.packOne(symbol),
            nftId
        );
        sharedPool = SharedPoolERC1155ETH(payable(address(implementationERC1155ETH).clone(data)));

        // transfer ownership of pair to SharedPool
        pair.transferOwnership(address(sharedPool), "");

        // initialize shared pool
        sharedPool.initialize();

        emit CreateSharedPoolERC1155ETH(sharedPool);
    }

    /// @notice Creates a SharedPoolERC1155ERC20 contract
    /// @dev Uses a modified minimal proxy contract that stores immutable parameters in code and
    /// passes them in through calldata. See ClonesWithImmutableArgs.
    /// @param token The ERC20 token the pair trades
    /// @param nft The NFT used by the LSSVMPair
    /// @param delta The initial delta value of the pair
    /// @param spotPrice The initial spotPrice value of the pair
    /// @param fee The trade fee value of the pair
    /// @param nftId The nftId used by the pair
    /// @return sharedPool The created SharedPool contract
    function createSharedPoolERC1155ERC20(
        ERC20 token,
        ERC1155 nft,
        uint128 delta,
        uint128 spotPrice,
        uint96 fee,
        uint256 nftId,
        address settings,
        string calldata name,
        string calldata symbol
    ) external returns (SharedPoolERC1155ERC20 sharedPool) {
        if (bytes(name).length > 31 || bytes(symbol).length > 31) revert SharedPoolFactory__StringTooLong();

        // deploy trade pair with XYK curve
        LSSVMPair pair = pairFactory.createPairERC1155ERC20(
            ILSSVMPairFactory.CreateERC1155ERC20PairParams(
                token,
                IERC1155(address(nft)),
                xykCurve,
                payable(address(0)),
                LSSVMPair.PoolType.TRADE,
                delta,
                fee,
                spotPrice,
                nftId,
                0,
                0
            )
        );

        // deploy SharedPool
        bytes memory data = abi.encodePacked(
            pair,
            delta,
            spotPrice,
            nft,
            pairFactory,
            settings,
            LibString.packOne(name),
            LibString.packOne(symbol),
            nftId,
            token
        );
        sharedPool = SharedPoolERC1155ERC20(payable(address(implementationERC1155ERC20).clone(data)));

        // transfer ownership of pair to SharedPool
        pair.transferOwnership(address(sharedPool), "");

        // initialize shared pool
        sharedPool.initialize();

        emit CreateSharedPoolERC1155ERC20(sharedPool);
    }
}

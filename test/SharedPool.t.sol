// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import {RoyaltyEngine} from "lssvm2/RoyaltyEngine.sol";
import {XykCurve} from "lssvm2/bonding-curves/XykCurve.sol";
import {LSSVMPair, LSSVMPairFactory} from "lssvm2/LSSVMPairFactory.sol";
import {LSSVMPairETH} from "lssvm2/LSSVMPairETH.sol";
import {LSSVMPairERC721ETH} from "lssvm2/erc721/LSSVMPairERC721ETH.sol";
import {LSSVMPairERC1155ETH} from "lssvm2/erc1155/LSSVMPairERC1155ETH.sol";
import {LSSVMPairERC721ERC20} from "lssvm2/erc721/LSSVMPairERC721ERC20.sol";
import {LSSVMPairERC1155ERC20} from "lssvm2/erc1155/LSSVMPairERC1155ERC20.sol";

import {RoyaltyRegistry} from "manifoldxyz/RoyaltyRegistry.sol";

import "../src/SharedPoolFactory.sol";
import {TestERC20} from "./mocks/TestERC20.sol";
import {TestERC721} from "./mocks/TestERC721.sol";
import {TestERC1155} from "./mocks/TestERC1155.sol";

contract SharedPoolTest is Test {
    uint256 constant PROTOCOL_FEE = 0.005e18;
    address payable constant PROTOCOL_FEE_RECIPIENT = payable(address(0xfee));
    uint256 constant MINIMUM_LIQUIDITY = 1e3;

    SharedPoolFactory factory;
    LSSVMPairFactory pairFactory;
    XykCurve bondingCurve;
    TestERC20 testERC20;
    TestERC721 testERC721;
    TestERC1155 testERC1155;

    function setUp() public {
        // deploy LSSVMPairFactory
        RoyaltyRegistry royaltyRegistry = new RoyaltyRegistry(address(0));
        royaltyRegistry.initialize(address(this));
        RoyaltyEngine royaltyEngine = new RoyaltyEngine(address(royaltyRegistry));
        LSSVMPairERC721ETH erc721ETHTemplate = new LSSVMPairERC721ETH(royaltyEngine);
        LSSVMPairERC721ERC20 erc721ERC20Template = new LSSVMPairERC721ERC20(royaltyEngine);
        LSSVMPairERC1155ETH erc1155ETHTemplate = new LSSVMPairERC1155ETH(royaltyEngine);
        LSSVMPairERC1155ERC20 erc1155ERC20Template = new LSSVMPairERC1155ERC20(royaltyEngine);
        pairFactory = new LSSVMPairFactory(
            erc721ETHTemplate,
            erc721ERC20Template,
            erc1155ETHTemplate,
            erc1155ERC20Template,
            PROTOCOL_FEE_RECIPIENT,
            PROTOCOL_FEE,
            address(this)
        );
        bondingCurve = new XykCurve();
        pairFactory.setBondingCurveAllowed(bondingCurve, true);

        // deploy shared pool factory
        factory = new SharedPoolFactory(
            new SharedPoolERC721ETH(),
            new SharedPoolERC721ERC20(),
            new SharedPoolERC1155ETH(),
            new SharedPoolERC1155ERC20(),
            pairFactory,
            bondingCurve
        );

        // deploy test tokens
        testERC20 = new TestERC20();
        testERC721 = new TestERC721();
        testERC1155 = new TestERC1155();
    }

    function test_createSharedPoolERC721ETH(uint256 delta, uint256 spotPrice, uint256 fee) public {
        delta = bound(delta, 0, 1000);
        spotPrice = bound(spotPrice, 0, 1e20);
        fee = bound(fee, 0, 1e17);

        SharedPoolERC721ETH pool =
            factory.createSharedPoolERC721ETH(testERC721, uint128(delta), uint128(spotPrice), uint96(fee), address(0));
        assertEq(pool.pair().delta(), delta);
        assertEq(pool.pair().spotPrice(), spotPrice);
        assertEq(pool.pair().fee(), fee);
        assertEq(pool.initialDelta(), delta);
        assertEq(pool.initialSpotPrice(), spotPrice);
        assertEq(pool.nft(), address(testERC721));
        assertEq(address(pool.pairFactory()), address(pairFactory));
        assertEq(address(pool.token()), address(0));
    }

    function test_deposit(uint256 delta, uint256 spotPrice, uint256 fee, uint256 numNfts, uint256 tokenAmount) public {
        delta = bound(delta, 0, 1000);
        spotPrice = bound(spotPrice, 0, 1e20);
        fee = bound(fee, 0, 1e17);
        numNfts = bound(numNfts, 1, 10);
        tokenAmount = bound(tokenAmount, 1, 1e20);

        // deploy pool
        SharedPoolERC721ETH pool =
            factory.createSharedPoolERC721ETH(testERC721, uint128(delta), uint128(spotPrice), uint96(fee), address(0));

        // mint NFTs
        testERC721.setApprovalForAll(address(pool), true);
        uint256[] memory idList = _getIdList(1, numNfts);
        for (uint256 i; i < numNfts; i++) {
            testERC721.safeMint(address(this), idList[i]);
        }

        // deposit
        deal(address(this), tokenAmount);
        uint256 liquidity = pool.deposit{value: tokenAmount}(idList, 0, address(this), bytes(""));
        assertGt(liquidity, 0, "minted 0 liquidity");
        assertEq(pool.balanceOf(address(this)), liquidity, "didn't mint LP tokens");
    }

    function test_withdraw_all(uint256 delta, uint256 spotPrice, uint256 fee, uint256 numNfts) public {
        delta = bound(delta, 1, 1000);
        spotPrice = bound(spotPrice, 1e3, 1e20);
        fee = bound(fee, 0, 0.5e18);
        numNfts = bound(numNfts, 1, 10);
        uint256 tokenAmount = spotPrice * numNfts / delta;

        // deploy pool
        SharedPoolERC721ETH pool =
            factory.createSharedPoolERC721ETH(testERC721, uint128(delta), uint128(spotPrice), uint96(fee), address(0));

        // mint NFTs
        testERC721.setApprovalForAll(address(pool), true);
        uint256[] memory idList = _getIdList(1, numNfts);
        for (uint256 i; i < numNfts; i++) {
            testERC721.safeMint(address(this), idList[i]);
        }

        // deposit
        deal(address(this), tokenAmount);
        uint256 liquidity = pool.deposit{value: tokenAmount}(idList, 0, address(this), bytes(""));

        // withdraw
        (uint256 numNftOutput, uint256 tokenOutput) = pool.redeem(liquidity, idList, 0, 0, address(this));
        assertEq(numNftOutput, numNfts, "NFT output incorrect");
        assertEq(pool.balanceOf(address(this)), 0, "didn't burn LP tokens");
        assertEq(testERC721.balanceOf(address(this)), numNfts, "didn't withdraw NFTs");
    }

    /// -----------------------------------------------------------------------
    /// ERC721 compliance
    /// -----------------------------------------------------------------------

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /// -----------------------------------------------------------------------
    /// Utilities
    /// -----------------------------------------------------------------------

    function _getIdList(uint256 startId, uint256 amount) internal pure returns (uint256[] memory idList) {
        idList = new uint256[](amount);
        for (uint256 i = startId; i < startId + amount; i++) {
            idList[i - startId] = i;
        }
    }

    receive() external payable {}
}

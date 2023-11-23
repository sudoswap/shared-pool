// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import {RoyaltyEngine} from "lssvm2/RoyaltyEngine.sol";
import {XykCurve} from "lssvm2/bonding-curves/XykCurve.sol";
import {LSSVMPair, LSSVMPairFactory} from "lssvm2/LSSVMPairFactory.sol";
import {LSSVMPairETH} from "lssvm2/LSSVMPairETH.sol";
import {LSSVMPairERC20} from "lssvm2/LSSVMPairERC20.sol";
import {LSSVMPairERC1155} from "lssvm2/erc1155/LSSVMPairERC1155.sol";
import {LSSVMPairERC721ETH} from "lssvm2/erc721/LSSVMPairERC721ETH.sol";
import {LSSVMPairERC1155ETH} from "lssvm2/erc1155/LSSVMPairERC1155ETH.sol";
import {LSSVMPairERC721ERC20} from "lssvm2/erc721/LSSVMPairERC721ERC20.sol";
import {LSSVMPairERC1155ERC20} from "lssvm2/erc1155/LSSVMPairERC1155ERC20.sol";
import {Splitter} from "lssvm2/settings/Splitter.sol";

import {RoyaltyRegistry} from "manifoldxyz/RoyaltyRegistry.sol";

import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";
import {ERC1155TokenReceiver} from "solmate/tokens/ERC1155.sol";

import {SharedPool} from "../../src/SharedPool.sol";
import "../../src/SharedPoolFactory.sol";
import {TestERC20} from "../mocks/TestERC20.sol";
import {TestERC721} from "../mocks/TestERC721.sol";
import {TestERC1155} from "../mocks/TestERC1155.sol";
import {TestERC2981} from "../mocks/TestERC2981.sol";
import "../../src/settings/SplitSettingsFactory.sol";
import {Bus} from "../mocks/Bus.sol";
import {ILSSVMPairFactory} from "../../src/ILSSVMPairFactory.sol";

contract MultiDepositTest is Test, ERC721TokenReceiver, ERC1155TokenReceiver {
    using FixedPointMathLib for uint256;

    uint256 constant PROTOCOL_FEE = 0.005e18;
    address payable constant PROTOCOL_FEE_RECIPIENT = payable(address(0xfee));
    uint256 constant MINIMUM_LIQUIDITY = 1e3;
    uint256 constant BASE = 1e18;
    uint256 constant HALF_BASE = 5e17;
    address constant ROYALTY_RECEIVER = address(420);
    uint96 constant ROYALTY_BPS = 30;
    uint256 constant BPS_BASE = 10_000;

    SharedPoolFactory internal factory;
    LSSVMPairFactory internal pairFactory;
    SplitSettingsFactory internal settingsFactory;
    RoyaltyRegistry internal royaltyRegistry;
    RoyaltyEngine internal royaltyEngine;
    XykCurve internal bondingCurve;
    TestERC20 internal testERC20;
    TestERC721 internal testERC721;
    TestERC1155 internal testERC1155;
    ERC2981 internal testERC2981;

    function setUp() public {
        // deploy LSSVMPairFactory
        royaltyRegistry = new RoyaltyRegistry(address(0));
        royaltyRegistry.initialize(address(this));
        royaltyEngine = new RoyaltyEngine(address(royaltyRegistry));
        testERC2981 = ERC2981(new TestERC2981(ROYALTY_RECEIVER, ROYALTY_BPS));
        LSSVMPairERC721ETH erc721ETHTemplate = new LSSVMPairERC721ETH(
            royaltyEngine
        );
        LSSVMPairERC721ERC20 erc721ERC20Template = new LSSVMPairERC721ERC20(
            royaltyEngine
        );
        LSSVMPairERC1155ETH erc1155ETHTemplate = new LSSVMPairERC1155ETH(
            royaltyEngine
        );
        LSSVMPairERC1155ERC20 erc1155ERC20Template = new LSSVMPairERC1155ERC20(
            royaltyEngine
        );
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
            ILSSVMPairFactory(address(pairFactory)),
            bondingCurve
        );

        // deploy test tokens
        testERC20 = new TestERC20();
        testERC721 = new TestERC721();
        testERC1155 = new TestERC1155();

        settingsFactory = new SplitSettingsFactory(
            new SplitSettings(new Splitter(), pairFactory)
        );
    }

    address[] callers = [
        address(1),
        address(2),
        address(3),
        address(4),
        address(5)
    ];
    
    event Foo(uint256[] a);

    function test_multiDepositWithdraw() public {
        SharedPoolERC721ETH pool = factory.createSharedPoolERC721ETH(
            testERC721,
            1,
            1 ether,
            0,
            address(0),
            address(0),
            "",
            ""
        );

        uint256[] memory idsToBuy = new uint256[](4);

        for (uint i; i < callers.length; ++i) {
            testERC721.safeMint(callers[i], i);
            vm.deal(callers[i], 10 ether);
            vm.startPrank(callers[i]);
            testERC721.setApprovalForAll(address(pool), true);
            uint256[] memory id = new uint256[](1);
            id[0] = i;
            pool.deposit{value: 1 ether}(
                id,
                1,
                1 ether,
                callers[i],
                1000000000,
                ""
            );
            vm.stopPrank();

            if (i != 4) {
              idsToBuy[i] = i;
            }
        }

        // Swap for 5 of the NFTs
        (, , , uint256 cost, , ) = pool.pair().getBuyNFTQuote(1, 4);
        pool.pair().swapTokenForSpecificNFTs{value: cost}(
            idsToBuy,
            cost,
            address(this),
            false,
            address(0)
        );

        // Attempt to withdraw for the first 4 callers
        uint256[] memory idToRedeem = new uint256[](1);
        uint256 prevTokens = 0;
        idToRedeem[0] = 4;
        for (uint i; i < callers.length - 1; ++i) {
            vm.startPrank(callers[i]);
            (uint256 nft, uint256 tokens) = pool.redeem(pool.balanceOf(callers[i]), idToRedeem, 0, 0, callers[i], 10000000000);
            if (prevTokens != 0) {
              assertEq(tokens, prevTokens);
            }
            else {
              prevTokens = tokens;
            }
        }
    }
}

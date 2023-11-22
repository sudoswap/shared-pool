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

abstract contract SharedPoolTest is Test, ERC721TokenReceiver, ERC1155TokenReceiver {
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
            ILSSVMPairFactory(address(pairFactory)),
            bondingCurve
        );

        // deploy test tokens
        testERC20 = new TestERC20();
        testERC721 = new TestERC721();
        testERC1155 = new TestERC1155();

        settingsFactory = new SplitSettingsFactory(new SplitSettings(new Splitter(), pairFactory));
    }

    function test_createSharedPoolERC721ETH(
        uint256 delta,
        uint256 spotPrice,
        uint256 fee,
        string memory name,
        string memory symbol
    ) public {
        vm.assume(bytes(name).length <= 31 && bytes(symbol).length <= 31);
        delta = bound(delta, 0, 1000);
        spotPrice = bound(spotPrice, 0, 1e20);
        fee = bound(fee, 0, 1e17);

        SharedPoolERC721ETH pool = factory.createSharedPoolERC721ETH(
            testERC721, uint128(delta), uint128(spotPrice), uint96(fee), address(0), address(0), name, symbol
        );
        assertEq(pool.pair().delta(), delta);
        assertEq(pool.pair().spotPrice(), spotPrice);
        assertEq(pool.pair().fee(), fee);
        assertEq(pool.initialDelta(), delta);
        assertEq(pool.initialSpotPrice(), spotPrice);
        assertEq(pool.nft(), address(testERC721));
        assertEq(address(pool.pairFactory()), address(pairFactory));
        assertEq(address(pool.token()), address(0));
        assertEq(pool.name(), name);
        assertEq(pool.symbol(), symbol);
    }

    function test_createSharedPoolERC721ERC20(
        uint256 delta,
        uint256 spotPrice,
        uint256 fee,
        string memory name,
        string memory symbol
    ) public {
        vm.assume(bytes(name).length <= 31 && bytes(symbol).length <= 31);
        delta = bound(delta, 0, 1000);
        spotPrice = bound(spotPrice, 0, 1e20);
        fee = bound(fee, 0, 1e17);

        SharedPoolERC721ERC20 pool = factory.createSharedPoolERC721ERC20(
            testERC20, testERC721, uint128(delta), uint128(spotPrice), uint96(fee), address(0), address(0), name, symbol
        );
        assertEq(pool.pair().delta(), delta);
        assertEq(pool.pair().spotPrice(), spotPrice);
        assertEq(pool.pair().fee(), fee);
        assertEq(pool.initialDelta(), delta);
        assertEq(pool.initialSpotPrice(), spotPrice);
        assertEq(pool.nft(), address(testERC721));
        assertEq(address(pool.pairFactory()), address(pairFactory));
        assertEq(address(LSSVMPairERC20(address(pool.pair())).token()), address(testERC20));
        assertEq(address(pool.token()), address(testERC20));
        assertEq(pool.name(), name);
        assertEq(pool.symbol(), symbol);
    }

    function test_createSharedPoolERC1155ETH(
        uint256 delta,
        uint256 spotPrice,
        uint256 fee,
        uint256 nftId,
        string memory name,
        string memory symbol
    ) public {
        vm.assume(bytes(name).length <= 31 && bytes(symbol).length <= 31);
        delta = bound(delta, 0, 1000);
        spotPrice = bound(spotPrice, 0, 1e20);
        fee = bound(fee, 0, 1e17);

        SharedPoolERC1155ETH pool = factory.createSharedPoolERC1155ETH(
            testERC1155, uint128(delta), uint128(spotPrice), uint96(fee), nftId, address(0), name, symbol
        );
        assertEq(pool.pair().delta(), delta);
        assertEq(pool.pair().spotPrice(), spotPrice);
        assertEq(pool.pair().fee(), fee);
        assertEq(pool.initialDelta(), delta);
        assertEq(pool.initialSpotPrice(), spotPrice);
        assertEq(pool.nft(), address(testERC1155));
        assertEq(address(pool.pairFactory()), address(pairFactory));
        assertEq(address(pool.token()), address(0));
        assertEq(LSSVMPairERC1155(address(pool.pair())).nftId(), nftId);
        assertEq(pool.nftId(), nftId);
        assertEq(pool.name(), name);
        assertEq(pool.symbol(), symbol);
    }

    function test_createSharedPoolERC1155ERC20(
        uint256 delta,
        uint256 spotPrice,
        uint256 fee,
        uint256 nftId,
        string memory name,
        string memory symbol
    ) public {
        vm.assume(bytes(name).length <= 31 && bytes(symbol).length <= 31);
        delta = bound(delta, 0, 1000);
        spotPrice = bound(spotPrice, 0, 1e20);
        fee = bound(fee, 0, 1e17);

        SharedPoolERC1155ERC20 pool = factory.createSharedPoolERC1155ERC20(
            testERC20, testERC1155, uint128(delta), uint128(spotPrice), uint96(fee), nftId, address(0), name, symbol
        );
        assertEq(pool.pair().delta(), delta);
        assertEq(pool.pair().spotPrice(), spotPrice);
        assertEq(pool.pair().fee(), fee);
        assertEq(pool.initialDelta(), delta);
        assertEq(pool.initialSpotPrice(), spotPrice);
        assertEq(pool.nft(), address(testERC1155));
        assertEq(address(pool.pairFactory()), address(pairFactory));
        assertEq(address(LSSVMPairERC20(address(pool.pair())).token()), address(testERC20));
        assertEq(address(pool.token()), address(testERC20));
        assertEq(LSSVMPairERC1155(address(pool.pair())).nftId(), nftId);
        assertEq(pool.nftId(), nftId);
        assertEq(pool.name(), name);
        assertEq(pool.symbol(), symbol);
    }

    function test_deposit(uint256 delta, uint256 spotPrice, uint256 fee, uint256 numNfts) public {
        delta = bound(delta, 1, 1000);
        spotPrice = bound(spotPrice, 1e3, 1e20);
        fee = bound(fee, 0, 1e17);
        numNfts = bound(numNfts, 1, 10);
        uint256 tokenAmount = spotPrice * numNfts / delta;

        // deploy pool
        SharedPool pool = _createSharedPool(delta, spotPrice, fee, address(0), address(0));

        // mint NFTs
        _approveNFT(address(pool));
        _mintNFT(address(this), numNfts, 1);

        // deposit
        _deal(address(this), tokenAmount);
        (uint256 amountNft, uint256 amountToken, uint256 liquidity) = _deposit(pool, numNfts, tokenAmount);
        uint256 expectedLiquidity = (amountNft * BASE * amountToken).sqrt() - MINIMUM_LIQUIDITY;
        assertEq(liquidity, expectedLiquidity, "minted 0 liquidity");
        assertEq(pool.balanceOf(address(this)), liquidity, "didn't mint LP tokens");
        assertEq(numNfts - _nftBalanceOf(address(this)), amountNft, "deposited NFT amount incorrect");
        assertEq(tokenAmount - _tokenBalanceOf(address(this)), amountToken, "deposited token amount incorrect");
    }

    function _deal(address to, uint256 amount) internal virtual;
    function _approveNFT(address to) internal virtual;
    function _mintNFT(address to, uint256 amount, uint256 start) internal virtual;
    function _nftAddress() internal view virtual returns (address);
    function _deposit(SharedPool pool, uint256 numNfts, uint256 tokenAmount)
        internal
        virtual
        returns (uint256 amountNft, uint256 amountToken, uint256 liquidity);
    function _redeem(SharedPool pool, uint256 burnAmount, uint256 numNfts)
        internal
        virtual
        returns (uint256 numNftOutput, uint256 tokenOutput);
    function _nftBalanceOf(address user) internal view virtual returns (uint256);
    function _tokenBalanceOf(address user) internal view virtual returns (uint256);
    function _createSharedPool(uint256 delta, uint256 spotPrice, uint256 fee, address propertyChecker, address settings)
        internal
        virtual
        returns (SharedPool);
    function _withdrawAllTokensFromSplitter(Splitter s) internal virtual;
    function _buyNFTsFromPool(SharedPool pool, uint256 numNfts, uint256 inputAmount) internal virtual;

    function test_withdraw_all(uint256 delta, uint256 spotPrice, uint256 fee, uint256 numNfts) public {
        delta = bound(delta, 1, 1000);
        spotPrice = bound(spotPrice, 1e3, 1e20);
        fee = bound(fee, 0, 0.5e18);
        numNfts = bound(numNfts, 1, 10);
        uint256 tokenAmount = spotPrice * numNfts / delta;

        // deploy pool
        SharedPool pool = _createSharedPool(delta, spotPrice, fee, address(0), address(0));

        // mint NFTs
        _approveNFT(address(pool));
        _mintNFT(address(this), numNfts, 1);

        // deposit
        _deal(address(this), tokenAmount);
        (,, uint256 liquidity) = _deposit(pool, numNfts, tokenAmount);

        // withdraw
        (uint256 numNftOutput, uint256 tokenOutput) = _redeem(pool, liquidity, numNfts);
        assertEq(numNftOutput, numNfts, "NFT output incorrect");
        assertEq(pool.balanceOf(address(this)), 0, "didn't burn LP tokens");
        assertEq(_nftBalanceOf(address(this)), numNfts, "didn't withdraw NFTs");
        assertLeDecimal(tokenOutput, tokenAmount, 18, "token output incorrect");
    }

    function test_withdraw_partial(
        uint256 delta,
        uint256 spotPrice,
        uint256 fee,
        uint256 numNfts,
        uint256 liquidityToWithdraw
    ) public {
        delta = bound(delta, 1, 1000);
        spotPrice = bound(spotPrice, 1e3, 1e20);
        fee = bound(fee, 0, 0.5e18);
        numNfts = bound(numNfts, 1, 10);
        uint256 tokenAmount = spotPrice * numNfts / delta;

        // deploy pool
        SharedPool pool = _createSharedPool(delta, spotPrice, fee, address(0), address(0));

        // mint NFTs
        _approveNFT(address(pool));
        _mintNFT(address(this), numNfts, 1);

        // deposit
        _deal(address(this), tokenAmount);
        (,, uint256 liquidity) = _deposit(pool, numNfts, tokenAmount);

        // withdraw
        liquidityToWithdraw = bound(liquidityToWithdraw, 1e3, liquidity);
        uint256 poolTotalSupply = pool.totalSupply();
        uint256 decimalNftAmount = liquidityToWithdraw.mulDivDown(numNfts * BASE, poolTotalSupply);
        uint256 rawTokenOutput = liquidityToWithdraw.mulDivDown(pool.getTokenReserve(), poolTotalSupply);
        uint256 fractionalNftAmount = decimalNftAmount % BASE;
        uint256 fractionalTokenAmount =
            decimalNftAmount == 0 ? 0 : fractionalNftAmount.mulDivDown(rawTokenOutput, decimalNftAmount);
        uint256 inputValue;
        {
            uint256 virtualNftReserve = pool.initialDelta() + pool.getNftReserve();
            uint256 virtualTokenReserve = pool.initialSpotPrice() + pool.getTokenReserve();
            uint256 fractionalBuyNumItems = BASE - fractionalNftAmount;
            uint256 inputValueWithoutFee = (
                fractionalBuyNumItems * (virtualTokenReserve - rawTokenOutput + fractionalTokenAmount)
            ) / ((virtualNftReserve * BASE - decimalNftAmount + fractionalNftAmount) - fractionalBuyNumItems);
            (,, uint256 royaltyAmount) = pool.pair().calculateRoyaltiesView(0, inputValueWithoutFee);
            inputValue = inputValueWithoutFee.mulWadUp(
                BASE + pool.pairFactory().protocolFeeMultiplier() + pool.pair().fee()
            ) + royaltyAmount;
        }

        // burn liquidity tokens to withdraw assets
        uint256 beforeTokenBalance = _tokenBalanceOf(address(this));
        (uint256 numNftOutput, uint256 tokenOutput) = _redeem(pool, liquidityToWithdraw, numNfts);

        // expected NFT output depends on whether rounding up or down happens
        uint256 expectedNumNftOutput = fractionalNftAmount >= HALF_BASE
            ? (
                rawTokenOutput >= inputValue
                    ? numNfts.mulDivUp(liquidityToWithdraw, poolTotalSupply)
                    : numNfts.mulDivDown(liquidityToWithdraw, poolTotalSupply)
            )
            : numNfts.mulDivDown(liquidityToWithdraw, poolTotalSupply);
        assertEq(numNftOutput, expectedNumNftOutput, "NFT output incorrect");
        assertEq(pool.balanceOf(address(this)), liquidity - liquidityToWithdraw, "didn't burn LP tokens");
        assertEq(_nftBalanceOf(address(this)), numNftOutput, "didn't withdraw NFTs");

        // verify token output
        assertEq(_tokenBalanceOf(address(this)) - beforeTokenBalance, tokenOutput, "returned tokenOutput incorrect");
    }

    function test_depositThenWithdraw_noProfit(uint256 delta, uint256 spotPrice, uint256 fee, uint256 numNfts) public {
        delta = bound(delta, 1, 1000);
        spotPrice = bound(spotPrice, 1e3, 1e20);
        fee = bound(fee, 0, 1e17);
        numNfts = bound(numNfts, 1, 10);
        uint256 tokenAmount = spotPrice * numNfts / delta;

        // deploy pool
        SharedPool pool = _createSharedPool(delta, spotPrice, fee, address(0), address(0));

        // mint NFTs
        _approveNFT(address(pool));
        _mintNFT(address(this), numNfts, 1);

        // deposit
        _deal(address(this), tokenAmount);
        (uint256 amountNft, uint256 amountToken, uint256 liquidity) = _deposit(pool, numNfts, tokenAmount);

        // withdraw
        (uint256 numNftOutput, uint256 tokenOutput) = _redeem(pool, liquidity, numNfts);

        // verify no profit
        assertLe(numNftOutput, amountNft, "withdrew more NFTs");
        assertLe(tokenOutput, amountToken, "withdrew more tokens");
    }

    function test_sync_statusQuo(uint256 delta, uint256 spotPrice, uint256 fee, uint256 numNfts) public {
        delta = bound(delta, 1, 1000);
        spotPrice = bound(spotPrice, 1e3, 1e20);
        fee = bound(fee, 0, 0.5e18);
        numNfts = bound(numNfts, 1, 10);
        uint256 tokenAmount = spotPrice * numNfts / delta;

        // deploy pool
        SharedPool pool = _createSharedPool(delta, spotPrice, fee, address(0), address(0));

        // mint NFTs
        _approveNFT(address(pool));
        _mintNFT(address(this), numNfts, 1);

        // deposit
        _deal(address(this), tokenAmount);
        _deposit(pool, numNfts, tokenAmount);

        uint256 beforeDelta = pool.pair().delta();
        uint256 beforeSpotPrice = pool.pair().spotPrice();
        uint256 beforeNftReserve = pool.getNftReserve();
        uint256 beforeTokenReserve = pool.getTokenReserve();

        // sync
        pool.sync();

        // verify pool params
        assertEq(pool.pair().delta(), beforeDelta);
        assertEq(pool.pair().spotPrice(), beforeSpotPrice);
        assertEq(pool.getNftReserve(), beforeNftReserve);
        assertEq(pool.getTokenReserve(), beforeTokenReserve);
    }

    function test_sync_update(
        uint256 delta,
        uint256 spotPrice,
        uint256 fee,
        uint256 numNfts,
        uint256 tokenToAdd,
        uint256 nftToAdd
    ) public {
        delta = bound(delta, 1, 1000);
        spotPrice = bound(spotPrice, 1e3, 1e20);
        fee = bound(fee, 0, 0.5e18);
        numNfts = bound(numNfts, 1, 10);
        tokenToAdd = bound(tokenToAdd, 1, 1e30);
        nftToAdd = bound(nftToAdd, 1, 10);
        uint256 tokenAmount = spotPrice * numNfts / delta;

        // deploy pool
        SharedPool pool = _createSharedPool(delta, spotPrice, fee, address(0), address(0));

        // mint NFTs
        _approveNFT(address(pool));
        _mintNFT(address(this), numNfts, 1);

        // deposit
        _deal(address(this), tokenAmount);
        _deposit(pool, numNfts, tokenAmount);

        LSSVMPair pair = pool.pair();
        uint256 beforeDelta = pair.delta();
        uint256 beforeSpotPrice = pair.spotPrice();
        uint256 beforeNftReserve = pool.getNftReserve();
        uint256 beforeTokenReserve = pool.getTokenReserve();

        // add tokens and NFTs to the pair
        _deal(address(pair), _tokenBalanceOf(address(pair)) + tokenToAdd);
        _mintNFT(address(pair), nftToAdd, 1 + numNfts);

        // sync
        pool.sync();

        // verify pool params
        assertEq(pair.delta(), beforeDelta + nftToAdd);
        assertEq(pair.spotPrice(), beforeSpotPrice + tokenToAdd);
        assertEq(pool.getNftReserve(), beforeNftReserve + nftToAdd);
        assertEq(pool.getTokenReserve(), beforeTokenReserve + tokenToAdd);
    }

    function test_settings_swapSendsRoyaltyAndFeeCorrectly(
        uint256 delta,
        uint256 spotPrice,
        uint256 fee,
        uint256 feeSplitBps,
        uint256 royaltyBps
    ) external {
        delta = bound(delta, 1, 1000);
        spotPrice = bound(spotPrice, 1e3, 1e20);
        fee = bound(fee, 0, 0.2e18);
        feeSplitBps = bound(feeSplitBps, 1, BPS_BASE);
        royaltyBps = bound(royaltyBps, 1, BPS_BASE / 10);
        address payable feeRecipient = payable(makeAddr("feeRecipient"));
        address owner = makeAddr("owner");
        Bus(_nftAddress()).setOwner(owner);
        uint256 numNfts = 10;
        uint256 tokenAmount = spotPrice * numNfts / delta;

        // enable royalties
        royaltyRegistry.setRoyaltyLookupAddress(_nftAddress(), address(testERC2981));

        // create settings
        SplitSettings settings = settingsFactory.createSettings(feeRecipient, uint64(feeSplitBps), uint64(royaltyBps));

        // enable settings
        vm.prank(owner);
        pairFactory.toggleSettingsForCollection(address(settings), _nftAddress(), true);

        // deploy pool
        SharedPool pool = _createSharedPool(delta, spotPrice, fee, address(0), address(settings));

        // mint NFTs
        _approveNFT(address(pool));
        _mintNFT(address(this), numNfts, 1);

        // deposit
        _deal(address(this), tokenAmount);
        _deposit(pool, numNfts, tokenAmount);

        // buy NFTs from the pool
        uint256 buyNumNfts = 2;
        (,,,, uint256 tradeFee,) =
            bondingCurve.getBuyInfo(pool.pair().spotPrice(), pool.pair().delta(), buyNumNfts, fee, PROTOCOL_FEE);
        (,,, uint256 inputAmount, uint256 protocolFee, uint256 royaltyAmount) =
            pool.pair().getBuyNFTQuote(1, buyNumNfts);
        uint256 beforeRoyaltyReceiverBalance = _tokenBalanceOf(ROYALTY_RECEIVER);
        uint256 beforeFeeRecipientBalance = _tokenBalanceOf(feeRecipient);
        _deal(address(this), _tokenBalanceOf(address(this)) + inputAmount);
        _buyNFTsFromPool(pool, buyNumNfts, inputAmount);

        // withdraw split trade fee
        _withdrawAllTokensFromSplitter(Splitter(payable(pool.pair().getFeeRecipient())));

        // check royalty and trade fee split
        uint256 inputAmountMinusFees = inputAmount - royaltyAmount - tradeFee - protocolFee;
        assertEq(royaltyAmount, inputAmountMinusFees * royaltyBps / BPS_BASE, "royalty incorrect");
        assertEq(
            _tokenBalanceOf(feeRecipient) - beforeFeeRecipientBalance,
            2 * tradeFee * feeSplitBps / BPS_BASE,
            "split trade fee incorrect"
        );
        assertEq(
            _tokenBalanceOf(ROYALTY_RECEIVER) - beforeRoyaltyReceiverBalance,
            royaltyAmount,
            "received royalty amount incorrect"
        );
    }

    function test_settings_withdraw_all(
        uint256 delta,
        uint256 spotPrice,
        uint256 fee,
        uint256 numNfts,
        uint256 feeSplitBps,
        uint256 royaltyBps
    ) public {
        delta = bound(delta, 1, 1000);
        spotPrice = bound(spotPrice, 1e3, 1e20);
        fee = bound(fee, 0, 0.2e18);
        numNfts = bound(numNfts, 1, 10);
        uint256 tokenAmount = spotPrice * numNfts / delta;
        feeSplitBps = bound(feeSplitBps, 1, BPS_BASE);
        royaltyBps = bound(royaltyBps, 1, BPS_BASE / 10);
        address payable feeRecipient = payable(makeAddr("feeRecipient"));
        address owner = makeAddr("owner");
        Bus(_nftAddress()).setOwner(owner);

        // enable royalties
        royaltyRegistry.setRoyaltyLookupAddress(_nftAddress(), address(testERC2981));

        // create settings
        SplitSettings settings = settingsFactory.createSettings(feeRecipient, uint64(feeSplitBps), uint64(royaltyBps));

        // enable settings
        vm.prank(owner);
        pairFactory.toggleSettingsForCollection(address(settings), _nftAddress(), true);

        // deploy pool
        SharedPool pool = _createSharedPool(delta, spotPrice, fee, address(0), address(settings));

        // mint NFTs
        _approveNFT(address(pool));
        _mintNFT(address(this), numNfts, 1);

        // deposit
        _deal(address(this), tokenAmount);
        (,, uint256 liquidity) = _deposit(pool, numNfts, tokenAmount);

        // withdraw
        (uint256 numNftOutput, uint256 tokenOutput) = _redeem(pool, liquidity, numNfts);
        assertEq(numNftOutput, numNfts, "NFT output incorrect");
        assertEq(pool.balanceOf(address(this)), 0, "didn't burn LP tokens");
        assertEq(_nftBalanceOf(address(this)), numNfts, "didn't withdraw NFTs");
        assertLeDecimal(tokenOutput, tokenAmount, 18, "token output incorrect");
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

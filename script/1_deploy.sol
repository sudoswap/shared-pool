// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SharedPoolERC721ETH} from "../src/SharedPoolERC721ETH.sol";
import {SharedPoolERC721ERC20} from "../src/SharedPoolERC721ERC20.sol";
import {SharedPoolERC1155ETH} from "../src/SharedPoolERC1155ETH.sol";
import {SharedPoolERC1155ERC20} from "../src/SharedPoolERC1155ERC20.sol";
import {SharedPoolFactory} from "../src/SharedPoolFactory.sol";
import {LSSVMPair, ICurve} from "lssvm2/LSSVMPairFactory.sol";
import {ILSSVMPairFactory} from "../src/ILSSVMPairFactory.sol";

import "forge-std/Script.sol";

contract Deploy is Script {

    function run()
        external
        returns (SharedPoolFactory factory)
    {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
        vm.startBroadcast(deployerPrivateKey);

        // SharedPoolERC721ETH s1 = new SharedPoolERC721ETH();
        // SharedPoolERC721ERC20 s2 = new SharedPoolERC721ERC20();
        // SharedPoolERC1155ETH s3 = new SharedPoolERC1155ETH();
        // SharedPoolERC1155ERC20 s4 = new SharedPoolERC1155ERC20();

        address pairFactory = vm.envAddress("PAIR_FACTORY");
        address xykCurve = vm.envAddress("XYK_CURVE");

        factory = new SharedPoolFactory(
            SharedPoolERC721ETH(payable(0xbe585139aB24aE96794f65a33205EE931fbb6A42)),
            SharedPoolERC721ERC20(payable(0x0db7f5f66fFFCA63Ef92D7A57Ad84bbdAf646b70)),
            SharedPoolERC1155ETH(payable(0x05aedb5328F2c8e1C04077687817992287C655ab)),
            SharedPoolERC1155ERC20(payable(0x73bEE8a0408e40eE2B713623342D1D57800205cD)),
            ILSSVMPairFactory(payable(pairFactory)),
            ICurve(xykCurve)
        );

        vm.stopBroadcast();
    }
}
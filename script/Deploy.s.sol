// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.13;

import {CREATE3Script} from "./base/CREATE3Script.sol";

import {Splitter} from "lssvm2/settings/Splitter.sol";

import "../src/SharedPoolFactory.sol";
import "../src/settings/SplitSettingsFactory.sol";

contract DeployScript is CREATE3Script {
    constructor() CREATE3Script(vm.envString("VERSION")) {}

    function run() external returns (SharedPoolFactory sharedPoolFactory, SplitSettingsFactory splitSettingsFactory) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));

        LSSVMPairFactory pairFactory = LSSVMPairFactory(payable(vm.envAddress("PAIR_FACTORY")));
        address xykCurve = vm.envAddress("XYK_CURVE");
        Splitter splitterImpl = Splitter(payable(vm.envAddress("SPLITTER_IMPL")));

        vm.startBroadcast(deployerPrivateKey);

        sharedPoolFactory = SharedPoolFactory(
            create3.deploy(
                getCreate3ContractSalt("SharedPoolFactory"),
                bytes.concat(
                    type(SharedPoolFactory).creationCode,
                    abi.encode(
                        new SharedPoolERC721ETH(),
                        new SharedPoolERC721ERC20(),
                        new SharedPoolERC1155ETH(),
                        new SharedPoolERC1155ERC20(),
                        pairFactory,
                        xykCurve
                    )
                )
            )
        );

        splitSettingsFactory = SplitSettingsFactory(
            create3.deploy(
                getCreate3ContractSalt("SplitSettingsFactory"),
                bytes.concat(
                    type(SplitSettingsFactory).creationCode,
                    abi.encode(new SplitSettings(splitterImpl, LSSVMPairFactory(pairFactory)))
                )
            )
        );

        vm.stopBroadcast();
    }
}

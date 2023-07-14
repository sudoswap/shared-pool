// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ClonesWithImmutableArgs} from "clones-with-immutable-args/ClonesWithImmutableArgs.sol";
import {SplitSettings} from "./SplitSettings.sol";

contract SplitSettingsFactory {
    using ClonesWithImmutableArgs for address;

    event NewSettings(address indexed settingsAddress);

    error SplitSettingsFactory__RoyaltyTooHigh();
    error SplitSettingsFactory__TradeFeeTooHigh();

    uint256 constant BASE = 10_000;

    SplitSettings immutable splitSettingsImplementation;

    constructor(SplitSettings _splitSettingsImplementation) {
        splitSettingsImplementation = _splitSettingsImplementation;
    }

    function createSettings(address payable settingsFeeRecipient, uint64 feeSplitBps, uint64 royaltyBps)
        public
        returns (SplitSettings settings)
    {
        if (royaltyBps > (BASE / 10)) revert SplitSettingsFactory__RoyaltyTooHigh();
        if (feeSplitBps > BASE) revert SplitSettingsFactory__TradeFeeTooHigh();

        bytes memory data = abi.encodePacked(feeSplitBps, royaltyBps);
        settings = SplitSettings(address(splitSettingsImplementation).clone(data));
        settings.initialize(msg.sender, settingsFeeRecipient);
        emit NewSettings(address(settings));
    }
}

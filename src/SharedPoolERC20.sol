// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import "./SharedPool.sol";

abstract contract SharedPoolERC20 is SharedPool {
    using SafeTransferLib for ERC20;

    function token() public pure override returns (ERC20) {
        uint256 tokenArgOffset;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // returns the last 20 bytes of the immutable args blob
            tokenArgOffset := sub(shr(240, calldataload(sub(calldatasize(), 2))), 20)
        }
        return ERC20(_getArgAddress(tokenArgOffset));
    }

    function _getTokenInput(bytes calldata extraData) internal pure override returns (uint256 tokenInput) {
        return abi.decode(extraData, (uint256));
    }

    function _pullTokensFromSender(ERC20 _token, address to, uint256 amount) internal override {
        if (amount == 0) return;
        _token.safeTransferFrom(msg.sender, to, amount);
    }

    function _pushTokens(ERC20 _token, address to, uint256 amount) internal override {
        if (amount == 0) return;
        _token.safeTransfer(to, amount);
    }

    function _withdrawTokensFromPair(ERC20 _token, LSSVMPair _pair, uint256 amount, address recipient)
        internal
        override
    {
        if (amount == 0) return;
        address payable settingsAddress = settings();
        if (settingsAddress != address(0)) {
            SplitSettings(settingsAddress).withdrawERC20(address(_pair), _token, amount, recipient);
        } else {
            _pair.withdrawERC20(_token, amount);
            _token.safeTransfer(recipient, amount);
        }
    }

    function _getTokenReserve(ERC20 _token, LSSVMPair _pair) internal view override returns (uint256 tokenReserve) {
        return _token.balanceOf(address(_pair));
    }
}

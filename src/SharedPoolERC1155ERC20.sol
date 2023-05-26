// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {SharedPoolERC1155} from "./SharedPoolERC1155.sol";
import {SharedPoolERC20} from "./SharedPoolERC20.sol";

contract SharedPoolERC1155ERC20 is SharedPoolERC1155, SharedPoolERC20 {}

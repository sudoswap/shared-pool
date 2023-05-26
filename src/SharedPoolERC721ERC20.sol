// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

import {SharedPoolERC721} from "./SharedPoolERC721.sol";
import {SharedPoolERC20} from "./SharedPoolERC20.sol";

contract SharedPoolERC721ERC20 is SharedPoolERC721, SharedPoolERC20 {}

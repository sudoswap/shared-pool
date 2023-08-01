// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ERC1155} from "solmate/tokens/ERC1155.sol";
import "./Bus.sol";

contract TestERC1155 is ERC1155, Bus {
    function uri(uint256) public view virtual override returns (string memory) {
        return "";
    }

    function mint(address to, uint256 id, uint256 amount) public {
        _mint(to, id, amount, "");
    }
}

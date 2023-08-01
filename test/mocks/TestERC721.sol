// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ERC721} from "solmate/tokens/ERC721.sol";
import "./Bus.sol";

contract TestERC721 is ERC721, Bus {
    constructor() ERC721("Test721", "T721") {}

    function tokenURI(uint256) public pure override returns (string memory) {
        return "";
    }

    function safeMint(address to, uint256 id) public {
        _safeMint(to, id);
    }
}

// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

abstract contract Bus {
    address public owner;

    function setOwner(address newOwner) external {
        owner = newOwner;
    }
}

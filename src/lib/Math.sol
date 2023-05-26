// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.4;

function min(uint256 x, uint256 y) pure returns (uint256) {
    return x < y ? x : y;
}
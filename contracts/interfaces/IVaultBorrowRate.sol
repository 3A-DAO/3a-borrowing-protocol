// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IVaultBorrowRate {
    function getBorrowRate(address _vaultAddress) external view returns (uint256);
}
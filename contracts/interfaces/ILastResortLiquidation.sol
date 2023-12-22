// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface ILastResortLiquidation {
    function addCollateral(address _collateral, uint256 _amount) external;
    function addBadDebt(uint256 _amount) external;
}

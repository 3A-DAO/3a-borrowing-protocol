// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface ICToken {
    function exchangeRateStored() external view returns (uint256);

    function decimals() external view returns (uint8);
}

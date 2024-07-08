// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IExternalPriceFeed {
    function token() external view returns (address);

    function price() external view returns (uint256);

    function pricePoint() external view returns (uint256);

    function setPrice(uint256 _price) external;
}

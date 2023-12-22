// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IPriceFeed {
  function token() external view returns (address);

  function price() external view returns (uint256);

  function pricePoint() external view returns (uint256);

  function emitPriceSignal() external;

  event PriceUpdate(address token, uint256 price, uint256 average);
}

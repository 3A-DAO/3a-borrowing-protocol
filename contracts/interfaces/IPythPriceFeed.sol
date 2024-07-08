// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IOrchestratorPriceFeed {
    function token() external view returns (address);

    function price(address token) external view returns (uint256);

    function prices(address[] memory tokens) external view returns (uint256[] memory);

    function pricePoint(address token) external view returns (uint256);
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IPricesOrchestrator {
    function token() external view returns (address);

    function price(address token) external view returns (uint256);

    function pricePoint() external view returns (uint256);

    function emitPriceSignal() external;

    function decimals() external pure returns (uint8);
}

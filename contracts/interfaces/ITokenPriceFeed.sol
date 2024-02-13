// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./IOwnable.sol";

interface ITokenPriceFeed is IOwnable {
    struct TokenInfo {
        address priceFeed;
        uint256 mcr; // Minimum Collateralization Ratio
        uint256 mlr; // Minimum Liquidation Ratio
        uint256 borrowRate;
        uint256 decimals;
    }

    function tokenPriceFeed(address) external view returns (address);

    function tokenPrice(address _token) external view returns (uint256);

    function mcr(address _token) external view returns (uint256);

    function decimals(address _token) external view returns (uint256);

    function mlr(address _token) external view returns (uint256);

    function borrowRate(address _token) external view returns (uint256);

    function setTokenPriceFeed(address _token, address _priceFeed, uint256 _mcr, uint256 _mlr, uint256 _borrowRate) external;

    event NewTokenPriceFeed(
        address _token,
        address _priceFeed,
        string _name,
        string _symbol,
        uint256 _mcr,
        uint256 _mlr,
        uint256 _borrowRate,
        uint256 _decimals
    );
}

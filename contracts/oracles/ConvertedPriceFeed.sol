// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./ChainlinkPriceFeed.sol";

/**
 * @title ConvertedPriceFeed
 * @dev Manages a price feed by converting between two different price feeds and emitting price signals.
 */
contract ConvertedPriceFeed is IPriceFeed, Constants {
    IPriceFeed public immutable priceFeed;
    IPriceFeed public immutable conversionPriceFeed;
    address public immutable override token;

    /**
     * @dev Constructor sets up the price feeds and associated tokens for conversion.
     * @param _priceFeed The primary price feed address.
     * @param _conversionPriceFeed The conversion price feed address.
     * @param _token The token address associated with the price feed.
     */
    constructor(address _priceFeed, address _conversionPriceFeed, address _token) {
        require(_priceFeed != address(0x0), "e2637b _priceFeed must not be address 0x0");
        require(_conversionPriceFeed != address(0x0), "e2637b _conversionPriceFeed must not be address 0x0");
        priceFeed = IPriceFeed(_priceFeed);
        conversionPriceFeed = IPriceFeed(_conversionPriceFeed);
        token = _token;
    }

    /**
     * @dev Retrieves the converted price by multiplying the primary price with the conversion price.
     */
    function price() public view override returns (uint256) {
        return (priceFeed.price() * DECIMAL_PRECISION) / conversionPriceFeed.price();
    }

    /**
     * @dev Retrieves the current price point by calling the 'price()' function.
     */
    function pricePoint() public view override returns (uint256) {
        return price();
    }

    /**
     * @dev Emits a price signal using the converted price.
     */
    function emitPriceSignal() public {
        emit PriceUpdate(token, price(), price());
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../../interfaces/IPriceFeed.sol";
import "../../interfaces/IPricesOrchestrator.sol";

/**
 * @title ConvertedPriceFeed
 * @dev Manages a price feed by converting between two different price feeds and emitting price signals.
 * @author 3A DAO - Cristian (0xCR6)
 */
contract ConvertedPriceFeed {
    uint256 public immutable DECIMAL_PRECISION;
    IPriceFeed public immutable priceFeed;
    IPriceFeed public immutable conversionPriceFeed;
    address public immutable token;
    string public constant version = "2.0.0";

    event PriceUpdate(address token, uint256 price, uint256 average);

    /**
     * @dev Constructor sets up the price feeds and associated tokens for conversion.
     * @param _priceFeed The primary price feed address.
     * @param _conversionPriceFeed The conversion price feed address.
     * @param _token The token address associated with the price feed.
     */
    constructor(address _priceFeed, address _conversionPriceFeed, address _token) {
        require(_priceFeed != address(0x0), "invalid-address");
        require(_conversionPriceFeed != address(0x0), "invalid-address");
        priceFeed = IPriceFeed(_priceFeed);
        conversionPriceFeed = IPriceFeed(_conversionPriceFeed);
        token = _token;
        DECIMAL_PRECISION = 10 ** IPricesOrchestrator(priceFeed.oracle()).decimals();
    }

    /**
     * @dev Retrieves the converted price by multiplying the primary price with the conversion price.
     */
    function price() public view returns (uint256) {
        return (priceFeed.price() * DECIMAL_PRECISION) / conversionPriceFeed.price();
    }

    /**
     * @dev Retrieves the current price point by calling the 'price()' function.
     */
    function pricePoint() public view returns (uint256) {
        return price();
    }

    /**
     * @dev Emits a price update signal for the associated token.
     */
    function emitPriceSignal() public {
        emit PriceUpdate(token, price(), price());
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import '@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '../interfaces/IPriceFeed.sol';
import '../interfaces/tokens/ICToken.sol';
import '../interfaces/ITokenPriceFeed.sol';
import '../utils/constants.sol';

/**
 * @title CTokenPriceFeed
 * @dev Fetches and handles price data from Chainlink's Oracle for a given underlying token and its corresponding cToken.
 */
contract CTokenPriceFeed is IPriceFeed, Constants {
    AggregatorV2V3Interface public immutable oracle;
    IERC20Metadata public immutable underlyingToken;
    address public immutable override token;
    uint256 public immutable precision;
    uint256 public updateThreshold = 24 hours;

    /**
     * @dev Initializes the Chainlink price feed with the specified oracle and token.
     * @param _oracle The address of the Chainlink oracle contract.
     * @param _CToken The address of the token contract where the rate is stored for the stToken/token.
     * @param _underlyingToken The address of the associated token.
     */
    constructor(address _oracle, address _CToken, address _underlyingToken) {
        require(
            _oracle != address(0x0),
            'e2637b _oracle must not be address 0x0'
        );
        require(
            _CToken != address(0x0),
            'e2637b _CToken must not be address 0x0'
        );
        require(
            _underlyingToken != address(0x0),
            'e2637b _underlyingToken must not be address 0x0'
        );
        token = _CToken;
        underlyingToken = IERC20Metadata(_underlyingToken);
        oracle = AggregatorV2V3Interface(_oracle);
        uint8 decimals = oracle.decimals();
        require(decimals > 0, 'e2637b decimals must be a positive number');
        precision = 10 ** decimals;
    }

    /**
     * @dev Retrieves the current underlying token price from the Chainlink oracle and calculates the cToken.
     * @return The latest recorded price of the cToken.
     */
    function price() public view virtual override returns (uint256) {
        (, int256 _price, , uint256 _timestamp, ) = oracle.latestRoundData();
        uint256 _rate = ICToken(address(token)).exchangeRateStored(); // * Rate comes with the same decimals as underlying token
        require(_price > 0, 'Price must be a positive number');
        require(_rate > 0, 'Exchange rate must be a positive number');
        require(
            block.timestamp - _timestamp <= updateThreshold,
            'Price data is outdated'
        );
        uint256 oneUnderlyingToken = (10 ** underlyingToken.decimals());
        // * How much CToken will I get with 1 UnderlyingToken
        uint256 underlyingRate = (oneUnderlyingToken * DECIMAL_PRECISION) /
            _rate;
        // * Price formated to Decimal precision
        uint256 adjustedPrice = (uint256(_price) * DECIMAL_PRECISION);
        // * Price of 1 CToken
        uint256 priceCToken = (adjustedPrice * DECIMAL_PRECISION) /
            (underlyingRate * DECIMAL_PRECISION);

        return priceCToken;
    }

    /**
     * @dev Retrieves the current price point.
     * @return The current price of the associated token.
     */
    function pricePoint() public view override returns (uint256) {
        return price();
    }

    /**
     * @dev Emits a price update signal for the associated token.
     */
    function emitPriceSignal() public override {
        emit PriceUpdate(token, price(), price());
    }
}

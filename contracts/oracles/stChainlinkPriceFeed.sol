// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import '@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol';
import '../interfaces/IPriceFeed.sol';
import '../interfaces/ITokenPriceFeed.sol';
import '../utils/constants.sol';

/**
 * @title stChainlinkPriceFeed
 * @dev Retrieves and manages price data from Chainlink's Oracle for specified staked tokens.
 */
contract stChainlinkPriceFeed is IPriceFeed, Constants {
    AggregatorV2V3Interface public immutable oracle;
    AggregatorV2V3Interface public immutable rateOracle;
    address public immutable override token;
    uint256 public immutable precision;
    uint256 public updateThreshold = 24 hours;

    /**
     * @dev Initializes the Chainlink price feed with the specified oracle and token.
     * @param _oracle The address of the Chainlink oracle contract.
     * @param _rateOracle The address of the Chainlink oracle contract for the stake rate.
     * @param _token The address of the associated token.
     */
    constructor(address _oracle, address _rateOracle, address _token) {
        require(
            _oracle != address(0x0),
            'e2637b _oracle must not be address 0x0'
        );
        require(
            _rateOracle != address(0x0),
            'e2637b _rateOracle must not be address 0x0'
        );
        require(
            _token != address(0x0),
            'e2637b _token must not be address 0x0'
        );
        token = _token;
        oracle = AggregatorV2V3Interface(_oracle);
        rateOracle = AggregatorV2V3Interface(_rateOracle);
        uint8 decimals = oracle.decimals();
        require(decimals > 0, 'e2637b decimals must be a positive number');
        precision = 10 ** decimals;
    }

    /**
     * @dev Retrieves the current price from the Chainlink oracle, ensuring it is not outdated.
     * @return The latest recorded price of the associated token.
     */
    function price() public view virtual override returns (uint256) {
        (, int256 _price, , uint256 _timestamp, ) = oracle.latestRoundData();
        (, int256 _rate, , uint256 _rateTimestamp, ) = rateOracle
            .latestRoundData();
        require(_price > 0, 'e2637b _price must be a positive number');
        require(_rate > 0, 'e2637b _rate must be a positive number');
        require(
            block.timestamp - _timestamp <= updateThreshold,
            'price-outdated'
        );
        require(
            block.timestamp - _rateTimestamp <= updateThreshold,
            'rate-outdated'
        );

        int256 stPrice = _rate * _price;

        return (uint256(stPrice)) / precision;
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

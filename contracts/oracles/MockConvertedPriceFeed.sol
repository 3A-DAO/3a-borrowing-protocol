// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./ChainlinkPriceFeed.sol";

contract MockConvertedPriceFeed is IPriceFeed, Constants {
    IPriceFeed public immutable priceFeed = IPriceFeed(address(0));
    IPriceFeed public immutable conversionPriceFeed = IPriceFeed(address(0));
    address public immutable override token;

    address public constant DAI = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address public constant WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address public constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant QNT = 0x36B77a184bE8ee56f5E81C56727B20647A42e28E;
    address public constant PAXG = 0x553d3D295e0f695B9228246232eDF400ed3560B5;
    address public constant USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    constructor(address _token) {
        token = _token;
    }

    function price() public view override returns (uint256) {
        if (token == DAI) return 931895460772162633;
        if (token == WETH) return 1775994046278866046632;
        if (token == WMATIC) return 663421266959892649;
        if (token == QNT) return 75127544993710105763;
        if (token == PAXG) return 1828020314028793738060;
        if (token == USDC) return 935946997491670098;
    }

    function pricePoint() public view override returns (uint256) {
        return price();
    }

    function emitPriceSignal() public {
        emit PriceUpdate(token, price(), price());
    }
}

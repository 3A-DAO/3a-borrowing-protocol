// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "./ChainlinkPriceFeed.sol";

contract FixedPriceOracle is IPriceFeed, Constants {
    IPriceFeed public immutable priceFeed = IPriceFeed(address(0));
    IPriceFeed public immutable conversionPriceFeed = IPriceFeed(address(0));
    address public immutable override token;
    uint256 public fixedPrice;
    constructor(address _token, uint256 _price) {

        fixedPrice = _price;
        token = _token;

    }

    function price() public view override returns (uint256) {
        return fixedPrice;
    }

    function pricePoint() public view override returns (uint256) {
        return price();
    }

    function emitPriceSignal() public {
        emit PriceUpdate(token, price(), price());
    }
}

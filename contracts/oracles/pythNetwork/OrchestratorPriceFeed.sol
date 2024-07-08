// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../../interfaces/IPriceFeed.sol";
import "../../interfaces/IPricesOrchestrator.sol";

/**
 * @title OrchestratorPriceFeed
 * @dev Retrieves and manages price data from Price Orchestrator for specified tokens.
 * @author 3A DAO - Cristian (0xCR6)
 */
contract OrchestratorPriceFeed {
    uint256 public immutable DECIMAL_PRECISION;
    address public immutable token;
    IPricesOrchestrator public immutable oracle;

    event PriceUpdate(address token, uint256 price, uint256 average);

    /**
     * @dev Initializes the Orchestrator price feed with the specified oracle and token.
     * @param _oracle The address of the Orchestrator prices orchestrator.
     * @param _token The address of the associated token.
     */
    constructor(address _oracle, address _token) {
        require(_oracle != address(0x0), "invalid-address");
        require(_token != address(0x0), "invalid-address");
        token = _token;
        oracle = IPricesOrchestrator(_oracle);
        uint8 decimals = oracle.decimals();
        require(decimals > 0, "invalid-decimals");
        DECIMAL_PRECISION = 10 ** decimals;
    }

    /**
     * @dev Retrieves the current price from the Orchestrator prices orchestrator, ensuring it is not outdated.
     * @return The latest recorded price of the associated token.
     */
    function price() public view virtual returns (uint256) {
        uint256 _price = oracle.price(token);
        require(_price > 0, "invalid-zero-price");

        return (uint256(_price) * DECIMAL_PRECISION) / DECIMAL_PRECISION;
    }

    /**
     * @dev Retrieves the current price point.
     * @return The current price of the associated token.
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

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "../../interfaces/IPriceFeed.sol";

/**
 * @title PricesOrchestratorPusher
 * @dev Integrates real-time price data from Pyth Network to track asset prices converted into USD or EUR.
 * @dev The contract will get price updates when needed based on the Pyth network API response.
 * @author 3A DAO - Cristian (0xCR6)
 */
contract PricesOrchestratorPusher is Ownable {
    uint256 public immutable DECIMAL_PRECISION;
    uint public priceValidTimeRange = 4500; // 1 hour and 15 minutes
    address public euro3;

    mapping(address => bool) public validTokens;
    mapping(address => PythStructs.Price) private tokenToPrice;

    event TokensUpdated(address[] tokens, bool[] isValid);
    event PricesUpdated(address[] tokens);

    constructor(address _euro3) Ownable(msg.sender) {
        require(_euro3 != address(0), "invalid-address");
        euro3 = _euro3;
        DECIMAL_PRECISION = 10 ** decimals();
    }

    // External Functions

    /**
     * @dev Retrieves the latest formatted prices for the specified tokens.
     * @param _tokens Array of token addresses.
     * @param _isEUR toggle to return prices in EUR or USD format.
     * @return formatedPrices Array of formatted token prices.
     */
    function batchPrices(address[] memory _tokens, bool _isEUR) external view returns (uint256[] memory) {
        require(_tokens.length > 0, "tokens-required");

        PythStructs.Price[] memory _prices = new PythStructs.Price[](_tokens.length);
        uint256[] memory formatedPrices = new uint256[](_tokens.length);

        for (uint i = 0; i < _tokens.length; ) {
            require(validTokens[_tokens[i]], "invalid-token");
            checkOutdatedPrice(_tokens[i]);
            _prices[i] = tokenToPrice[_tokens[i]];

            uint256 fPrice = convertPriceToUint(_prices[i]);

            if (_isEUR) {
                uint256 eurPrice = convertPriceToEur(fPrice);
                formatedPrices[i] = eurPrice;
            } else {
                formatedPrices[i] = fPrice / DECIMAL_PRECISION;
            }

            unchecked {
                i++;
            }
        }

        return formatedPrices;
    }

    // Public Functions

    /**
     * @dev Retrieves the latest formatted prices for a specific token.
     * @param _token Token address.
     * @return formatted token price in USD format.
     */
    function price(address _token) public view returns (uint256) {
        require(_token != address(0), "not-valid-address");
        require(validTokens[_token], "invalid-token");
        checkOutdatedPrice(_token);

        PythStructs.Price memory _price = tokenToPrice[_token];

        return convertPriceToUint(_price) / DECIMAL_PRECISION;
    }

    /**
     * @dev Retrieves the price of a token using the `price` method.
     * @param _token The address of the token.
     * @return The price of the token in USD format.
     */
    function pricePoint(address _token) external view returns (uint256) {
        return price(_token);
    }

    /**
     * @dev Method to get the EUR/USD Rate
     */
    function conversionRate() public view returns (uint256) {
        checkOutdatedPrice(euro3);
        return convertPriceToUint(tokenToPrice[euro3]) / DECIMAL_PRECISION;
    }

    // Internal Functions

    /**
     * @dev Checks if the price for a token is outdated based on the current timestamp.
     * @param _token The address of the token.
     * @return A boolean indicating whether the price is outdated or not.
     */
    function checkOutdatedPrice(address _token) internal view returns (bool) {
        require(block.timestamp <= tokenToPrice[_token].publishTime + priceValidTimeRange, "price-outdated");
        return true;
    }

    // Private Functions

    /**
     * @dev Internal method to get the EUR/USD Rate
     */
    function _conversionRate() private view returns (uint256) {
        checkOutdatedPrice(euro3);
        return convertPriceToUint(tokenToPrice[euro3]);
    }

    /**
     * @dev Converts Pyth price data to EURO value.
     * @param _price The Pyth price data.
     * @return Formatted uint value representing the price in EURO.
     */
    function convertPriceToEur(uint256 _price) private view returns (uint) {
        return (_price * DECIMAL_PRECISION) / (_conversionRate());
    }

    /**
     * @dev Converts Pyth price data to a formatted uint value.
     * @param _price The Pyth price data.
     * @return Formatted uint value representing the price in USD.
     */
    function convertPriceToUint(PythStructs.Price memory _price) private view returns (uint) {
        require(_price.price > 0 || _price.expo < 0 || _price.expo > -255, "invalid-price");
        uint8 targetDecimals = 18;
        require(targetDecimals != 0, "invalid-decimals");
        uint8 priceDecimals = uint8(uint32(-1 * _price.expo));
        uint priceUSD;
        if (targetDecimals >= priceDecimals) {
            priceUSD = uint(uint64(_price.price)) * 10 ** uint32(targetDecimals - priceDecimals);
        } else {
            priceUSD = uint(uint64(_price.price)) / 10 ** uint32(priceDecimals - targetDecimals);
        }

        return (priceUSD * DECIMAL_PRECISION);
    }

    // View Functions

    /**
     * @dev Returns the number of decimals used for token prices.
     */
    function decimals() public pure returns (uint8) {
        return 18;
    }

    // Owner Functions

    /**
     * @dev Updates token prices based on the provided data.
     * @param _tokens Array of token addresses.
     * @param _newPrices Array of new prices, gotten from Pyth Endpoint.
     * @param _conf Array of Confidence interval around the price, gotten from Pyth Endpoint.
     * @param _expo Array of Price exponent, gotten from Pyth Endpoint.
     * @param _publishTime Array of Unix timestamp describing when the price was published, gotten from Pyth Endpoint.
     */

    function updatePrice(
        address[] memory _tokens,
        int64[] memory _newPrices,
        uint64[] memory _conf,
        int32[] memory _expo,
        uint[] memory _publishTime
    ) external onlyOwner {
        require(_tokens.length > 0, "tokens-required");
        require(
            _tokens.length == _newPrices.length &&
                _tokens.length == _conf.length &&
                _tokens.length == _expo.length &&
                _tokens.length == _publishTime.length,
            "Arrays length mismatch"
        );

        for (uint i = 0; i < _tokens.length; i++) {
            PythStructs.Price memory _lastPrice = PythStructs.Price(_newPrices[i], _conf[i], _expo[i], _publishTime[i]);
            tokenToPrice[_tokens[i]] = _lastPrice;
        }

        emit PricesUpdated(_tokens);
    }

    /**
     * @dev Sets the time range during which prices are considered valid.
     * @param _priceValidTimeRange The new valid time range.
     */
    function setPriceValidTimeRange(uint _priceValidTimeRange) public onlyOwner {
        require(_priceValidTimeRange > 0, "invalid-priceValidTimeRange");
        priceValidTimeRange = _priceValidTimeRange;
    }

    /**
     * @dev Sets tokens as valid or invalid.
     * @param _tokens The array of token addresses to set validation.
     * @param _isValid Array of booleans to define validation for each token.
     */
    function updateTokens(address[] memory _tokens, bool[] memory _isValid) public onlyOwner {
        require(_tokens.length == _isValid.length, "Arrays length mismatch");

        for (uint256 i = 0; i < _tokens.length; ) {
            require(_tokens[i] != address(0), "invalid-token");
            validTokens[_tokens[i]] = _isValid[i];
            unchecked {
                i++;
            }
        }

        emit TokensUpdated(_tokens, _isValid);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "../../interfaces/IPriceFeed.sol";

/**
 * @title PricesOrchestrator
 * @dev Integrates real-time price data from Pyth Network to track asset prices converted into USD or EUR.
 * @author 3A DAO - Cristian (0xCR6)
 */
contract PricesOrchestrator is Ownable {
    uint256 public immutable DECIMAL_PRECISION;
    uint public priceValidTimeRange = 4500; // 1 hour and 15 minutes
    address public euro3;
    IPyth public pyth;

    mapping(address => bytes32) public tokenToId;
    mapping(address => PythStructs.Price) private tokenToPrice;

    event TokensUpdated(address[] tokens, bytes32[] priceIDs); // Price feed ids - https://pyth.network/developers/price-feed-ids
    event PricesUpdated(address[] tokens);
    event PythUpdated(address newPyth);

    constructor(address _pythContract, address _euro3) Ownable(msg.sender) {
        require(_pythContract != address(0), "invalid-address");
        require(_euro3 != address(0), "invalid-address");
        pyth = IPyth(_pythContract); // Pyth contracts EVM - https://docs.pyth.network/price-feeds/contract-addresses/evm
        euro3 = _euro3;
        DECIMAL_PRECISION = 10 ** decimals();
    }

    // External Functions

    /**
     * @dev Links tokens with Pyth Network price IDs.
     * @param _tokens Array of token addresses.
     * @param _priceIDs Array of corresponding Pyth Network price IDs.
     */
    function updateIds(address[] memory _tokens, bytes32[] memory _priceIDs) external onlyOwner {
        require(_tokens.length > 0, "tokens-required");
        require(_tokens.length == _priceIDs.length, "arrays-length-mismatch");

        for (uint i = 0; i < _tokens.length; ) {
            tokenToId[_tokens[i]] = _priceIDs[i];
            unchecked {
                i++;
            }
        }

        emit TokensUpdated(_tokens, _priceIDs);
    }

    /**
     * @dev Updates token prices based on the provided data.
     * @param _tokens Array of token addresses.
     * @param _priceUpdateData Array of price update data.
     */
    function updatePrice(
        address[] memory _tokens,
        bytes[] memory _priceUpdateData // `pyth-evm-js` package.
    ) external payable {
        require(_tokens.length > 0, "tokens-required");
        require(_priceUpdateData.length > 0, "priceUpdateData-required");
        uint fee = pyth.getUpdateFee(_priceUpdateData);
        pyth.updatePriceFeeds{value: fee}(_priceUpdateData);

        for (uint i = 0; i < _tokens.length; ) {
            bytes32 priceID = tokenToId[_tokens[i]];
            PythStructs.Price memory _lastPrice = pyth.getPrice(priceID);
            tokenToPrice[_tokens[i]] = _lastPrice;
            unchecked {
                i++;
            }
        }

        emit PricesUpdated(_tokens);
    }

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
            require(tokenToId[_tokens[i]] != bytes32(0), "invalid-token");
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

    /**
     * @dev Calculates the fee required for updating prices based on the provided data.
     * @param _priceUpdateData Array of price update data.
     * @return Fee required for the update.
     */
    function getUpdateFee(bytes[] memory _priceUpdateData) external view returns (uint256) {
        return pyth.getUpdateFee(_priceUpdateData);
    }

    // Public Functions

    /**
     * @dev Retrieves the latest formatted prices for a specific token.
     * @param _token Token address.
     * @return formatted token price in USD format.
     */
    function price(address _token) public view returns (uint256) {
        require(_token != address(0), "not-valid-address");
        require(tokenToId[_token] != bytes32(0), "invalid-token");
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
     * @dev Sets the time range during which prices are considered valid.
     * @param _priceValidTimeRange The new valid time range.
     */
    function setPriceValidTimeRange(uint _priceValidTimeRange) public onlyOwner {
        require(_priceValidTimeRange > 0, "invalid-priceValidTimeRange");
        priceValidTimeRange = _priceValidTimeRange;
    }

    /**
     * @dev Updates the Pyth contract address.
     * @param _newPyth The new address of the Pyth contract.
     */
    function updatePyth(address _newPyth) external onlyOwner {
        require(_newPyth != address(0), "invalid-address");
        pyth = IPyth(_newPyth);
        emit PythUpdated(_newPyth);
    }
}

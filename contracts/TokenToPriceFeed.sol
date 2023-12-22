// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "./interfaces/IPriceFeed.sol";
import "./utils/constants.sol";
import "./interfaces/ITokenPriceFeed.sol";

/**
 * @title TokenToPriceFeed
 * @dev Manages mapping of token addresses to their respective price feed contracts.
 */
contract TokenToPriceFeed is Ownable, Constants, ITokenPriceFeed {
    /// @dev Mapping of token address to its associated price feed contract.
    mapping(address => TokenInfo) public tokens;

    /**
     * @dev Retrieves the contract owner's address.
     */
    function owner() public view override(Ownable, IOwnable) returns (address) {
        return Ownable.owner();
    }

    /**
     * @dev Retrieves the token's current price from the respective price feed.
     * @param  _token Address of the token.
     */
    function tokenPrice(address _token) public view override returns (uint256) {
        return IPriceFeed(tokens[_token].priceFeed).price();
    }

    /**
     * @dev Retrieves the price feed contract address for a given token.
     * @param  _token Address of the token.
     */
    function tokenPriceFeed(address _token) public view override returns (address) {
        return tokens[_token].priceFeed;
    }

    /**
     * @dev Retrieves the minimal collateral ratio for a given token.
     * @param  _token Address of the token.
     */
    function mcr(address _token) public view override returns (uint256) {
        return tokens[_token].mcr;
    }

    /**
     * @dev Retrieves the decimal places of a given token.
     * @param  _token Address of the token.
     */
    function decimals(address _token) public view override returns (uint256) {
        return tokens[_token].decimals;
    }

    /**
     * @dev Retrieves the minimal liquidation ratio for a given token.
     * @param  _token Address of the token.
     */
    function mlr(address _token) public view override returns (uint256) {
        return tokens[_token].mlr;
    }

    /**
     * @dev Retrieves the borrow rate for a given token.
     * @param  _token Address of the token.
     */

    function borrowRate(address _token) public view override returns (uint256) {
        return tokens[_token].borrowRate;
    }

    /**
     * @dev Sets or updates the price feed contract for a specific token.
     * @param  _token Address of the token.
     * @param  _priceFeed Address of the PriceFeed contract for the token.
     * @param  _mcr Minimal Collateral Ratio of the token.
     * @param  _mlr Minimal Liquidation Ratio of the token.
     * @param  _borrowRate Borrow rate of the token.
     * @param  _decimals Decimals of the token.
     */
    function setTokenPriceFeed(
        address _token,
        address _priceFeed,
        uint256 _mcr,
        uint256 _mlr,
        uint256 _borrowRate,
        uint256 _decimals
    ) public override onlyOwner {
        require(_mcr >= 100, "MCR < 100");
        require(_mlr >= 100 && _mlr <= _mcr, "MLR < 100 or MLR > MCR");
        require(_decimals > 0, "decimals = 0");
        require(_borrowRate < 10 ether, "borrowRate >= 10%");

        TokenInfo memory token = tokens[_token];
        token.priceFeed = _priceFeed;
        IERC20Metadata erc20 = IERC20Metadata(_token);
        token.mcr = (DECIMAL_PRECISION * _mcr) / 100;
        token.mlr = (DECIMAL_PRECISION * _mlr) / 100;
        token.borrowRate = _borrowRate;
        token.decimals = _decimals;
        emit NewTokenPriceFeed(
            _token,
            _priceFeed,
            erc20.name(),
            erc20.symbol(),
            token.mcr,
            token.mlr,
            token.borrowRate,
            token.decimals
        );
        tokens[_token] = token;
    }

    /**
     * @dev Transfers ownership after revoking other roles from other addresses.
     * @param _newOwner Address of the new owner.
     */
    function transferOwnership(address _newOwner) public override(Ownable, IOwnable) {
        Ownable.transferOwnership(_newOwner);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import '../interfaces/IVaultFactory.sol';
import '../interfaces/ITokenPriceFeed.sol';
import '../interfaces/mendi/ICToken.sol';
import '../interfaces/IPriceFeed.sol';
import '../interfaces/IVault.sol';

/**
 * @title SurgeHelper
 * @notice Helper contract providing data about TVL and collaterals by vault
 */
contract SurgeHelper {
    string public constant VERSION = '1.1.0';
    uint256 public constant DECIMAL_PRECISION = 1e18;
    address public constant CONVERSION_PRICE_FEED =
        0x06E684f6E0a601b0b8304CC2f22980a6E480c981; // EUR/USDC Price feed Linea

    /**
     * @notice Retrieves all vault addresses within a vault factory
     * @param _vaultFactory Address of the vault factory
     * @return An array of vault addresses
     */
    function getAllVaults(
        address _vaultFactory
    ) public view returns (address[] memory) {
        IVaultFactory vaultFactory = IVaultFactory(_vaultFactory);
        uint256 vaultCount = vaultFactory.vaultCount();
        if (vaultCount == 0) {
            return new address[](0);
        } else {
            address[] memory vaults = new address[](vaultCount);
            vaults[0] = vaultFactory.firstVault();
            for (uint256 i = 1; i < vaultCount; i++) {
                vaults[i] = vaultFactory.nextVault(vaults[i - 1]);
            }
            return vaults;
        }
    }

    /**
     * @notice Get the total value locked (TVL) and the amount of underlying tokens for a given vault and receipt token.
     * @param vaultAddress The address of the vault.
     * @param receiptTokenAddress The address of the collateral receipt token.
     * @return The total value locked (TVL) in the vault and the amount of underlying tokens.
     */
    function getVaultTVLAndUnderlyingAmount(
        address vaultAddress,
        address receiptTokenAddress
    ) public view returns (uint256, uint256) {
        IVault vault = IVault(vaultAddress);
        ICToken receiptToken = ICToken(receiptTokenAddress);
        uint256 collateralAmount = vault.collateral(receiptTokenAddress);

        uint256 exchangeRate = receiptToken.exchangeRateStored();
        uint8 receiptTokenDecimals = receiptToken.decimals();

        // Calculate the amount of underlying tokens
        uint256 underlyingAmount = (collateralAmount * exchangeRate) /
            (10 ** (receiptTokenDecimals + 10));

        ITokenPriceFeed priceFeed = ITokenPriceFeed(
            IVaultFactory(vault.factory()).priceFeed()
        );
        uint256 price = priceFeed.tokenPrice(receiptTokenAddress);
        uint256 normalizedCollateralAmount = collateralAmount *
            (10 ** (18 - priceFeed.decimals(receiptTokenAddress)));
        uint256 tvl = (normalizedCollateralAmount * price) / DECIMAL_PRECISION;

        tvl = convertEuroToDollar(tvl);

        return (tvl, underlyingAmount);
    }

    /**
     * @notice Retrieves the Total Value Locked (TVL) of a specific vault based on a single collateral type
     * @param vaultAddress Address of the vault
     * @param collateralAddress Address of the collateral asset
     * @return The TVL of the vault for the given collateral
     */
    function getVaultTVLAndCollateralAmount(
        address vaultAddress,
        address collateralAddress
    ) public view returns (uint256, uint256) {
        IVault vault = IVault(vaultAddress);
        uint256 collateralAmount = vault.collateral(collateralAddress);

        ITokenPriceFeed priceFeed = ITokenPriceFeed(
            IVaultFactory(vault.factory()).priceFeed()
        );
        uint256 price = priceFeed.tokenPrice(collateralAddress);
        uint256 normalizedCollateralAmount = collateralAmount *
            (10 ** (18 - priceFeed.decimals(collateralAddress)));
        uint256 tvl = (normalizedCollateralAmount * price) / DECIMAL_PRECISION;

        tvl = convertEuroToDollar(tvl);
        return (tvl, collateralAmount);
    }

    /**
     * @notice Converts an amount from Euro to Dollar using the current conversion rate
     * @param euroAmount The amount in Euro
     * @return The amount in Dollar
     */
    function convertEuroToDollar(
        uint256 euroAmount
    ) public view returns (uint256) {
        uint256 rate = IPriceFeed(CONVERSION_PRICE_FEED).price();
        uint256 dollarAmount = (euroAmount * (rate)) / 1e18;
        return dollarAmount;
    }
}

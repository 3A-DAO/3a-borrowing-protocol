// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import '../interfaces/IVault.sol';
import '../interfaces/ITokenPriceFeed.sol';
import '../interfaces/IVaultFactory.sol';

/**
 * @title VaultBorrowRate
 * @notice Contract to calculate the borrow rate for a given Vault
 */
contract VaultBorrowRate {
    /**
     * @notice Calculates the borrow rate for a specified Vault
     * @param _vaultAddress The address of the Vault for which to calculate the borrow rate
     * @return uint256 The calculated borrow rate
     */
    function getBorrowRate(
        address _vaultAddress
    ) external view returns (uint256) {
        IVault _vault = IVault(_vaultAddress);
        IVaultFactory _vaultFactory = IVaultFactory(_vault.factory());
        ITokenPriceFeed _priceFeed = ITokenPriceFeed(_vaultFactory.priceFeed());
        uint256 _totalWeightedFee;
        uint256 _totalCollateralValue;
        uint256 _collateralsLength = _vault.collateralsLength();

        for (uint256 i; i < _collateralsLength; i++) {
            address _collateralAddress = _vault.collateralAt(i);
            uint256 _collateralAmount = _vault.collateral(_collateralAddress);
            uint256 _price = _priceFeed.tokenPrice(_collateralAddress);
            uint256 _borrowRate = _priceFeed.borrowRate(_collateralAddress);

            uint256 _normalizedCollateralAmount = _collateralAmount *
                (10 ** (18 - _priceFeed.decimals(_collateralAddress)));
            uint256 _collateralValue = (_normalizedCollateralAmount * _price) /
                (10 ** _priceFeed.decimals(_collateralAddress));
            uint256 _weightedFee = (_collateralValue * _borrowRate) / 1e18;

            _totalCollateralValue += _collateralValue;
            _totalWeightedFee += _weightedFee;
        }

        return ((_totalWeightedFee * 1e18) / _totalCollateralValue) / 100;
    }
}

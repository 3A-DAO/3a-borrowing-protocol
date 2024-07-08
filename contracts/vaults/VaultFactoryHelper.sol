// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import '../interfaces/IVaultFactory.sol';
import '../interfaces/IVault.sol';
import '../interfaces/ITokenPriceFeed.sol';

/**
 * @title VaultFactoryHelper
 * @notice Helper contract providing various functions to retrieve information about vaults in a vault factory
 */
contract VaultFactoryHelper {
    uint256 public constant DECIMAL_PRECISION = 1e18;

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
     * @notice Retrieves the Total Value Locked (TVL) of a specific vault based on a single collateral type
     * @param _vaultAddress Address of the vault
     * @param _collateralAddress Address of the collateral asset
     * @return The TVL of the vault for the given collateral
     */
    function getVaultTvlByCollateral(
        address _vaultAddress,
        address _collateralAddress
    ) public view returns (uint256) {
        IVault _vault = IVault(_vaultAddress);
        uint256 _collateralAmount = _vault.collateral(_collateralAddress);
        ITokenPriceFeed _priceFeed = ITokenPriceFeed(
            IVaultFactory(_vault.factory()).priceFeed()
        );
        uint256 _price = _priceFeed.tokenPrice(_collateralAddress);
        uint256 _normalizedCollateralAmount = _collateralAmount *
            (10 ** (18 - _priceFeed.decimals(_collateralAddress)));
        uint256 _tvl = (_normalizedCollateralAmount * _price) /
            DECIMAL_PRECISION;
        return _tvl;
    }

    /**
     * @notice Retrieves the Total Value Locked (TVL) of a vault across all collateral types it holds
     * @param _vault Address of the vault
     * @return The total TVL of the vault across all collateral types
     */
    function getVaultTvl(address _vault) public view returns (uint256) {
        IVault vault = IVault(_vault);
        uint256 tvl = 0;
        for (uint256 i = 0; i < vault.collateralsLength(); i++) {
            address _collateralAddress = vault.collateralAt(i);
            tvl += getVaultTvlByCollateral(_vault, _collateralAddress);
        }
        return tvl;
    }

    /**
     * @notice Retrieves an array of liquidatable vault addresses within a vault factory
     * @param _vaultFactory Address of the vault factory
     * @return An array of liquidatable vault addresses
     */
    function getLiquidatableVaults(
        address _vaultFactory
    ) public view returns (address[] memory) {
        IVaultFactory vaultFactory = IVaultFactory(_vaultFactory);
        uint256 vaultCount = vaultFactory.vaultCount();
        uint256 liquidatableVaultCount = 0;
        if (vaultCount == 0) {
            return new address[](0);
        } else {
            address[] memory _vaults = getAllVaults(_vaultFactory);
            address[] memory _liquidatableVaults = new address[](vaultCount);

            for (uint256 i = 0; i < vaultCount; i++) {
                IVault _vault = IVault(_vaults[i]);
                if (vaultFactory.isLiquidatable(address(_vault))) {
                    _liquidatableVaults[liquidatableVaultCount] = address(
                        _vault
                    );
                    liquidatableVaultCount++;
                }
            }

            address[] memory liquidatableVaults = new address[](
                liquidatableVaultCount
            );
            for (uint256 i = 0; i < liquidatableVaultCount; i++) {
                liquidatableVaults[i] = _liquidatableVaults[i];
            }

            return liquidatableVaults;
        }
    }

    /**
     * @notice Retrieves an array of redeemable vault addresses and their corresponding redeemable collaterals
     * @param _vaultFactory Address of the vault factory
     * @param _useMlr Boolean indicating whether to use MLR for health factor calculation
     * @return redeemableVaults An array of redeemable vault addresses
     * @return redeemableCollaterals An array of corresponding redeemable collateral addresses
     */
    function getRedeemableVaults(
        address _vaultFactory,
        bool _useMlr
    )
        public
        view
        returns (
            address[] memory redeemableVaults,
            address[] memory redeemableCollaterals
        )
    {
        IVaultFactory vaultFactory = IVaultFactory(_vaultFactory);
        uint256 vaultCount = vaultFactory.vaultCount();
        uint256 redeemableVaultCount = 0;
        uint256 healthFactorLimit = vaultFactory.redemptionHealthFactorLimit();
        if (vaultCount == 0) {
            return (new address[](0), new address[](0));
        } else {
            address[] memory _vaults = getAllVaults(_vaultFactory);
            address[] memory _redeemableVaults = new address[](vaultCount);
            address[] memory _redeemableCollaterals = new address[](vaultCount);

            for (uint256 i = 0; i < vaultCount; i++) {
                IVault _vault = IVault(_vaults[i]);
                if (_vault.healthFactor(_useMlr) < healthFactorLimit) {
                    _redeemableVaults[redeemableVaultCount] = address(_vault);

                    address[] memory _collaterals = getVaultCollaterals(
                        address(_vault)
                    );

                    for (uint256 j = 0; j < _collaterals.length; j++) {
                        if (
                            vaultFactory.isReedemable(
                                address(_vault),
                                _collaterals[j]
                            )
                        ) {
                            _redeemableCollaterals[
                                redeemableVaultCount
                            ] = _collaterals[j];
                            break;
                        }
                    }

                    redeemableVaultCount++;
                }
            }

            redeemableVaults = new address[](redeemableVaultCount);
            redeemableCollaterals = new address[](redeemableVaultCount);

            for (uint256 i = 0; i < redeemableVaultCount; i++) {
                redeemableVaults[i] = _redeemableVaults[i];
                redeemableCollaterals[i] = _redeemableCollaterals[i];
            }
        }
    }

    /**
     * @notice Retrieves an array of collateral asset addresses held by a specific vault
     * @param _vault Address of the vault
     * @return An array of collateral asset addresses
     */
    function getVaultCollaterals(
        address _vault
    ) public view returns (address[] memory) {
        IVault vault = IVault(_vault);
        uint256 collateralsLength = vault.collateralsLength();
        if (collateralsLength == 0) {
            return new address[](0);
        } else {
            address[] memory collaterals = new address[](collateralsLength);
            for (uint256 i = 0; i < collateralsLength; i++) {
                collaterals[i] = vault.collateralAt(i);
            }
            return collaterals;
        }
    }

    /**
     * @notice Calculates the Total Value Locked (TVL) across all vaults within a vault factory
     * @param _vaultFactory Address of the vault factory
     * @return The total TVL across all vaults in the factory
     */
    function getProtocolTvl(
        address _vaultFactory
    ) public view returns (uint256) {
        IVaultFactory vaultFactory = IVaultFactory(_vaultFactory);
        uint256 vaultCount = vaultFactory.vaultCount();
        uint256 tvl = 0;
        if (vaultCount == 0) {
            return 0;
        } else {
            address[] memory _vaults = getAllVaults(_vaultFactory);
            for (uint256 i = 0; i < vaultCount; i++) {
                tvl += getVaultTvl(_vaults[i]);
            }
            return tvl;
        }
    }
}

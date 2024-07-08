// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import './Vault.sol';
import '../interfaces/IVaultExtraSettings.sol';

/**
 * @title VaultDeployer
 * @notice A contract responsible for deploying new instances of the Vault contract.
 */
contract VaultDeployer {
    IVaultExtraSettings public immutable vaultExtraSettings;

    constructor(address _vaultExtraSettings) {
        require(
            _vaultExtraSettings != address(0x0),
            'vault-extra-settings-is-zero'
        );
        vaultExtraSettings = IVaultExtraSettings(_vaultExtraSettings);
    }

    /**
     * @notice Deploys a new Vault contract.
     * @param _factory The address of the factory contract managing the vaults.
     * @param _vaultOwner The address of the intended owner of the new vault.
     * @param _name The name of the new vault.
     * @return The address of the newly created Vault contract.
     */
    function deployVault(
        address _factory,
        address _vaultOwner,
        string memory _name
    ) external returns (address) {
        // Deploy a new instance of the Vault contract
        Vault vault = new Vault(
            _factory,
            _vaultOwner,
            _name,
            vaultExtraSettings
        );
        return address(vault);
    }
}

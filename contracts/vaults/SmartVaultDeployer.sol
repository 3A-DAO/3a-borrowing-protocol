// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import './SmartVault.sol';
import '../interfaces/IVaultExtraSettings.sol';
import '../interfaces/ISmartVaultProxy.sol';

/**
 * @title SmartVaultDeployer
 * @notice A contract responsible for deploying new instances of the Vault contract.
 */
contract SmartVaultDeployer {
    IVaultExtraSettings public immutable vaultExtraSettings;
    ISmartVaultProxy public immutable smartVaultProxy;

    constructor(address _vaultExtraSettings, address _smartVaultProxy) {
        require(
            _vaultExtraSettings != address(0x0),
            'vault-extra-settings-is-zero'
        );
        require(_smartVaultProxy != address(0x0), 'smart-vault-proxy-is-zero');
        vaultExtraSettings = IVaultExtraSettings(_vaultExtraSettings);
        smartVaultProxy = ISmartVaultProxy(_smartVaultProxy);
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
        SmartVault vault = new SmartVault(
            _factory,
            _vaultOwner,
            _name,
            vaultExtraSettings,
            smartVaultProxy
        );
        return address(vault);
    }
}

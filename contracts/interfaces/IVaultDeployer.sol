// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IVaultDeployer {
    function deployVault(
        address _factory,
        address _vaultOwner,
        string memory _name
    ) external returns (address);
}

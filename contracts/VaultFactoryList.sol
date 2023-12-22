// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;
import "./utils/constants.sol";
import "./utils/linked-address-list.sol";
// import openzeppelin context
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title VaultFactoryList
 * @dev Manages a list of vaults by their owners, allowing addition, removal, and transfer of vaults.
 */
abstract contract VaultFactoryList is Context {
    using LinkedAddressList for LinkedAddressList.List;
    using EnumerableSet for EnumerableSet.AddressSet;

    LinkedAddressList.List _vaults;
    mapping(address => EnumerableSet.AddressSet) private _vaultsByOwner;

    function vaultsByOwnerLength(address _owner) external view returns (uint256) {
        return _vaultsByOwner[_owner].length();
    }

    function vaultsByOwner(address _owner, uint256 _index) external view returns (address) {
        return _vaultsByOwner[_owner].at(_index);
    }

    function _addVault(address _owner, address _vault) internal {
        require(_vaults.add(_vault, address(0x0), false), "vault-could-not-be-added");
        _vaultsByOwner[_owner].add(_vault);
    }

    function _transferVault(address _from, address _to, address _vault) internal {
        _vaultsByOwner[_from].remove(_vault);
        _vaultsByOwner[_to].add(_vault);
    }

    function _removeVault(address _owner, address _vault) internal {
        require(_vaults.remove(_vault), "vault-could-not-be-removed");
        _vaultsByOwner[_owner].remove(_vault);
    }

    /**
     * @dev returns the number of vaults for specific token
     */
    function vaultCount() public view returns (uint256) {
        return _vaults._size;
    }

    /**
     * @dev returns the last vault by maximum collaterization ratio
     */
    function lastVault() public view returns (address) {
        return _vaults._last;
    }

    /**
     * @dev returns the first vault by minimal collaterization ratio
     */
    function firstVault() public view returns (address) {
        return _vaults._first;
    }

    /**
     * @dev returns the next vault by collaterization ratio
     */
    function nextVault(address _vault) public view returns (address) {
        return _vaults._values[_vault].next;
    }

    /**
     * @dev returns the previous vault by collaterization ratio
     */
    function prevVault(address _vault) public view returns (address) {
        return _vaults._values[_vault].prev;
    }

    /**
     * @dev Checks if a vault exists for a specific token.
     * @param _vault The address of the vault to check.
     * @return A boolean indicating whether the vault exists.
     */
    function containsVault(address _vault) public view returns (bool) {
        return _vaults._values[_vault].next != address(0x0);
    }
}

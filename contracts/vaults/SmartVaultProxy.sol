// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/Context.sol';
import '../utils/constants.sol';

/**
 * @title SmartVaultProxy
 * @dev Enables the execution of whitelisted methods authorized by the proxy owner across all smart vaults.
 */

contract SmartVaultProxy is Context, Ownable {
    address public rewardCollector; // Rewards collector address
    uint16 public rewardFee; // 1 = 0.01%
    mapping(uint256 => bool) public permissions;

    event PermissionAdded(
        address targetAddress,
        bytes4 targetSignature,
        uint256 permissionHash
    );
    event PermissionRemoved(uint256 indexed permissionHash);
    event RewardFeeUpdated(uint16 newRewardFee);
    event RewardCollectorUpdated(address newRewardCollector);

    constructor(uint16 _rewardFee) payable {
        require(_rewardFee < 10000, 'innvalid-fee');

        rewardFee = _rewardFee;
        rewardCollector = msg.sender;
    }

    /**
     * @dev Adds permission for a specific vault to execute a function on a target address.
     * @param targetAddress The target address where the function will be called.
     * @param targetSignature The function signature to be executed.
     */
    function addPermission(
        address targetAddress,
        bytes4 targetSignature
    ) external onlyOwner {
        uint256 _hash = getHash(targetAddress, targetSignature);
        permissions[_hash] = true;
        emit PermissionAdded(targetAddress, targetSignature, _hash);
    }

    /**
     * @dev Removes a specific permission.
     * @param targetAddress The target address to remove Permissions.
     * @param targetSignature The function signature to remove Permissions.
     */
    function removePermission(
        address targetAddress,
        bytes4 targetSignature
    ) external onlyOwner {
        uint256 _hash = getHash(targetAddress, targetSignature);

        delete permissions[_hash];
        emit PermissionRemoved(_hash);
    }

    /**
     * @dev Sets the reward fee for the Smart Vault.
     * @param _newRewardFee The new reward fee to be set.
     */
    function setRewardFee(uint16 _newRewardFee) external onlyOwner {
        require(_newRewardFee < 10000, 'innvalid-fee');
        rewardFee = _newRewardFee;
        emit RewardFeeUpdated(_newRewardFee);
    }

    /**
     * @dev Sets the reward collector address for the Smart Vault.
     * @param newRewardCollector The new reward collector address to be set.
     */
    function setRewardCollector(address newRewardCollector) external onlyOwner {
        require(newRewardCollector != address(0), 'innvalid-collector');
        rewardCollector = newRewardCollector;
        emit RewardCollectorUpdated(newRewardCollector);
    }

    /**
     * @dev Checks if a specific target address and function signature are whitelisted.
     * @param targetAddress The target address to check.
     * @param targetSignature The function signature to check.
     * @return Boolean indicating whether the target address and function signature are whitelisted.
     */
    function isWhitelisted(
        address targetAddress,
        bytes4 targetSignature
    ) external view returns (bool) {
        uint256 _hash = getHash(targetAddress, targetSignature);
        return permissions[_hash];
    }

    /**
     * @dev Calculates the hash for a target address and function signature.
     * @param targetAddress The target address for the function.
     * @param targetSignature The function signature.
     * @return _hash The calculated hash value.
     */
    function getHash(
        address targetAddress,
        bytes4 targetSignature
    ) internal pure returns (uint256 _hash) {
        require(targetAddress != address(0), 'invalid-target-address');
        _hash = uint256(
            keccak256(abi.encodePacked(targetAddress, targetSignature))
        );
    }
}

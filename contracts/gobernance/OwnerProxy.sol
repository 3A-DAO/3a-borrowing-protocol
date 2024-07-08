// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/Context.sol';

/**
 * @title OwnerProxy
 * @dev Allows the main owner to add fine-grained permissions to other operators.
 */
contract OwnerProxy is Context, Ownable {
    mapping(uint256 => bool) public permissions;

    event PermissionAdded(
        address indexed caller,
        address targetAddress,
        bytes4 targetSignature,
        uint256 permissionHash
    );
    event PermissionRemoved(uint256 indexed permissionHash);
    event Executed(
        address indexed caller,
        address indexed target,
        string func,
        bytes data
    );

    /**
     * @dev Adds permission for a specific caller to execute a function on a target address.
     * @param caller The address allowed to call the function.
     * @param targetAddress The target address where the function will be called.
     * @param targetSignature The function signature to be executed.
     */
    function addPermission(
        address caller,
        address targetAddress,
        bytes4 targetSignature
    ) public onlyOwner {
        require(caller != address(0), 'invalid-caller-address');
        require(targetAddress != address(0), 'invalid-target-address');
        uint256 _hash = uint256(
            keccak256(abi.encodePacked(caller, targetAddress, targetSignature))
        );
        permissions[_hash] = true;
        emit PermissionAdded(caller, targetAddress, targetSignature, _hash);
    }

    /**
     * @dev Removes a specific permission.
     * @param permissionHash The hash of the permission to be removed.
     */
    function removePermission(uint256 permissionHash) public onlyOwner {
        delete permissions[permissionHash];
        emit PermissionRemoved(permissionHash);
    }

    /**
     * @dev Executes a function on a target address only if the caller has the required permission.
     * @param target The contract address where the function will be called.
     * @param func The name of the function to be executed.
     * @param data The data to be passed to the function.
     * @return _result The result of the function execution.
     */
    function execute(
        address target,
        string memory func,
        bytes memory data
    ) public returns (bytes memory _result) {
        bytes4 _targetSignature = bytes4(keccak256(bytes(func)));
        uint256 _hash = uint256(
            keccak256(abi.encodePacked(_msgSender(), target, _targetSignature))
        );
        require(permissions[_hash], 'invalid-permission');
        emit Executed(_msgSender(), target, func, data);
        _result = Address.functionCall(
            target,
            bytes.concat(_targetSignature, data)
        );
    }
}

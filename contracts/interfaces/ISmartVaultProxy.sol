// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface ISmartVaultProxy {
    function addPermission(
        address caller,
        address targetAddress,
        bytes4 targetSignature
    ) external returns (bool);

    function removePermission(uint256 permissionHash) external returns (bool);

    function isWhitelisted(
        address targetAddress,
        bytes4 targetSignature
    ) external returns (bool);

    function rewardFee() external view returns (uint16);

    function rewardCollector() external view returns (address);
}

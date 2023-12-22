// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IStabilityPool {
    function liquidate() external;

    function totalDeposit() external view returns (uint256);

    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function a3aToken() external view returns (address);
}

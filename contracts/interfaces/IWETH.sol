// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IWETH {
  function deposit() external payable;

  function approve(address, uint256) external returns (bool);

  function transfer(address _to, uint256 _value) external returns (bool);

  function withdraw(uint256) external;
}

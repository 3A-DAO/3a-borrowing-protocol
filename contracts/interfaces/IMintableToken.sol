// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './IOwnable.sol';

interface IMintableToken is IERC20, IOwnable {
    function mint(address recipient, uint256 amount) external;

    function burn(uint256 amount) external;

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function approve(
        address spender,
        uint256 amount
    ) external override returns (bool);
}

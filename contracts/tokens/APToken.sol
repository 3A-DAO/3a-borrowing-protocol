// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import './MintableToken.sol';

/// @title implements minting/burning functionality for owner
contract APToken is MintableToken {
    /// @dev address of the token, it is used to be swapped against in ArbitragePool
    address public baseToken;

    // solhint-disable-next-line func-visibility
    constructor(
        string memory name,
        string memory symbol,
        address _baseToken
    ) MintableToken(name, symbol) {
        baseToken = _baseToken;
    }
}

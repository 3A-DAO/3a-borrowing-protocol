// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title A3A
 * @dev A3A is an ERC20 token representing the 3A Utility Token.
 */
contract A3A is ERC20 {
    /**
     * @dev Total supply of A3A tokens.
     */
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether;

    /**
     * @dev Constructor that mints the total supply of A3A tokens to the deployer.
     */
    constructor() ERC20("3A Utility Token", "A3A") {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}

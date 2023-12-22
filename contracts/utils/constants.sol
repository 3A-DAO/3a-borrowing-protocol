// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

/**
 * @title Constants
 * @dev This contract defines various constants used within the system.
 */
contract Constants {
    // Precision used for decimal calculations
    uint256 public constant DECIMAL_PRECISION = 1e18;

    // Reserve required for liquidation purposes
    uint256 public constant LIQUIDATION_RESERVE = 1e18;

    // Maximum value for uint256
    uint256 public constant MAX_INT = 2 ** 256 - 1;

    // Constants for percentage calculations
    uint256 public constant PERCENT = (DECIMAL_PRECISION * 1) / 100; // Represents 1%
    uint256 public constant PERCENT10 = PERCENT * 10; // Represents 10%
    uint256 public constant PERCENT_05 = PERCENT / 2; // Represents 0.5%

    // Maximum borrowing and redemption rates
    uint256 public constant MAX_BORROWING_RATE = (DECIMAL_PRECISION * 5) / 100; // Represents 5%
    uint256 public constant MAX_REDEMPTION_RATE = (DECIMAL_PRECISION * 1) / 100; // Represents 1%
}

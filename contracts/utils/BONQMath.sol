// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

/**
 * @title BONQMath
 * @dev Library implementing mathematical operations with 18-digit decimal precision.
 */
library BONQMath {
    uint256 public constant DECIMAL_PRECISION = 1e18;
    uint256 public constant MAX_INT = 2 ** 256 - 1;

    uint256 public constant MINUTE_DECAY_FACTOR = 999037758833783000;

    /**
     * @notice Returns the smaller of two numbers.
     * @param a The first number.
     * @param b The second number.
     * @return The smaller of the two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice Returns the larger of two numbers.
     * @param a The first number.
     * @param b The second number.
     * @return The larger of the two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @dev Multiply two decimal numbers and round the result using standard rounding rules.
     *  -round product up if 19'th mantissa digit >= 5
     *  -round product down if 19'th mantissa digit < 5
     * @param x The first number.
     * @param y The second number.
     * @return decProd The rounded product of x and y.
     *
     * This function is used internally inside the exponentiation, _decPow().
     */
    function decMul(uint256 x, uint256 y) internal pure returns (uint256 decProd) {
        uint256 prod_xy = x * y;

        decProd = (prod_xy + (DECIMAL_PRECISION / 2)) / DECIMAL_PRECISION;
    }

    /**
     * @notice Exponentiation function for 18-digit decimal base and integer exponent (_minutes).
     * Uses the efficient "exponentiation by squaring" algorithm with O(log(_minutes)) complexity.
     * Caps the exponent to prevent overflow. The cap 525600000 equals "minutes in 1000 years": 60 * 24 * 365 * 1000.
     * If a period of > 1000 years is ever used as an exponent in either of the above functions, the result will be
     * negligibly different from just passing the cap, since:
     * @param _base The number to be exponentially increased.
     * @param _minutes The power in minutes passed.
     * @return The result of raising _base to the power of _minutes.
     *
     * This function is called by functions representing time in units of minutes, such as IFeeRecipient.calcDecayedBaseRate.
     */
    function _decPow(uint256 _base, uint256 _minutes) internal pure returns (uint256) {
        if (_minutes > 525600000) {
            _minutes = 525600000;
        } // cap to avoid overflow

        if (_minutes == 0) {
            return DECIMAL_PRECISION;
        }

        uint256 y = DECIMAL_PRECISION;
        uint256 x = _base;
        uint256 n = _minutes;

        // Exponentiation-by-squaring
        while (n > 1) {
            if (n % 2 == 0) {
                x = decMul(x, x);
                n = n / 2;
            } else {
                // if (n % 2 != 0)
                y = decMul(x, y);
                x = decMul(x, x);
                n = (n - 1) / 2;
            }
        }

        return decMul(x, y);
    }
}

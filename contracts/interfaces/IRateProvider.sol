// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/**
 * @title IRateProvider
 * @notice Interface for getting the rate of a staking token.
 */
interface IRateProvider {
    /**
     * @notice Get the rate of the staking token.
     * @return The current rate of the staking token.
     */
    function getRate() external view returns (int256);
}

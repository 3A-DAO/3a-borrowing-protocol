// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import '../utils/constants.sol';

interface IBONQStaking {
    /* view */
    function totalStake() external view returns (uint256);

    function getRewardsTotal() external view returns (uint256);

    function getUnpaidStableCoinGain(
        address _user
    ) external view returns (uint256);

    /* state changes*/
    function stake(uint256 _amount) external;

    function unstake(uint256 _amount) external;

    function redeemReward(
        uint256 _amount,
        address _troveAddress,
        address _newNextTrove
    ) external;
}

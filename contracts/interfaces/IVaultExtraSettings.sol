// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IVaultExtraSettings {
    function setMaxRedeemablePercentage(
        uint256 _debtTreshold,
        uint256 _maxRedeemablePercentage
    ) external;
    function setRedemptionKickback(uint256 _redemptionKickback) external;

    function getExtraSettings()
        external
        view
        returns (
            uint256 _debtTreshold,
            uint256 _maxRedeemablePercentage,
            uint256 _redemptionKickback
        );
}

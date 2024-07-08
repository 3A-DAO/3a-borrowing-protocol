// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import '../interfaces/IVaultExtraSettings.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title VaultExtraSettings
 * @notice Contract to manage extra settings for a Vault
 */
contract VaultExtraSettings is IVaultExtraSettings, Ownable {
    uint256 public debtTreshold;
    uint256 public maxRedeemablePercentage;
    uint256 public redemptionKickback;

    /**
     * @dev Sets the maximum redeemable percentage for a Vault.
     * @param _debtTreshold The debt treshold for the Vault, in order to enable percentage redemption.
     * @param _maxRedeemablePercentage The maximum redeemable percentage for the Vault.
     */
    function setMaxRedeemablePercentage(
        uint256 _debtTreshold,
        uint256 _maxRedeemablePercentage
    ) external override onlyOwner {
        debtTreshold = _debtTreshold;
        maxRedeemablePercentage = _maxRedeemablePercentage;
    }

    /**
     * @dev Sets the redemption kickback for a Vault.
     * @param _redemptionKickback The redemption kickback for the Vault.
     */
    function setRedemptionKickback(
        uint256 _redemptionKickback
    ) external override onlyOwner {
        redemptionKickback = _redemptionKickback;
    }

    /**
     * @dev Retrieves the extra settings for a Vault.
     * @return _debtTreshold debt treshold for enabling max redeemable percentage, _maxRedeemablePercentage maximum redeemable percentage, _redemptionKickback redemption fee kickback to the vault
     */
    function getExtraSettings()
        external
        view
        override
        returns (
            uint256 _debtTreshold,
            uint256 _maxRedeemablePercentage,
            uint256 _redemptionKickback
        )
    {
        return (debtTreshold, maxRedeemablePercentage, redemptionKickback);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IVaultFactoryConfig {
    event PriceFeedUpdated(address indexed priceFeed);
    event MaxTokensPerVaultUpdated(uint256 oldMaxTokensPerVault, uint256 newMaxTokensPerVault);
    event RedemptionRateUpdated(uint256 oldRedemptionRate, uint256 newRedemptionRate);
    event BorrowRateUpdated(uint256 oldBorrowRate, uint256 newBorrowRate);
    event RedemptionHealthFactorLimitUpdated(uint256 oldRedemptionHealthFactorLimit, uint256 newRedemptionHealthFactorLimit);

    function setMaxTokensPerVault(uint256 _maxTokensPerVault) external;
    function setPriceFeed(address _priceFeed) external;
    function setRedemptionRate(uint256 _redemptionRate) external;
    function setBorrowRate(uint256 _borrowRate) external;
    function setRedemptionHealthFactorLimit(uint256 _redemptionHealthFactorLimit) external;
    function setBorrowFeeRecipient(address _borrowFeeRecipient) external;
    function setRedemptionFeeRecipient(address _redemptionFeeRecipient) external;

    function priceFeed() external view returns (address);
    function MAX_TOKENS_PER_VAULT() external view returns (uint256);
    function redemptionRate() external view returns (uint256);
    function borrowRate() external view returns (uint256);
    function redemptionHealthFactorLimit() external view returns (uint256);
    function borrowFeeRecipient() external view returns (address);
    function redemptionFeeRecipient() external view returns (address);
}
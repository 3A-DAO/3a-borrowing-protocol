// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;
import "./utils/constants.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract VaultFactoryConfig is Constants, Ownable {
    event PriceFeedUpdated(address indexed priceFeed);
    event MaxTokensPerVaultUpdated(uint256 oldMaxTokensPerVault, uint256 newMaxTokensPerVault);
    event RedemptionRateUpdated(uint256 oldRedemptionRate, uint256 newRedemptionRate);
    event BorrowRateUpdated(address oldBorrowRate, address newBorrowRate);
    event RedemptionHealthFactorLimitUpdated(uint256 oldRedemptionHealthFactorLimit, uint256 newRedemptionHealthFactorLimit);
    event DebtCeilingUpdated(uint256 oldDebtCeiling, uint256 newDebtCeiling);
    event MaxDebtPerWindowUpdated(uint256 oldMaxDebtPerWindow, uint256 newMaxDebtPerWindow);
    event DebtWindowSizeUpdated(uint256 oldDebtWindowSize, uint256 newDebtWindowSize);
    event CollateralCapacityUpdated(address indexed collateral, uint256 oldCapacity, uint256 newCapacity);
    event liquidationRouterUpdated(address indexed liquidationRouter);

    // Various configuration parameters
    address public priceFeed;
    address public borrowRate;

    uint256 public MAX_TOKENS_PER_VAULT = 5;
    uint256 public redemptionRate = PERCENT_05; // 0.5%

    uint256 public redemptionHealthFactorLimit = 1.5 ether; // 2.0 HF

    address public borrowFeeRecipient;
    address public redemptionFeeRecipient;

    mapping(address => uint256) public collateralCap;

    uint256 public debtCeiling = type(uint256).max; // max stablecoin debt issued by the protocol

    uint256 public maxDebtPerWindow = 2000 ether; // 1M
    uint256 public debtWindowSize = 1 hours;
    uint256 public lastDebtWindow;
    uint256 public debtWindowAmount;

    address public vaultDeployer;
    address public liquidationRouter;

    /**
     * @dev Set the address for the Vault Deployer
     * @param _vaultDeployer Address of the Vault Deployer
     */
    function setVaultDeployer(address _vaultDeployer) external onlyOwner {
        require(_vaultDeployer != address(0x0), "vault-deployer-is-0");
        vaultDeployer = _vaultDeployer;
    }

    /**
     * @dev Set the address for the Liquidation Router
     * @param _liquidationRouter Address of the Liquidation Router
     */
    function setLiquidationRouter(address _liquidationRouter) external onlyOwner {
        require(_liquidationRouter != address(0x0), "liquidation-router-is-0");
        liquidationRouter = _liquidationRouter;
        emit liquidationRouterUpdated(_liquidationRouter);
    }

    /**
     * @dev Set the collateral capacity for a specific collateral token
     * @param _collateral Address of the collateral token
     * @param _cap The new capacity for the collateral token
     */
    function setCollateralCapacity(address _collateral, uint256 _cap) external onlyOwner {
        require(_collateral != address(0x0), "collateral-is-0");
        emit CollateralCapacityUpdated(_collateral, collateralCap[_collateral], _cap);
        collateralCap[_collateral] = _cap;
    }

    /**
     * @dev Set the debt ceiling value.
     * @param _debtCeiling The new debt ceiling value to be set.
     */
    function setDebtCeiling(uint256 _debtCeiling) external onlyOwner {
        emit DebtCeilingUpdated(debtCeiling, _debtCeiling);
        debtCeiling = _debtCeiling;
    }

    /**
     * @dev Set the maximum debt allowed per window.
     * @param _maxDebtPerWindow The new maximum debt per window value to be set.
     */
    function setMaxDebtPerWindow(uint256 _maxDebtPerWindow) external onlyOwner {
        emit MaxDebtPerWindowUpdated(maxDebtPerWindow, _maxDebtPerWindow);
        maxDebtPerWindow = _maxDebtPerWindow;
    }

    /**
     * @dev Set the window size for debt.
     * @param _debtWindowSize The new debt window size value to be set.
     */
    function setDebtWindowSize(uint256 _debtWindowSize) external onlyOwner {
        emit DebtWindowSizeUpdated(debtWindowSize, _debtWindowSize);
        debtWindowSize = _debtWindowSize;
    }

    /**
     * @dev Set the maximum tokens allowed per vault.
     * @param _maxTokensPerVault The new maximum tokens per vault value to be set.
     */
    function setMaxTokensPerVault(uint256 _maxTokensPerVault) external onlyOwner {
        require(_maxTokensPerVault > 0, "max-tokens-per-vault-is-0");
        emit MaxTokensPerVaultUpdated(MAX_TOKENS_PER_VAULT, _maxTokensPerVault);
        MAX_TOKENS_PER_VAULT = _maxTokensPerVault;
    }

    /**
     * @dev Set the address for the price feed.
     * @param _priceFeed Address of the new price feed contract.
     */
    function setPriceFeed(address _priceFeed) external onlyOwner {
        require(_priceFeed != address(0x0), "pricefeed-is-0");
        priceFeed = _priceFeed;
        emit PriceFeedUpdated(_priceFeed);
    }

    /**
     * @dev Set the redemption rate for the protocol.
     * @param _redemptionRate The new redemption rate value to be set.
     */
    function setRedemptionRate(uint256 _redemptionRate) external onlyOwner {
        require(_redemptionRate <= MAX_REDEMPTION_RATE, "redemption-rate-too-high");
        emit RedemptionRateUpdated(redemptionRate, _redemptionRate);
        redemptionRate = _redemptionRate;
    }

    /**
     * @dev Set the address for the borrow rate.
     * @param _borrowRate Address of the new borrow rate contract.
     */
    function setBorrowRate(address _borrowRate) external onlyOwner {
        require(_borrowRate != address(0), "borrow-rate-is-0");
        emit BorrowRateUpdated(borrowRate, _borrowRate);
        borrowRate = _borrowRate;
    }

    /**
     * @dev Set the redemption health factor limit.
     * @param _redemptionHealthFactorLimit The new redemption health factor limit to be set.
     */
    function setRedemptionHealthFactorLimit(uint256 _redemptionHealthFactorLimit) external onlyOwner {
        emit RedemptionHealthFactorLimitUpdated(redemptionHealthFactorLimit, _redemptionHealthFactorLimit);
        redemptionHealthFactorLimit = _redemptionHealthFactorLimit;
    }

    /**
     * @dev Set the address for the borrow fee recipient.
     * @param _borrowFeeRecipient Address of the new borrow fee recipient.
     */
    function setBorrowFeeRecipient(address _borrowFeeRecipient) external onlyOwner {
        require(_borrowFeeRecipient != address(0x0), "borrow-fee-recipient-is-0");
        borrowFeeRecipient = _borrowFeeRecipient;
    }

    /**
     * @dev Set the address for the redemption fee recipient.
     * @param _redemptionFeeRecipient Address of the new redemption fee recipient.
     */
    function setRedemptionFeeRecipient(address _redemptionFeeRecipient) external onlyOwner {
        require(_redemptionFeeRecipient != address(0x0), "redemption-fee-recipient-is-0");
        redemptionFeeRecipient = _redemptionFeeRecipient;
    }

    /**
     * @dev Constructor to initialize the configuration settings upon deployment
     * @param _vaultDeployer Address of the Vault Deployer
     * @param _liquidationRouter Address of the Liquidation Router
     */
    constructor(address _vaultDeployer, address _liquidationRouter) {
        require(_vaultDeployer != address(0x0), "vault-deployer-is-0");
        require(_liquidationRouter != address(0x0), "liquidation-factory-is-0");
        vaultDeployer = _vaultDeployer;
        borrowFeeRecipient = _msgSender();
        redemptionFeeRecipient = _msgSender();
        lastDebtWindow = block.timestamp;
        liquidationRouter = _liquidationRouter;
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./utils/linked-address-list.sol";
import "./Vault.sol";
import "./VaultFactoryConfig.sol";
import "./VaultFactoryList.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/ITokenPriceFeed.sol";
import "./interfaces/IPriceFeed.sol";
import "./interfaces/IMintableTokenOwner.sol";
import "./interfaces/IMintableToken.sol";
import "./interfaces/IVaultDeployer.sol";
import "./interfaces/IVaultBorrowRate.sol";

/**
 * @title VaultFactory
 * @dev Manages the creation, configuration, and operations of Vaults with collateral and borrowing functionality.
 */
contract VaultFactory is ReentrancyGuard, VaultFactoryConfig, VaultFactoryList {
    // Events emitted by the contract
    event NewVault(address indexed vault, string name, address indexed owner);
    event VaultOwnerChanged(address indexed vault, address indexed oldOwner, address indexed newOwner);

    // Libraries used by the contract
    using LinkedAddressList for LinkedAddressList.List;
    using SafeERC20 for IERC20;
    using SafeERC20 for IMintableToken;

    // Immutable state variables
    address public immutable stable;
    address public immutable nativeWrapped;
    IMintableTokenOwner public immutable mintableTokenOwner;

    // State variables
    mapping(address => uint256) public collateral;
    uint256 public totalDebt;

    /**
     * @dev Constructor to initialize essential addresses and contracts for VaultFactory.
     * @param _mintableTokenOwner Address of the Mintable Token Owner contract.
     * @param _nativeWrapped Address of the native wrapped token.
     * @param _priceFeed Address of the price feed contract.
     * @param _vaultDeployer Address of the Vault Deployer contract.
     * @param _liquidationRouter Address of the liquidation router contract.
     * @param _borrowRate Address of the borrow rate contract.
     */
    constructor(
        address _mintableTokenOwner,
        address _nativeWrapped,
        address _priceFeed,
        address _vaultDeployer,
        address _liquidationRouter,
        address _borrowRate
    ) VaultFactoryConfig(_vaultDeployer, _liquidationRouter) {
        require(_mintableTokenOwner != address(0x0), "mintable-token-owner-is-0");

        mintableTokenOwner = IMintableTokenOwner(_mintableTokenOwner);
        stable = address(mintableTokenOwner.token());

        require(stable != address(0x0), "stable-is-0");
        require(_nativeWrapped != address(0x0), "nativew-is-0");
        require(_priceFeed != address(0x0), "pricefeed-is-0");
        require(_borrowRate != address(0x0), "borrow-rate-is-0");

        borrowRate = _borrowRate;
        nativeWrapped = _nativeWrapped;
        priceFeed = _priceFeed;
    }

    /**
     * @dev Fallback function to receive Ether and restricts its usage to a designated sender.
     */
    receive() external payable {
        require(msg.sender == nativeWrapped, "only-native-wrapped");
    }

    /**
     * @dev Modifier: Allows function execution only by the owner of a specific vault.
     * @param _vault The address of the vault to check ownership.
     */
    modifier onlyVaultOwner(address _vault) {
        require(Vault(_vault).vaultOwner() == _msgSender(), "only-vault-owner");
        _;
    }

    /**
     * @dev Modifier: Allows function execution by the owner or an operator of a specific vault.
     * @param _vault The address of the vault to check ownership or operator status.
     */
    modifier onlyVaultOwnerOrOperator(address _vault) {
        require(
            Vault(_vault).vaultOwner() == _msgSender() || Vault(_vault).isOperator(_msgSender()),
            "only-vault-owner-or-operator"
        );
        _;
    }

    /**
     * @dev Modifier: Allows function execution only by the liquidation router.
     */
    modifier onlyLiquidationRouter() {
        require(liquidationRouter == _msgSender(), "only-liquidation-router");
        _;
    }

    /**
     * @dev Checks if a given collateral token is supported.
     * @param _collateral The address of the collateral token.
     * @return A boolean indicating whether the collateral token is supported.
     */
    function isCollateralSupported(address _collateral) external view returns (bool) {
        return _isCollateralSupported(_collateral);
    }

    /**
     * @dev Transfers ownership of a vault to a new owner.
     * @param _vault The address of the vault to transfer ownership.
     * @param _newOwner The address of the new owner to receive the vault ownership.
     */
    function transferVaultOwnership(address _vault, address _newOwner) external onlyVaultOwner(_vault) {
        address _msgSender = _msgSender();
        require(_newOwner != address(0x0), "new-owner-is-0");
        require(containsVault(_vault), "vault-not-found");

        emit VaultOwnerChanged(_vault, _msgSender, _newOwner);
        Vault(_vault).transferVaultOwnership(_newOwner);
        _transferVault(_msgSender, _newOwner, _vault);
    }

    /**
     * @dev Creates a new vault with a specified name.
     * @param _name The name of the new vault.
     * @return The address of the newly created vault.
     */
    function createVault(string memory _name) public returns (address) {
        address _msgSender = _msgSender();
        address _vaultAddress = IVaultDeployer(vaultDeployer).deployVault(address(this), _msgSender, _name);
        _addVault(_msgSender, _vaultAddress);
        emit NewVault(_vaultAddress, _name, _msgSender);

        return _vaultAddress;
    }

    /**
     * @dev Checks if a specific collateral token is supported for the vault.
     * @param _collateral The address of the collateral token to check.
     * @return A boolean indicating whether the collateral token is supported.
     */
    function _isCollateralSupported(address _collateral) internal view returns (bool) {
        ITokenPriceFeed _priceFeed = ITokenPriceFeed(priceFeed);
        return (_priceFeed.tokenPriceFeed(_collateral) != address(0x0));
    }

    /**
     * @dev Adds native-wrapped collateral to a specific vault.
     * @param _vault The address of the vault to add collateral.
     */
    function addCollateralNative(address _vault) external payable {
        require(containsVault(_vault), "vault-not-found");
        require(_isCollateralSupported(nativeWrapped), "collateral-not-supported");
        uint256 _amount = msg.value;

        collateral[nativeWrapped] += _amount;

        require(collateral[nativeWrapped] <= collateralCap[nativeWrapped], "collateral-cap-reached");

        IWETH(nativeWrapped).deposit{value: _amount}();
        IERC20(nativeWrapped).safeTransferFrom(address(this), _vault, _amount);

        Vault(_vault).addCollateral(nativeWrapped, _amount);
    }

    /**
     * @dev Removes native-wrapped collateral from a specific vault.
     * @param _vault The address of the vault to remove collateral.
     * @param _amount The amount of collateral to be removed.
     * @param _to The address where the removed collateral is transferred.
     */
    function removeCollateralNative(address _vault, uint256 _amount, address _to) external onlyVaultOwner(_vault) {
        require(containsVault(_vault), "vault-not-found");
        require(_isCollateralSupported(nativeWrapped), "collateral-not-supported");

        Vault(_vault).removeCollateral(nativeWrapped, _amount, address(this));

        collateral[nativeWrapped] -= _amount;

        IWETH(nativeWrapped).withdraw(_amount);
        _to.call{value: _amount};
    }

    /**
     * @dev Adds a specific collateral to a vault.
     * @param _vault The address of the vault to add collateral.
     * @param _collateral The address of the collateral token to add.
     * @param _amount The amount of collateral to add.
     */
    function addCollateral(address _vault, address _collateral, uint256 _amount) external {
        require(containsVault(_vault), "vault-not-found");
        require(_isCollateralSupported(_collateral), "collateral-not-supported");

        collateral[_collateral] += _amount;

        require(collateral[_collateral] <= collateralCap[_collateral], "collateral-cap-reached");

        IERC20(_collateral).safeTransferFrom(_msgSender(), _vault, _amount);
        Vault(_vault).addCollateral(_collateral, _amount);
    }

    /**
     * @dev Removes a specific collateral from a vault.
     * @param _vault The address of the vault to remove collateral.
     * @param _collateral The address of the collateral token to remove.
     * @param _amount The amount of collateral to remove.
     * @param _to The address where the removed collateral is transferred.
     */
    function removeCollateral(
        address _vault,
        address _collateral,
        uint256 _amount,
        address _to
    ) external onlyVaultOwner(_vault) {
        require(containsVault(_vault), "vault-not-found");
        require(_isCollateralSupported(_collateral), "collateral-not-supported");

        collateral[_collateral] -= _amount;
        Vault(_vault).removeCollateral(_collateral, _amount, _to);
    }

    /**
     * @dev Borrows funds from a vault by its owner or an operator.
     * @param _vault The address of the vault from which funds are borrowed.
     * @param _amount The amount of funds to borrow.
     * @param _to The address where borrowed funds are sent.
     */
    function borrow(address _vault, uint256 _amount, address _to) external onlyVaultOwnerOrOperator(_vault) {
        require(containsVault(_vault), "vault-not-found");
        require(_to != address(0x0), "to-is-0");

        totalDebt += _amount;
        _updateDebtWindow(_amount);
        Vault(_vault).borrow(_amount);
        uint256 _borrowRate = IVaultBorrowRate(borrowRate).getBorrowRate(_vault);
        uint256 _feeAmount = (_amount * _borrowRate) / DECIMAL_PRECISION;

        mintableTokenOwner.mint(_to, _amount - _feeAmount);
        mintableTokenOwner.mint(borrowFeeRecipient, _feeAmount);
    }

    /**
     * @dev Distributes bad debt to a specific vault.
     * @param _vault The address of the vault to distribute bad debt.
     * @param _amount The amount of bad debt to be distributed.
     */
    function distributeBadDebt(address _vault, uint256 _amount) external nonReentrant onlyLiquidationRouter {
        require(containsVault(_vault), "vault-not-found");
        totalDebt += _amount;
        Vault(_vault).addBadDebt(_amount);
    }

    /**
     * @dev Closes a vault if it meets specific conditions.
     * @param _vault The address of the vault to close.
     */
    function closeVault(address _vault) external onlyVaultOwner(_vault) {
        require(containsVault(_vault), "vault-not-found");
        require(Vault(_vault).debt() == 0, "debt-not-0");
        require(Vault(_vault).collateralsLength() == 0, "collateral-not-0");

        _removeVault(_msgSender(), _vault);
    }

    /**
     * @dev Repays borrowed funds for a specific vault.
     * @param _vault The address of the vault for which funds are repaid.
     * @param _amount The amount of funds to repay.
     */
    function repay(address _vault, uint256 _amount) external {
        require(containsVault(_vault), "vault-not-found");
        totalDebt -= _amount;
        Vault(_vault).repay(_amount);

        IMintableToken(stable).safeTransferFrom(_msgSender(), address(this), _amount);
        IMintableToken(stable).burn(_amount);
    }

    /**
     * @dev Redeems collateral from a vault after meeting specific conditions.
     * @param _vault The address of the vault from which collateral is redeemed.
     * @param _collateral The address of the collateral token to redeem.
     * @param _collateralAmount The amount of collateral to redeem.
     * @param _to The address where the redeemed collateral is transferred.
     */
    function redeem(address _vault, address _collateral, uint256 _collateralAmount, address _to) external nonReentrant {
        require(containsVault(_vault), "vault-not-found");
        require(_to != address(0x0), "to-is-0");

        require(isReedemable(_vault, _collateral), "not-redeemable");

        (uint256 _debtRepaid, uint256 _feeCollected) = Vault(_vault).redeem(_collateral, _collateralAmount);

        totalDebt -= _debtRepaid;
        collateral[_collateral] -= _collateralAmount;

        IMintableToken(stable).safeTransferFrom(_msgSender(), address(this), _debtRepaid + _feeCollected);
        IMintableToken(stable).burn(_debtRepaid);
        IMintableToken(stable).transfer(redemptionFeeRecipient, _feeCollected);

        IERC20(_collateral).safeTransfer(_to, _collateralAmount);
    }

    /**
     * @dev Liquidates a specific vault if it is eligible for liquidation.
     * @param _vault The address of the vault to be liquidated.
     */
    function liquidate(address _vault) external nonReentrant {
        require(containsVault(_vault), "vault-not-found");

        address _vaultOwner = Vault(_vault).vaultOwner();
        uint256 _forgivenDebt = Vault(_vault).liquidate();

        totalDebt -= _forgivenDebt;

        _removeVault(_vaultOwner, _vault);
    }

    /**
     * @dev Checks if a vault is eligible for liquidation.
     * @param _vault The address of the vault to check for liquidation eligibility.
     * @return A boolean indicating whether the vault is liquidatable.
     */
    function isLiquidatable(address _vault) external view returns (bool) {
        require(containsVault(_vault), "vault-not-found");
        return Vault(_vault).healthFactor(true) < DECIMAL_PRECISION;
    }

    /**
     * @dev Checks if a specific collateral can be redeemed from a vault based on conditions.
     * @param _vault The address of the vault to check for collateral redemption.
     * @param _collateral The address of the collateral token to check for redemption.
     * @notice Collateral with higher MCR can be redeemed first
     * @return A boolean indicating whether the collateral is redeemable.
     */
    function isReedemable(address _vault, address _collateral) public view returns (bool) {
        require(_isCollateralSupported(_collateral), "collateral-not-supported");
        if (!Vault(_vault).containsCollateral(_collateral)) {
            return false;
        }
        uint256 _healthFactor = Vault(_vault).healthFactor(false);
        if (_healthFactor >= redemptionHealthFactorLimit) {
            return false;
        }

        ITokenPriceFeed _priceFeed = ITokenPriceFeed(priceFeed);
        uint256 _collateralMcr = _priceFeed.mcr(_collateral);

        address[] memory _collaterals = Vault(_vault).collaterals();
        uint256 _length = _collaterals.length;

        for (uint256 i; i < _length; i++) {
            if (_collaterals[i] != _collateral) {
                uint256 _mcr = _priceFeed.mcr(_collaterals[i]);
                if (_mcr > _collateralMcr) {
                    return false;
                }
            }
        }
        return true;
    }

    /**
     * @dev Updates the debt window with the newly incurred debt.
     * @param _newDebt The amount of new debt to update in the debt window.
     */
    function _updateDebtWindow(uint256 _newDebt) internal {
        require(totalDebt <= debtCeiling, "debt-ceiling-reached");

        if (block.timestamp > lastDebtWindow + debtWindowSize) {
            debtWindowAmount = _newDebt;
            lastDebtWindow = block.timestamp;
        } else {
            debtWindowAmount += _newDebt;
        }
        require(debtWindowAmount <= maxDebtPerWindow, "debt-window-amount-reached");
    }
}

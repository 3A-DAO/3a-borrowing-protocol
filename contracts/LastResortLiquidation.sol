// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/IVault.sol";
import "./interfaces/IVaultFactory.sol";
import "./interfaces/IStabilityPool.sol";
import "./interfaces/IAuctionManager.sol";
import "./interfaces/IMintableToken.sol";
import "./interfaces/ILiquidationRouter.sol";

/**
 * @title LastResortLiquidation
 * @dev Contract to manage collateral and bad debt distribution for liquidation.
 */
contract LastResortLiquidation is Ownable, ReentrancyGuard {
    event VaultFactoryUpdated(address indexed _vaultFactory);

    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;
    using SafeERC20 for IMintableToken;

    EnumerableSet.AddressSet private collateralSet;
    EnumerableSet.AddressSet private allowedSet;

    address public vaultFactory;

    mapping(address => uint256) public collateral;

    uint256 public badDebt;

    modifier onlyAllowed() {
        require(allowedSet.contains(msg.sender), "not-allowed");
        _;
    }

    /**
     * @dev Adds an address to the allowed set.
     * @param _allowed The address to add to the allowed set.
     */
    function addAllowed(address _allowed) external onlyOwner {
        require(_allowed != address(0x0), "allowed-is-0");
        allowedSet.add(_allowed);
    }

    /**
     * @dev Removes an address from the allowed set.
     * @param _allowed The address to remove from the allowed set.
     */
    function removeAllowed(address _allowed) external onlyOwner {
        require(_allowed != address(0x0), "allowed-is-0");
        allowedSet.remove(_allowed);
    }

    /**
     * @dev Gets the number of addresses in the allowed set.
     * @return The number of addresses in the allowed set.
     */
    function allowedLength() external view returns (uint256) {
        return allowedSet.length();
    }

    /**
     * @dev Gets the address at the specified index in the allowed set.
     * @param _index The index of the address.
     * @return The address at the specified index in the allowed set.
     */
    function allowedAt(uint256 _index) external view returns (address) {
        return allowedSet.at(_index);
    }

    /**
     * @dev Gets the number of addresses in the collateral set.
     * @return The number of addresses in the collateral set.
     */
    function collateralLength() external view returns (uint256) {
        return collateralSet.length();
    }

    /**
     * @dev Gets the address at the specified index in the collateral set.
     * @param _index The index of the address.
     * @return The address at the specified index in the collateral set.
     */
    function collateralAt(uint256 _index) external view returns (address) {
        return collateralSet.at(_index);
    }

    /**
     * @dev Sets the address of the vault factory.
     * @param _vaultFactory Address of the vault factory.
     */
    function setVaultFactory(address _vaultFactory) external onlyOwner {
        require(_vaultFactory != address(0x0), "vault-factory-is-0");
        vaultFactory = _vaultFactory;
        emit VaultFactoryUpdated(_vaultFactory);
    }

    /**
     * @dev Adds collateral to the contract and updates the collateral balance.
     * @param _collateral The address of the collateral token.
     * @param _amount The amount of collateral to add.
     */
    function addCollateral(address _collateral, uint256 _amount) external onlyAllowed {
        require(_collateral != address(0x0), "collateral-is-0");
        require(_amount > 0, "amount-is-0");

        collateralSet.add(_collateral);
        IERC20(_collateral).safeTransferFrom(msg.sender, address(this), _amount);

        collateral[_collateral] += _amount;
    }

    /**
     * @dev Withdraws collateral from the contract.
     * @param _collateral The address of the collateral token.
     * @param _amount The amount of collateral to withdraw.
     * @param _to The address to receive the withdrawn collateral.
     */
    function withdrawCollateral(address _collateral, uint256 _amount, address _to) external onlyOwner {
        require(_collateral != address(0x0), "collateral-is-0");
        require(_amount > 0, "amount-is-0");

        collateral[_collateral] -= _amount;

        if (collateral[_collateral] == 0) collateralSet.remove(_collateral);

        IERC20(_collateral).safeTransfer(_to, _amount);
    }

    /**
     * @dev Adds bad debt to the contract.
     * @param _amount The amount of bad debt to add.
     */
    function addBadDebt(uint256 _amount) external onlyAllowed {
        require(_amount > 0, "amount-is-0");
        badDebt += _amount;
    }

    /**
     * @dev Repays bad debt by burning stable tokens.
     * @param _amount The amount of stable tokens to burn.
     */
    function repayBadDebt(uint256 _amount) external onlyOwner {
        require(_amount > 0, "amount-is-0");
        require(_amount <= badDebt, "amount-too-high");

        IMintableToken _stable = IMintableToken(IVaultFactory(vaultFactory).stable());
        _stable.safeTransferFrom(msg.sender, address(this), _amount);
        _stable.burn(_amount);

        badDebt -= _amount;
    }

    /**
     * @dev Distributes bad debt to a specific vault.
     * @param _vault The address of the vault to receive the bad debt.
     * @param _amount The amount of bad debt to distribute.
     */
    function distributeBadDebt(address _vault, uint256 _amount) external onlyOwner {
        require(_vault != address(0x0), "vault-is-0");
        require(_amount > 0, "amount-is-0");
        require(_amount <= badDebt, "amount-too-high");
        badDebt -= _amount;
        IVaultFactory _vaultFactory = IVaultFactory(vaultFactory);
        ILiquidationRouter _liquidationRouter = ILiquidationRouter(_vaultFactory.liquidationRouter());
        _liquidationRouter.distributeBadDebt(_vault, _amount);
    }
}

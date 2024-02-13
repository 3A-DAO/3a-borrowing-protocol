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

/**
 * @title LiquidationRouter
 * @dev Handles liquidation and redistribution of collaterals and debts in the system.
 */
contract LiquidationRouter is Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    using SafeERC20 for IERC20;
    event SeizedCollateralAdded(
        address indexed collateral,
        address indexed _vaultFactory,
        address indexed _vault,
        uint256 amount
    );
    event UnderWaterDebtAdded(address indexed _vaultFactory, address indexed _vault, uint256 debtAmount);
    event UnderWaterDebtRemoved(address indexed _vaultFactory, uint256 debtAmount);
    event VaultFactoryUpdated(address indexed _vaultFactory);
    event StabilityPoolUpdated(address indexed _stabilityPool);
    event AuctionManagerUpdated(address indexed _auctionManager);
    event LastResortLiquidationUpdated(address indexed _lastResortLiquidation);
    event BadDebtDistributed(address indexed _vault, uint256 amount);

    uint256 public underWaterDebt;

    address public vaultFactory;
    address public stabilityPool;
    address public auctionManager;
    address public lastResortLiquidation;

    EnumerableSet.AddressSet private collateralSet;

    mapping(address => uint256) public collateral;

    /**
     * @dev Sets the last resort liquidation contract address.
     * @param _lastResortLiquidation Address of the last resort liquidation contract.
     */
    function setLastResortLiquidation(address _lastResortLiquidation) external onlyOwner {
        require(_lastResortLiquidation != address(0x0), "last-resort-liquidation-is-0");
        lastResortLiquidation = _lastResortLiquidation;
        emit LastResortLiquidationUpdated(_lastResortLiquidation);
    }

    /**
     * @dev Sets the stability pool contract address.
     * @param _stabilityPool Address of the stability pool contract.
     */
    function setStabilityPool(address _stabilityPool) external onlyOwner {
        require(_stabilityPool != address(0x0), "stability-pool-is-0");
        stabilityPool = _stabilityPool;
        emit StabilityPoolUpdated(_stabilityPool);
    }

    /**
     * @dev Sets the auction manager contract address.
     * @param _auctionManager Address of the auction manager contract.
     */
    function setAuctionManager(address _auctionManager) external onlyOwner {
        require(_auctionManager != address(0x0), "auction-manager-is-0");
        auctionManager = _auctionManager;
        emit AuctionManagerUpdated(_auctionManager);
    }

    modifier onlyVault() {
        require(IVaultFactory(vaultFactory).containsVault(msg.sender), "not-a-vault");
        _;
    }

    modifier onlyAllowed() {
        require(msg.sender == stabilityPool, "not-allowed");
        _;
    }

    modifier onlyLastResortLiquidation() {
        require(msg.sender == lastResortLiquidation, "not-last-resort-liquidation");
        _;
    }

    /**
     * @dev Checks if a specific collateral token is registered.
     * @param _collateral Address of the collateral token to check.
     * @return bool indicating the presence of the collateral token.
     */
    function containsCollateral(address _collateral) external view returns (bool) {
        return collateralSet.contains(_collateral);
    }

    /**
     * @dev Returns the count of registered collateral tokens.
     * @return uint256 representing the count of collateral tokens.
     */
    function collateralsLength() external view returns (uint256) {
        return collateralSet.length();
    }

    /**
     * @dev Gets the collateral token at a specific index in the list of registered collaterals.
     * @param _index Index of the collateral token.
     * @return address representing the collateral token address.
     */
    function collateralAt(uint256 _index) external view returns (address) {
        return collateralSet.at(_index);
    }

    /**
     * @dev Gets all the registered collateral tokens.
     * @return address[] memory representing the list of collateral token addresses.
     */
    function collaterals() external view returns (address[] memory) {
        address[] memory _collaterals = new address[](collateralSet.length());
        for (uint256 i = 0; i < collateralSet.length(); i++) {
            _collaterals[i] = collateralSet.at(i);
        }
        return _collaterals;
    }

    /**
     * @dev Sets the vault factory contract address.
     * @param _vaultFactory Address of the vault factory contract.
     */
    function setVaultFactory(address _vaultFactory) external onlyOwner {
        require(_vaultFactory != address(0x0), "vault-factory-is-0");
        require(IVaultFactory(_vaultFactory).liquidationRouter() == address(this), "wrong-liquidation-router");
        vaultFactory = _vaultFactory;
        emit VaultFactoryUpdated(_vaultFactory);
    }

    /**
     * @dev Adds seized collateral to the contract.
     * @param _collateral Address of the seized collateral.
     * @param _amount Amount of seized collateral.
     */
    function addSeizedCollateral(address _collateral, uint256 _amount) external onlyVault {
        IERC20(_collateral).safeTransferFrom(msg.sender, address(this), _amount);

        IERC20(_collateral).safeApprove(stabilityPool, 0);
        IERC20(_collateral).safeApprove(stabilityPool, _amount);

        IERC20(_collateral).safeApprove(auctionManager, 0);
        IERC20(_collateral).safeApprove(auctionManager, _amount);

        collateralSet.add(_collateral);
        collateral[_collateral] += _amount;
        emit SeizedCollateralAdded(_collateral, vaultFactory, msg.sender, _amount);
    }

    /**
     * @dev Adds underwater debt for a vault and increases the total underwater debt for the system.
     * @param _vault Address of the vault.
     * @param _amount Amount of underwater debt.
     */
    function addUnderWaterDebt(address _vault, uint256 _amount) external onlyVault {
        underWaterDebt += _amount;
        emit UnderWaterDebtAdded(vaultFactory, _vault, _amount);
    }

    /**
     * @dev Removes underwater debt from the system and decreases the total underwater debt.
     * @param _amount Amount of underwater debt to be removed.
     */
    function _removeUnderWaterDebt(uint256 _amount) internal {
        underWaterDebt -= _amount;
        emit UnderWaterDebtRemoved(vaultFactory, _amount);
    }

    /**
     * @dev Withdraws liquidated collateral.
     * @param _collateral Address of the liquidated collateral.
     * @param _to Address to receive the liquidated collateral.
     * @param _amount Amount of liquidated collateral to withdraw.
     */
    function withdrawLiquidatedCollateral(address _collateral, address _to, uint256 _amount) external onlyOwner {
        IERC20(_collateral).safeTransfer(_to, _amount);
        collateral[_collateral] -= _amount;
        if (collateral[_collateral] == 0) {
            collateralSet.remove(_collateral);
        }
    }

    /**
     * @dev Removes all collaterals from the contract.
     * This function sets the collateral amount for each collateral token to 0.
     */
    function _removeAllCollaterals() internal {
        uint256 _length = collateralSet.length();
        for (uint256 i; i < _length; i++) {
            address _collateral = collateralSet.at(i);
            collateral[_collateral] = 0;
        }
    }

    /**
     * @dev Initiates liquidation or auction if necessary.
     */
    function tryLiquidate() external nonReentrant {
        require(underWaterDebt > 0, "no-underwater-debt");
        uint256 _stabilityPoolDeposit = IStabilityPool(stabilityPool).totalDeposit();
        if (_stabilityPoolDeposit >= underWaterDebt) {
            IStabilityPool(stabilityPool).liquidate();
        } else {
            IAuctionManager(auctionManager).newAuction();
        }
        _removeAllCollaterals();
        _removeUnderWaterDebt(underWaterDebt);
    }

    /**
     * @dev Distributes bad debt in the system.
     * @param _vault Address of the vault with bad debt.
     * @param _amount Amount of bad debt to distribute.
     */
    function distributeBadDebt(address _vault, uint256 _amount) external onlyLastResortLiquidation {
        IVaultFactory(vaultFactory).distributeBadDebt(_vault, _amount);
        emit BadDebtDistributed(_vault, _amount);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

// OpenZeppelin imports
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// Interfaces
import "../interfaces/IPriceFeed.sol";
import "../interfaces/IVaultFactory.sol";
import "../interfaces/IVaultFactoryConfig.sol";
import "../interfaces/ILiquidationRouter.sol";
import "../interfaces/IStabilityPool.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IMintableToken.sol";
import "../interfaces/ITokenPriceFeed.sol";
import "../utils/constants.sol";
import "../utils/linked-address-list.sol";

/**
 * @title VaultOptimizerBot
 * @notice A smart contract managing operations for vault optimization
 * @dev This contract allows borrowing, depositing, withdrawing, repaying, and transferring tokens for vault optimization.
 */
contract VaultOptimizerBot is Context, Constants, Ownable {
    string public constant VERSION = "1.0.0";
    using SafeERC20 for IERC20;
    using SafeERC20 for IMintableToken;

    IVaultFactory public vaultFactory;
    IStabilityPool public stabilityPool;
    IMintableToken public stable;
    IERC20 public a3aToken;

    /**
     * @dev Constructor to set up the VaultOptimizerBot contract
     * @param _vaultFactory Address of the VaultFactory contract
     * @param _stabilityPool Address of the StabilityPool contract
     */
    constructor(address _vaultFactory, address _stabilityPool) {
        require(_vaultFactory != address(0x0), "vault-factory-is-0");
        require(_stabilityPool != address(0x0), "stability-pool-is-0");
        vaultFactory = IVaultFactory(_vaultFactory);
        stabilityPool = IStabilityPool(_stabilityPool);
        a3aToken = IERC20(stabilityPool.a3aToken());
        stable = IMintableToken(vaultFactory.stable());
    }

    /**
     * @dev Borrows tokens from the Vault and deposits them into the Stability Pool
     * @param _vault Address of the Vault to borrow from
     * @param _amount Amount of tokens to borrow and deposit
     */
    function borrowAndDeposit(address _vault, uint256 _amount) external onlyOwner {
        uint256 _stableAmountBefore = stable.balanceOf(address(this));
        vaultFactory.borrow(_vault, _amount, address(this));
        uint256 _stableAmountAfter = stable.balanceOf(address(this));
        uint256 _stableAmount = _stableAmountAfter - _stableAmountBefore;
        stable.approve(address(stabilityPool), _stableAmount);
        stabilityPool.deposit(_stableAmount);
    }

    /**
     * @dev Withdraws tokens from the Stability Pool and repays the Vault
     * @param _vault Address of the Vault to repay
     * @param _amount Amount of tokens to withdraw and repay
     */
    function withdrawAndRepay(address _vault, uint256 _amount) external onlyOwner {
        stabilityPool.withdraw(_amount);
        stable.approve(address(vaultFactory), _amount);
        vaultFactory.repay(_vault, _amount);
    }

    /**
     * @dev Transfers specified tokens to the owner of the Vault
     * @param _token Address of the token to transfer
     * @param _vault Address of the Vault to send tokens to its owner
     * @param _amount Amount of tokens to transfer
     */
    function sendTokenToVaultOwner(address _token, address _vault, uint256 _amount) external onlyOwner {
        // Send liquidation rewards and governance tokens accrued to the Vault owner
        address _vaultOwner = IVault(_vault).vaultOwner();

        IERC20(_token).transfer(_vaultOwner, _amount);
    }
}

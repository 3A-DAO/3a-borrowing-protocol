// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IVaultFactory.sol";
import "./interfaces/IFeeRecipient.sol";
import "./interfaces/IVault.sol";

import "./utils/BONQMath.sol";
import "./utils/constants.sol";

/**
 * @title A3A Staking contract.
 * @dev Rewards stakers in StableCoin that is used to pay fee.
 */
contract A3AStaking is Ownable, Constants {
    using BONQMath for uint256;
    using SafeERC20 for IERC20;

    // Mapping of stakers' addresses to their staked amount.
    mapping(address => uint256) public stakes;
    // Total amount of A3A staked.
    uint256 public totalA3AStaked;

    // Running sum of StableCoin fees per-A3A-staked.
    uint256 public F_StableCoin;
    // Timestamp of the last fee operation.
    uint256 public lastFeeOperationTime;

    // User snapshots of F_A3A and F_StableCoin, taken at the point at which their latest deposit was made.
    mapping(address => uint256) public F_StableCoinSnapshots;
    // User gains in StableCoin.
    mapping(address => uint256) public stableCoinUserGains;

    // Interfaces to interact with other contracts.
    IVaultFactory public factory;
    IERC20 public a3aToken;
    IERC20 public stableCoin;

    // --- Events ---
    event FactoryAddressSet(address _factoryAddress);
    event A3aTokenAddressSet(address _a3aTokenAddress);
    event StableCoinAddressSet(address _stableCoinAddress);
    event StakeChanged(address indexed _staker, uint256 _newStake);
    event TotalA3AStakedUpdated(uint256 _totalA3AStaked);
    event RewardRedeemed(address _account, uint256 _stableAmount, address _vaultAddress);
    event StakerSnapshotsUpdated(address _staker, uint256 _F_StableCoin, uint256 _stableGains);
    event FeeTaken(uint256 _amount, uint256 _F_StableCoin, bool _redemptionFee);

    /**
     * @notice Initializes the A3AStaking contract.
     * @param _vaultFactory Address of the VaultFactory contract.
     * @param _a3aToken Address of the A3A token contract.
     */
    constructor(address _vaultFactory, address _a3aToken) {
        factory = IVaultFactory(_vaultFactory);
        a3aToken = IERC20(_a3aToken);
        stableCoin = IERC20(factory.stable());
    }

    // --- Functions ---

    /**
     * @dev Sets the timestamp to calculate the next decayed rate from.
     * @param _timestamp uint256 value representing time in seconds.
     */
    function setInitialLastFee(uint256 _timestamp) public onlyOwner {
        lastFeeOperationTime = _timestamp > 0 ? _timestamp : block.timestamp;
    }

    /**
     * @dev Sets the VaultFactory contract if the address was updated.
     * @param _factoryAddress Address of the updated VaultFactory contract.
     */
    function setFactory(address _factoryAddress) external onlyOwner {
        factory = IVaultFactory(_factoryAddress);
        stableCoin = IERC20(address(factory.stable()));
        emit FactoryAddressSet(address(factory));
        emit StableCoinAddressSet(address(stableCoin));
    }

    /**
     * @dev Allows users to stake A3A tokens.
     * @param _a3aAmount Amount of A3A tokens to stake.
     * @notice If caller has a pre-existing stake, records any accumulated StableCoin gains to them.
     */
    function stake(uint256 _a3aAmount) external {
        _requireNonZeroAmount(_a3aAmount);

        uint256 currentStake = stakes[msg.sender];

        // Transfer A3A from caller to this contract.
        require(a3aToken.transferFrom(msg.sender, address(this), _a3aAmount), "transfer-from-failed");

        // Grab and record accumulated StableCoin gains from the current stake and update Snapshot.
        uint256 currentTotalA3AStaked = totalA3AStaked;
        if (currentTotalA3AStaked == 0) stableCoinUserGains[msg.sender] += F_StableCoin;
        _updateUserSnapshot(msg.sender);

        // Increase user’s stake and total A3A staked.
        uint256 newTotalA3AStaked = currentTotalA3AStaked + _a3aAmount;
        totalA3AStaked = newTotalA3AStaked;
        uint256 newUserStake = currentStake + _a3aAmount;
        stakes[msg.sender] = newUserStake;

        emit TotalA3AStakedUpdated(newTotalA3AStaked);
        emit StakeChanged(msg.sender, newUserStake);
    }

    /**
     * @dev Allows user to unstake A3A.
     * @param _a3aAmount Amount of A3A to unstake.
     * @notice Unstake the A3A and send it back to the caller, and record accumulated StableCoin gains for the caller.
     * If requested amount > stake, send their entire stake.
     */
    function unstake(uint256 _a3aAmount) external {
        _requireNonZeroAmount(_a3aAmount);
        uint256 currentStake = stakes[msg.sender];
        _requireUserHasStake(currentStake);

        // Grab and record accumulated StableCoin gains from the current stake and update Snapshot.
        _updateUserSnapshot(msg.sender);

        uint256 A3AToWithdraw = _a3aAmount.min(currentStake);

        uint256 newStake = currentStake - A3AToWithdraw;

        // Decrease user's stake and total A3A staked.
        stakes[msg.sender] = newStake;
        totalA3AStaked = totalA3AStaked - A3AToWithdraw;
        emit TotalA3AStakedUpdated(totalA3AStaked);

        // Transfer unstaked A3A to user.
        a3aToken.safeTransfer(msg.sender, A3AToWithdraw);

        emit StakeChanged(msg.sender, newStake);
    }

    /**
     * @dev Increases the fees and updates F_StableCoin based on the received amount. Called by A3A core contracts.
     * @param _amount Amount of StableCoin received as fees.
     * @return bool Returns true if the fee operation is successful.
     */
    function takeFees(uint256 _amount) external returns (bool) {
        _requireNonZeroAmount(_amount);
        stableCoin.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 totalA3AStaked_cached = totalA3AStaked;
        uint256 amountPerA3AStaked = _amount;
        if (totalA3AStaked_cached > 0) {
            amountPerA3AStaked = ((_amount) * DECIMAL_PRECISION) / totalA3AStaked_cached;
        }
        uint256 newF_StableCoin = F_StableCoin + amountPerA3AStaked;
        F_StableCoin = newF_StableCoin;

        lastFeeOperationTime = block.timestamp;
        emit FeeTaken(_amount, newF_StableCoin, msg.sender == address(factory));
        return true;
    }

    // --- Pending reward functions ---

    /**
     * @dev to redeem StableCoin rewards, transfers the amount only to repay debt of the Vault.
     * @param _amount amount of StableCoin to repay the debt.
     * @param _vaultAddress address of the valid vault to repay the debt.
     * @notice user can redeem StableCoin rewards only to repay the debt of the vaults.
     */
    function redeemReward(uint256 _amount, address _vaultAddress) external {
        _requireNonZeroAmount(_amount);
        address account = msg.sender;
        require(factory.containsVault(_vaultAddress), "vault-not-found");
        IVault _vault = IVault(_vaultAddress);
        _amount = _vault.debt().min(_amount);
        require((_getUnpaidStableCoinGain(msg.sender)) >= _amount, "amount-must-fit-rewards-amount");
        _updateUserSnapshot(account);
        stableCoinUserGains[account] = stableCoinUserGains[account] - _amount;
        stableCoin.approve(address(factory), 0);
        stableCoin.approve(address(factory), _amount);

        factory.repay(_vaultAddress, _amount);

        emit RewardRedeemed(msg.sender, _amount, _vaultAddress);
    }

    /**
     * @dev Retrieves the total amount of A3A staked.
     * @return uint256 Total amount of A3A staked.
     */
    function totalStake() external view returns (uint256) {
        return totalA3AStaked;
    }

    /**
     * @dev Retrieves the unpaid rewards of the user.
     * @param _user Address of the user to check.
     * @return uint256 Unpaid rewards of the user in StableCoin.
     */
    function getUnpaidStableCoinGain(address _user) external view returns (uint256) {
        return _getUnpaidStableCoinGain(_user);
    }

    /**
     * @dev Retrieves the total rewards accumulated in StableCoin.
     * @return uint256 Total rewards accumulated in StableCoin.
     */
    function getRewardsTotal() external view returns (uint256) {
        return F_StableCoin;
    }

    // --- Internal helper functions ---

    /**
     * @dev Calculates the pending StableCoin gains for a user.
     * @param _user Address of the user to calculate gains for.
     * @return uint256 Pending StableCoin gains for the user.
     */
    function _getPendingStableCoinGain(address _user) internal view returns (uint256) {
        uint256 F_StableCoin_Snapshot = F_StableCoinSnapshots[_user];
        uint256 stableCoinGain = (stakes[_user] * (F_StableCoin - F_StableCoin_Snapshot)) / DECIMAL_PRECISION;
        return stableCoinGain;
    }

    /**
     * @dev Calculates the total unpaid StableCoin gains for a user.
     * @param _user Address of the user to calculate gains for.
     * @return uint256 Total unpaid StableCoin gains for the user.
     */
    function _getUnpaidStableCoinGain(address _user) internal view returns (uint256) {
        return stableCoinUserGains[_user] + _getPendingStableCoinGain(_user);
    }

    /**
     * @dev Records the StableCoin gains for a user based on their stake.
     * @param _user Address of the user to record gains for.
     */
    function _recordStableCoinGain(address _user) internal {
        uint256 userStake = stakes[_user];
        if (userStake > 0) {
            uint256 F_StableCoin_Snapshot = F_StableCoinSnapshots[_user];
            uint256 stableCoinGain = (userStake * (F_StableCoin - F_StableCoin_Snapshot)) / DECIMAL_PRECISION;
            stableCoinUserGains[_user] += stableCoinGain;
        }
    }

    /**
     * @dev Updates user's snapshot of StableCoin gains and F_StableCoin.
     * @param _user Address of the user to update snapshot for.
     */
    function _updateUserSnapshot(address _user) internal {
        _recordStableCoinGain(_user);
        uint256 currentF_StableCoin = F_StableCoin;
        F_StableCoinSnapshots[_user] = currentF_StableCoin;
        emit StakerSnapshotsUpdated(_user, currentF_StableCoin, stableCoinUserGains[_user]);
    }

    // --- 'require' functions ---

    /**
     * @dev Requires the user to have a non-zero stake.
     * @param currentStake Amount of current stake for the user.
     */
    function _requireUserHasStake(uint256 currentStake) internal pure {
        require(currentStake > 0, "stakes-is-zero");
    }

    /**
     * @dev Requires the amount to be non-zero.
     * @param _amount Amount to check for non-zero.
     */
    function _requireNonZeroAmount(uint256 _amount) internal pure {
        require(_amount > 0, "amount-is-zero");
    }
}

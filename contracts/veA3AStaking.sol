// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/interfaces/IERC20Metadata.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

import './interfaces/IVaultFactory.sol';
import './interfaces/IFeeRecipient.sol';
import './interfaces/IVault.sol';
import './interfaces/IStabilityPool.sol';
import './utils/constants.sol';

/**
 * @title A3A Staking contract.
 * @dev Rewards stakers in StableCoin that is used to pay fee.
 */
contract veA3AStaking is Ownable, Constants {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_SLASHING_ROUNDS = 5;
    address public constant BURN_ADDRESS =
        0x000000000000000000000000000000000000dEaD;
    // Mapping of stakers' addresses to their staked amount.
    mapping(address => uint256) public stakes;
    // Mapping of stakers' addresses to the timestamp of their last stake operation.
    mapping(address => uint256) public lastStakeOperationTime;
    // Mapping of slashing rounds to their duration and rate.
    mapping(uint256 => uint256) public slashingDuration;
    mapping(uint256 => uint256) public slashingRate;

    // The rate of A3A that will be returned to the Stability Pool in case of slashing.
    // The rest will be burned.
    uint256 public slashingReturnForStabilityPool;

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
    IStabilityPool public stabilityPool;
    IERC20 public a3aToken;
    IERC20 public stableCoin;

    // --- Events ---
    event StabilityPoolSet(address _stabilityPool);
    event SlashingRateSet(uint256 _index, uint256 _duration, uint256 _rate);
    event FactoryAddressSet(address _factoryAddress);
    event A3aTokenAddressSet(address _a3aTokenAddress);
    event StableCoinAddressSet(address _stableCoinAddress);
    event StakeChanged(address indexed _staker, uint256 _newStake);
    event TotalA3AStakedUpdated(uint256 _totalA3AStaked);
    event RewardRedeemed(
        address _account,
        uint256 _stableAmount,
        address _vaultAddress
    );
    event StakerSnapshotsUpdated(
        address _staker,
        uint256 _F_StableCoin,
        uint256 _stableGains
    );
    event FeeTaken(uint256 _amount, uint256 _F_StableCoin, bool _redemptionFee);

    /**
     * @notice Initializes the A3AStaking contract.
     * @param _vaultFactory Address of the VaultFactory contract.
     * @param _a3aToken Address of the A3A token contract.
     * @param _stabilityPool Address of the StabilityPool contract.
     */
    constructor(
        address _vaultFactory,
        address _a3aToken,
        address _stabilityPool
    ) {
        require(_vaultFactory != address(0), 'invalid-vault-factory-address');
        require(_a3aToken != address(0), 'invalid-a3a-token-address');
        require(_stabilityPool != address(0), 'invalid-stability-pool-address');

        factory = IVaultFactory(_vaultFactory);
        a3aToken = IERC20(_a3aToken);
        stableCoin = IERC20(factory.stable());
        stabilityPool = IStabilityPool(_stabilityPool);
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
     * @dev Sets the slashing rate that will be returned to the Stability Pool in case of slashing.
     * @param _rate uint256 value representing the rate of slashing. (0-10000), 10000 = 100%
     */
    function setSlashingReturnForStabilityPool(
        uint256 _rate
    ) external onlyOwner {
        require(_rate <= 10_000, 'invalid-rate');
        slashingReturnForStabilityPool = _rate;
    }

    /**
     * @dev Sets the slashing rate and duration.
     * @param _index uint256 value representing the index of the slashing rate.
     * @param _duration uint256 value representing time in seconds.
     * @param _rate uint256 value representing the rate of slashing.
     */

    function setSlashingRate(
        uint256 _index,
        uint256 _duration,
        uint256 _rate
    ) external onlyOwner {
        slashingDuration[_index] = _duration;
        slashingRate[_index] = _rate;
    }

    function getCurrentSlashingRate(
        address _user
    ) public view returns (uint256 _currentRate, uint256 _timeLeftForNextRate) {
        uint256 _currentIndex = 0;

        uint256 _elapsedTime = block.timestamp - lastStakeOperationTime[_user];

        while (slashingDuration[_currentIndex] != 0) {
            if (slashingDuration[_currentIndex] == 0) {
                _currentRate = 0;
                break;
            }
            if (_elapsedTime < slashingDuration[_currentIndex]) {
                _currentRate = slashingRate[_currentIndex];
                break;
            }
            _currentIndex++;
        }

        if (_currentRate != 0) {
            uint256 _delta = lastStakeOperationTime[_user] +
                slashingDuration[_currentIndex];

            if (_delta > block.timestamp) {
                _timeLeftForNextRate = _delta - block.timestamp;
            }
        }

        return (_currentRate, _timeLeftForNextRate);
    }

    function getFullUnlockTimestamp(
        address _user
    ) public view returns (uint256 _unlockTimestamp, bool isFullyUnlocked) {
        uint256 _currentIndex;
        uint256 _depositTime = lastStakeOperationTime[_user];
        uint256 _totalDuration = 0;
        while (slashingDuration[_currentIndex] != 0) {
            _totalDuration = slashingDuration[_currentIndex];
            _currentIndex++;
        }
        _unlockTimestamp = _depositTime + _totalDuration;
        return (_unlockTimestamp, _unlockTimestamp < block.timestamp);
    }

    function getAllRates()
        public
        view
        returns (uint256[] memory _rates, uint256[] memory _durations)
    {
        _rates = new uint256[](MAX_SLASHING_ROUNDS);
        _durations = new uint256[](MAX_SLASHING_ROUNDS);
        for (uint256 i = 0; i < MAX_SLASHING_ROUNDS; i++) {
            _rates[i] = slashingRate[i];
            _durations[i] = slashingDuration[i];
        }
        return (_rates, _durations);
    }

    /**
     * @dev Sets the VaultFactory contract if the address was updated.
     * @param _factoryAddress Address of the updated VaultFactory contract.
     */
    function setFactory(address _factoryAddress) external onlyOwner {
        require(_factoryAddress != address(0), 'invalid-factory-address');
        factory = IVaultFactory(_factoryAddress);
        stableCoin = IERC20(address(factory.stable()));
        emit FactoryAddressSet(address(factory));
        emit StableCoinAddressSet(address(stableCoin));
    }

    function setStabilityPool(address _stabilityPool) external onlyOwner {
        require(_stabilityPool != address(0), 'invalid-stability-pool-address');
        stabilityPool = IStabilityPool(_stabilityPool);
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
        require(
            a3aToken.transferFrom(msg.sender, address(this), _a3aAmount),
            'transfer-from-failed'
        );

        // Grab and record accumulated StableCoin gains from the current stake and update Snapshot.
        uint256 currentTotalA3AStaked = totalA3AStaked;
        if (currentTotalA3AStaked == 0)
            stableCoinUserGains[msg.sender] += F_StableCoin;
        _updateUserSnapshot(msg.sender);

        // Increase user’s stake and total A3A staked.
        uint256 newTotalA3AStaked = currentTotalA3AStaked + _a3aAmount;
        totalA3AStaked = newTotalA3AStaked;
        uint256 newUserStake = currentStake + _a3aAmount;
        stakes[msg.sender] = newUserStake;
        lastStakeOperationTime[msg.sender] = block.timestamp;

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

        uint256 A3AToWithdraw = _a3aAmount > currentStake
            ? currentStake
            : _a3aAmount;

        uint256 newStake = currentStake - A3AToWithdraw;

        // Decrease user's stake and total A3A staked.
        stakes[msg.sender] = newStake;
        totalA3AStaked = totalA3AStaked - A3AToWithdraw;
        emit TotalA3AStakedUpdated(totalA3AStaked);

        // Transfer unstaked A3A to user.

        (
            uint256 A3AToUser,
            uint256 A3AToStabilityPool,
            uint256 A3AToBurn
        ) = getWithdrawAmounts(msg.sender, A3AToWithdraw);

        if (A3AToUser > 0) {
            a3aToken.safeTransfer(msg.sender, A3AToUser);
        }

        if (A3AToStabilityPool > 0) {
            a3aToken.safeTransfer(address(stabilityPool), A3AToStabilityPool);
        }

        if (A3AToBurn > 0) {
            a3aToken.safeTransfer(BURN_ADDRESS, A3AToBurn);
        }

        emit StakeChanged(msg.sender, newStake);
    }

    function getWithdrawAmounts(
        address _user,
        uint256 _withdrawAmount
    )
        public
        view
        returns (
            uint256 _amountToUser,
            uint256 _amountToStabilityPool,
            uint256 _amountToBurn
        )
    {
        (uint256 _currentRate, ) = getCurrentSlashingRate(_user);

        uint256 _slashingAmount = (_withdrawAmount * _currentRate) / 10_000;

        if (_withdrawAmount > 0) {
            _amountToUser = _withdrawAmount - _slashingAmount;
            _amountToStabilityPool =
                (_slashingAmount * slashingReturnForStabilityPool) /
                10_000;
            _amountToBurn = _slashingAmount - _amountToStabilityPool;
        } else {
            _amountToUser = 0;
            _amountToStabilityPool = 0;
            _amountToBurn = 0;
        }
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
            amountPerA3AStaked =
                ((_amount) * DECIMAL_PRECISION) /
                totalA3AStaked_cached;
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
        require(factory.containsVault(_vaultAddress), 'vault-not-found');
        IVault _vault = IVault(_vaultAddress);
        _amount = _vault.debt() > _amount ? _amount : _vault.debt();
        require(
            (_getUnpaidStableCoinGain(msg.sender)) >= _amount,
            'amount-must-fit-rewards-amount'
        );
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
    function getUnpaidStableCoinGain(
        address _user
    ) external view returns (uint256) {
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
    function _getPendingStableCoinGain(
        address _user
    ) internal view returns (uint256) {
        uint256 F_StableCoin_Snapshot = F_StableCoinSnapshots[_user];
        uint256 stableCoinGain = (stakes[_user] *
            (F_StableCoin - F_StableCoin_Snapshot)) / DECIMAL_PRECISION;
        return stableCoinGain;
    }

    /**
     * @dev Calculates the total unpaid StableCoin gains for a user.
     * @param _user Address of the user to calculate gains for.
     * @return uint256 Total unpaid StableCoin gains for the user.
     */
    function _getUnpaidStableCoinGain(
        address _user
    ) internal view returns (uint256) {
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
            uint256 stableCoinGain = (userStake *
                (F_StableCoin - F_StableCoin_Snapshot)) / DECIMAL_PRECISION;
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
        emit StakerSnapshotsUpdated(
            _user,
            currentF_StableCoin,
            stableCoinUserGains[_user]
        );
    }

    // --- 'require' functions ---

    /**
     * @dev Requires the user to have a non-zero stake.
     * @param currentStake Amount of current stake for the user.
     */
    function _requireUserHasStake(uint256 currentStake) internal pure {
        require(currentStake > 0, 'stakes-is-zero');
    }

    /**
     * @dev Requires the amount to be non-zero.
     * @param _amount Amount to check for non-zero.
     */
    function _requireNonZeroAmount(uint256 _amount) internal pure {
        require(_amount > 0, 'amount-is-zero');
    }
}

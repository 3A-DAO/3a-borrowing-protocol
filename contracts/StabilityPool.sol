// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/access/Ownable.sol';
// import openzeppelin reentrancy guard
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import './utils/constants.sol';
import './interfaces/IVaultFactory.sol';
import './interfaces/IMintableToken.sol';
import './interfaces/IVault.sol';
import './interfaces/ILiquidationRouter.sol';

/**
 * @title StabilityPool
 * @dev A smart contract responsible for liquidating vaults and rewarding depositors with collateral redeemed.
 * @notice is used to liquidate vaults and reward depositors with collateral redeemed
 */
contract StabilityPool is Ownable, ReentrancyGuard, Constants {
    using SafeERC20 for IERC20;

    // A structure defining token addresses and their respective 'Stable' values
    struct TokenToS {
        address tokenAddress;
        uint256 S_value;
    }

    // A structure defining token addresses and their corresponding uint256 values
    struct TokenToUint256 {
        address tokenAddress;
        uint256 value;
    }

    // A structure that holds snapshots of token balances, 'P' and 'G', and epoch information
    struct Snapshots {
        TokenToS[] tokenToSArray;
        uint256 P;
        uint256 G;
        uint128 scale;
        uint128 epoch;
    }

    IVaultFactory public factory;
    IMintableToken public immutable stableCoin;

    IERC20 public immutable a3aToken;

    // Track total deposits and error offsets
    uint256 public totalDeposit;
    mapping(address => uint256) public collateralToLastErrorOffset;
    uint256 public lastStableCoinLossErrorOffset;
    mapping(address => uint256) public deposits;
    mapping(address => Snapshots) public depositSnapshots; // depositor address -> snapshots struct

    // Variables related to A3A rewards and error tracking
    uint256 public a3aPerMinute;
    uint256 public totalA3ARewardsLeft;
    uint256 public latestA3ARewardTime;
    // Error tracker for the error correction in the A3A redistribution calculation
    uint256 public lastA3AError;
    /*  Product 'P': Running product by which to multiply an initial deposit, in order to find the current compounded deposit,
     * after a series of liquidations have occurred, each of which cancel some StableCoin debt with the deposit.
     *
     * During its lifetime, a deposit's value evolves from d_t to d_t * P / P_t , where P_t
     * is the snapshot of P taken at the instant the deposit was made. 18-digit decimal.
     */
    uint256 public P;

    uint256 public constant SCALE_FACTOR = 1e9;

    uint256 public constant SECONDS_IN_ONE_MINUTE = 60;

    // Each time the scale of P shifts by SCALE_FACTOR, the scale is incremented by 1
    uint128 public currentScale;

    // With each offset that fully empties the Pool, the epoch is incremented by 1
    uint128 public currentEpoch;

    /* Collateral Gain sum 'S': During its lifetime, each deposit d_t earns an Collateral gain of ( d_t * [S - S_t] )/P_t, where S_t
     * is the depositor's snapshot of S taken at the time t when the deposit was made.
     *
     * The 'S' sums are stored in a nested mapping (epoch => scale => sum):
     *
     * - The inner mapping records the sum S at different scales
     * - The outer mapping records the (scale => sum) mappings, for different epochs.
     */
    mapping(uint128 => mapping(uint128 => TokenToS[]))
        public epochToScaleToTokenToSum;

    /*
     * Similarly, the sum 'G' is used to calculate A3A gains. During it's lifetime, each deposit d_t earns a A3A gain of
     *  ( d_t * [G - G_t] )/P_t, where G_t is the depositor's snapshot of G taken at time t when  the deposit was made.
     *
     *  A3A reward events occur are triggered by depositor operations (new deposit, topup, withdrawal), and liquidations.
     *  In each case, the A3A reward is issued (i.e. G is updated), before other state changes are made.
     */
    mapping(uint128 => mapping(uint128 => uint256)) public epochToScaleToG;

    event Deposit(address _contributor, uint256 _amount);
    event TotalDepositUpdated(uint256 _newValue);
    event Withdraw(address _contributor, uint256 _amount);

    // Events
    // solhint-disable-next-line event-name-camelcase
    event A3ARewardRedeemed(address _contributor, uint256 _amount);
    event A3ARewardIssue(uint256 issuance, uint256 _totalA3ARewardsLeft);
    event A3APerMinuteUpdated(uint256 _newAmount);
    event TotalA3ARewardsUpdated(uint256 _newAmount);
    // solhint-disable-next-line event-name-camelcase
    event CollateralRewardRedeemed(
        address _contributor,
        address _tokenAddress,
        uint256 _amount
    );
    event DepositSnapshotUpdated(
        address indexed _depositor,
        uint256 _P,
        uint256 _G,
        uint256 _newDepositValue
    );

    /* solhint-disable event-name-camelcase */
    event P_Updated(uint256 _P);
    event S_Updated(
        address _tokenAddress,
        uint256 _S,
        uint128 _epoch,
        uint128 _scale
    );
    event G_Updated(uint256 _G, uint128 _epoch, uint128 _scale);
    /* solhint-disable event-name-camelcase */
    event EpochUpdated(uint128 _currentEpoch);
    event ScaleUpdated(uint128 _currentScale);

    /**
     * @notice Initializes the StabilityPool contract with the given Vault factory and A3A token addresses.
     * @dev The constructor sets up essential contract parameters upon deployment.
     * @param _factory Address of the Vault Factory contract responsible for creating Vault instances.
     * @param _a3aToken Address of the A3A token to be used within the Vault system.
     */
    constructor(address _factory, address _a3aToken) {
        require(_factory != address(0x0), 'factory-is-0');
        require(_a3aToken != address(0x0), 'a3a-is-0');
        factory = IVaultFactory(_factory);
        stableCoin = IMintableToken(address(IVaultFactory(_factory).stable()));
        a3aToken = IERC20(_a3aToken);
        P = DECIMAL_PRECISION;
    }

    /// @dev to deposit StableCoin into StabilityPool this must be protected against a reentrant attack from the arbitrage
    /// @param  _amount amount to deposit
    function deposit(uint256 _amount) public nonReentrant {
        // address depositor = msg.sender;
        require(_amount > 0, 'amount-is-0');

        stableCoin.transferFrom(msg.sender, address(this), _amount);
        uint256 initialDeposit = deposits[msg.sender];
        _redeemReward();

        Snapshots memory snapshots = depositSnapshots[msg.sender];

        uint256 compoundedDeposit = _getCompoundedDepositFromSnapshots(
            initialDeposit,
            snapshots
        );
        // uint256 newValue = compoundedDeposit + _amount;
        uint256 newTotalDeposit = totalDeposit + _amount;
        totalDeposit = newTotalDeposit;

        _updateDepositAndSnapshots(msg.sender, compoundedDeposit + _amount);

        emit Deposit(msg.sender, _amount);
        emit TotalDepositUpdated(newTotalDeposit);
    }

    /// @dev to withdraw StableCoin that was not spent if this function is called in a reentrantway during arbitrage  it
    /// @dev would skew the token allocation and must be protected against
    /// @param  _amount amount to withdraw
    function withdraw(uint256 _amount) public nonReentrant {
        uint256 contributorDeposit = deposits[msg.sender];
        require(_amount > 0, 'amount-is-0');
        require(contributorDeposit > 0, 'deposit-is-0');
        _redeemReward();

        Snapshots memory snapshots = depositSnapshots[msg.sender];

        uint256 compoundedDeposit = _getCompoundedDepositFromSnapshots(
            contributorDeposit,
            snapshots
        );
        uint256 calculatedAmount = compoundedDeposit > _amount
            ? _amount
            : compoundedDeposit;
        uint256 newValue = compoundedDeposit - calculatedAmount;

        totalDeposit = totalDeposit - calculatedAmount;

        _updateDepositAndSnapshots(msg.sender, newValue);

        stableCoin.transfer(msg.sender, calculatedAmount);
        emit Withdraw(msg.sender, calculatedAmount);
        emit TotalDepositUpdated(totalDeposit);
    }

    /// @dev to withdraw collateral rewards earned after liquidations
    /// @dev this function does not provide an opportunity for a reentrancy attack
    function redeemReward() external {
        Snapshots memory snapshots = depositSnapshots[msg.sender];
        uint256 contributorDeposit = deposits[msg.sender];

        uint256 compoundedDeposit = _getCompoundedDepositFromSnapshots(
            contributorDeposit,
            snapshots
        );
        _redeemReward();
        _updateDepositAndSnapshots(msg.sender, compoundedDeposit);
    }

    function setVaultFactory(address _factory) external onlyOwner {
        require(_factory != address(0x0), 'factory-is-0');
        factory = IVaultFactory(_factory);
    }

    /// @dev liquidates vault, must be called from that vault
    /// @dev this function does not provide an opportunity for a reentrancy attack even though it would make the arbitrage
    /// @dev fail because of the lowering of the stablecoin balance
    /// @notice must be called by the valid vault
    function liquidate() external {
        require(
            msg.sender == factory.liquidationRouter(),
            'not-liquidation-router'
        );
        IVaultFactory factory_cached = factory;

        ILiquidationRouter _liquidationRouter = ILiquidationRouter(
            factory_cached.liquidationRouter()
        );
        uint256 _underWaterDebt = _liquidationRouter.underWaterDebt();
        address[] memory _collaterals = _liquidationRouter.collaterals();
        uint256 _collateralCount = _collaterals.length;

        uint256 totalStableCoin = totalDeposit; // cached to save an SLOAD

        for (uint256 i; i < _collateralCount; i++) {
            IERC20 _collateralToken = IERC20(_collaterals[i]);
            uint256 _collateralAmount = _liquidationRouter.collateral(
                address(_collateralToken)
            );
            _collateralToken.safeTransferFrom(
                address(_liquidationRouter),
                address(this),
                _collateralAmount
            );

            (
                uint256 collateralGainPerUnitStaked,
                uint256 stableCoinLossPerUnitStaked
            ) = _computeRewardsPerUnitStaked(
                    address(_collateralToken),
                    _collateralAmount,
                    _underWaterDebt,
                    totalStableCoin
                );

            _updateRewardSumAndProduct(
                address(_collateralToken),
                collateralGainPerUnitStaked,
                stableCoinLossPerUnitStaked
            );
        }

        _triggerA3Adistribution();

        stableCoin.burn(_underWaterDebt);
        uint256 newTotalDeposit = totalStableCoin - _underWaterDebt;
        totalDeposit = newTotalDeposit;
        emit TotalDepositUpdated(newTotalDeposit);
        //factory_cached.emitLiquidationEvent(address(collateralToken), msg.sender, address(this), vaultCollateral);
    }

    /**
     * @dev Gets the current withdrawable deposit of a specified staker.
     * @param staker The address of the staker
     * @return uint256 The withdrawable deposit amount
     */ function getWithdrawableDeposit(
        address staker
    ) public view returns (uint256) {
        uint256 initialDeposit = deposits[staker];
        Snapshots memory snapshots = depositSnapshots[staker];
        return _getCompoundedDepositFromSnapshots(initialDeposit, snapshots);
    }

    /**
     * @dev Retrieves the collateral reward of a specified `_depositor` for a specific `_token`.
     * @param _token The address of the collateral token
     * @param _depositor The address of the depositor
     * @return uint256 The collateral reward amount
     */
    function getCollateralReward(
        address _token,
        address _depositor
    ) external view returns (uint256) {
        Snapshots memory _snapshots = depositSnapshots[_depositor];
        uint256 _initialDeposit = deposits[_depositor];

        uint128 epochSnapshot = _snapshots.epoch;
        uint128 scaleSnapshot = _snapshots.scale;

        TokenToS[] memory tokensToSum_cached = epochToScaleToTokenToSum[
            epochSnapshot
        ][scaleSnapshot];
        uint256 tokenArrayLength = tokensToSum_cached.length;

        TokenToS memory cachedS;
        for (uint128 i = 0; i < tokenArrayLength; i++) {
            TokenToS memory S = tokensToSum_cached[i];
            if (S.tokenAddress == _token) {
                cachedS = S;
                break;
            }
        }
        if (cachedS.tokenAddress == address(0)) return 0;
        uint256 relatedSValue_snapshot;
        for (uint128 i = 0; i < _snapshots.tokenToSArray.length; i++) {
            TokenToS memory S_snapsot = _snapshots.tokenToSArray[i];
            if (S_snapsot.tokenAddress == _token) {
                relatedSValue_snapshot = S_snapsot.S_value;
                break;
            }
        }
        TokenToS[] memory nextTokensToSum_cached = epochToScaleToTokenToSum[
            epochSnapshot
        ][scaleSnapshot + 1];
        uint256 nextScaleS;
        for (uint128 i = 0; i < nextTokensToSum_cached.length; i++) {
            TokenToS memory nextScaleTokenToS = nextTokensToSum_cached[i];
            if (nextScaleTokenToS.tokenAddress == _token) {
                nextScaleS = nextScaleTokenToS.S_value;
                break;
            }
        }

        uint256 P_Snapshot = _snapshots.P;

        uint256 collateralGain = _getCollateralGainFromSnapshots(
            _initialDeposit,
            cachedS.S_value,
            nextScaleS,
            relatedSValue_snapshot,
            P_Snapshot
        );

        return collateralGain;
    }

    /**
     * @dev Retrieves the A3A reward of a specified `_depositor`.
     * @param _depositor The address of the user
     * @return uint256 The A3A reward amount
     */
    function getDepositorA3AGain(
        address _depositor
    ) external view returns (uint256) {
        uint256 totalA3ARewardsLeft_cached = totalA3ARewardsLeft;
        uint256 totalStableCoin = totalDeposit;
        if (
            totalA3ARewardsLeft_cached == 0 ||
            a3aPerMinute == 0 ||
            totalStableCoin == 0
        ) {
            return 0;
        }

        uint256 _a3aIssuance = a3aPerMinute *
            ((block.timestamp - latestA3ARewardTime) / SECONDS_IN_ONE_MINUTE);
        if (totalA3ARewardsLeft_cached < _a3aIssuance) {
            _a3aIssuance = totalA3ARewardsLeft_cached;
        }

        uint256 a3aGain = (_a3aIssuance * DECIMAL_PRECISION + lastA3AError) /
            totalStableCoin;
        uint256 marginalA3AGain = a3aGain * P;

        return _getDepositorA3AGain(_depositor, marginalA3AGain);
    }

    /**
     * @dev Sets the amount of A3A tokens per minute for rewards.
     * @param _a3aPerMinute The A3A tokens per minute to be set
     */
    function setA3APerMinute(uint256 _a3aPerMinute) external onlyOwner {
        _triggerA3Adistribution();
        a3aPerMinute = _a3aPerMinute;
        emit A3APerMinuteUpdated(a3aPerMinute);
    }

    /**
     * @dev Sets the total amount of A3A tokens to be rewarded.
     * It pays per minute until it reaches the specified rewarded amount.
     */
    function setA3AAmountForRewards() external onlyOwner {
        _triggerA3Adistribution();
        totalA3ARewardsLeft = a3aToken.balanceOf(address(this));
        emit TotalA3ARewardsUpdated(totalA3ARewardsLeft);
    }

    /**
     * @dev Redeems rewards, calling internal functions for collateral and A3A rewards.
     * Private function for internal use.
     */
    function _redeemReward() private {
        _redeemCollateralReward();
        _triggerA3Adistribution();
        _redeemA3AReward();
    }

    /**
     * @notice Allows a depositor to redeem collateral rewards.
     */
    function _redeemCollateralReward() internal {
        address depositor = msg.sender;
        TokenToUint256[]
            memory depositorCollateralGains = _getDepositorCollateralGains(
                depositor
            );
        _sendCollateralRewardsToDepositor(depositorCollateralGains);
    }

    /**
     * @notice Allows a depositor to redeem A3A rewards.
     */
    function _redeemA3AReward() internal {
        address depositor = msg.sender;
        uint256 depositorA3AGain = _getDepositorA3AGain(depositor, 0);
        _sendA3ARewardsToDepositor(depositorA3AGain);
        emit A3ARewardRedeemed(depositor, depositorA3AGain);
    }

    /**
     * @dev Updates user deposit snapshot data for a new deposit value.
     * @param _depositor The address of the depositor.
     * @param _newValue The new deposit value.
     */
    function _updateDepositAndSnapshots(
        address _depositor,
        uint256 _newValue
    ) private {
        deposits[_depositor] = _newValue;
        if (_newValue == 0) {
            delete depositSnapshots[_depositor];
            emit DepositSnapshotUpdated(_depositor, 0, 0, 0);
            return;
        }
        uint128 cachedEpoch = currentEpoch;
        uint128 cachedScale = currentScale;
        TokenToS[] storage cachedTokenToSArray = epochToScaleToTokenToSum[
            cachedEpoch
        ][cachedScale];
        uint256 cachedP = P;
        uint256 cachedG = epochToScaleToG[cachedEpoch][cachedScale];

        depositSnapshots[_depositor].tokenToSArray = cachedTokenToSArray;
        depositSnapshots[_depositor].P = cachedP;
        depositSnapshots[_depositor].G = cachedG;
        depositSnapshots[_depositor].scale = cachedScale;
        depositSnapshots[_depositor].epoch = cachedEpoch;
        emit DepositSnapshotUpdated(_depositor, cachedP, cachedG, _newValue);
    }

    /**
     * @notice Updates the reward sums and product based on collateral and stablecoin changes.
     * @dev This function updates the reward sums and product based on changes in collateral and stablecoin values.
     * @param _collateralTokenAddress Address of the collateral token.
     * @param _collateralGainPerUnitStaked Collateral gains per unit staked.
     * @param _stableCoinLossPerUnitStaked Stablecoin losses per unit staked.
     */
    function _updateRewardSumAndProduct(
        address _collateralTokenAddress,
        uint256 _collateralGainPerUnitStaked,
        uint256 _stableCoinLossPerUnitStaked
    ) internal {
        assert(_stableCoinLossPerUnitStaked <= DECIMAL_PRECISION);

        uint128 currentScaleCached = currentScale;
        uint128 currentEpochCached = currentEpoch;
        uint256 currentS;
        uint256 currentSIndex;
        bool _found;
        TokenToS[] memory currentTokenToSArray = epochToScaleToTokenToSum[
            currentEpochCached
        ][currentScaleCached];
        for (uint128 i = 0; i < currentTokenToSArray.length; i++) {
            if (
                currentTokenToSArray[i].tokenAddress == _collateralTokenAddress
            ) {
                currentS = currentTokenToSArray[i].S_value;
                currentSIndex = i;
                _found = true;
            }
        }
        /*
         * Calculate the new S first, before we update P.
         * The Collateral gain for any given depositor from a liquidation depends on the value of their deposit
         * (and the value of totalDeposits) prior to the Stability being depleted by the debt in the liquidation.
         *
         * Since S corresponds to Collateral gain, and P to deposit loss, we update S first.
         */
        uint256 marginalCollateralGain = _collateralGainPerUnitStaked * P;
        uint256 newS = currentS + marginalCollateralGain;
        if (currentTokenToSArray.length == 0 || !_found) {
            TokenToS memory tokenToS;
            tokenToS.S_value = newS;
            tokenToS.tokenAddress = _collateralTokenAddress;
            epochToScaleToTokenToSum[currentEpochCached][currentScaleCached]
                .push() = tokenToS;
        } else {
            epochToScaleToTokenToSum[currentEpochCached][currentScaleCached][
                currentSIndex
            ].S_value = newS;
        }
        emit S_Updated(
            _collateralTokenAddress,
            newS,
            currentEpochCached,
            currentScaleCached
        );
        _updateP(_stableCoinLossPerUnitStaked, true);
    }

    function _updateP(
        uint256 _stableCoinChangePerUnitStaked,
        bool loss
    ) internal {
        /*
         * The newProductFactor is the factor by which to change all deposits, due to the depletion of Stability Pool StableCoin in the liquidation.
         * We make the product factor 0 if there was a pool-emptying. Otherwise, it is (1 - StableCoinLossPerUnitStaked)
         */
        uint256 newProductFactor;
        if (loss) {
            newProductFactor = uint256(
                DECIMAL_PRECISION - _stableCoinChangePerUnitStaked
            );
        } else {
            newProductFactor = uint256(
                DECIMAL_PRECISION + _stableCoinChangePerUnitStaked
            );
        }
        uint256 currentP = P;
        uint256 newP;
        // If the Stability Pool was emptied, increment the epoch, and reset the scale and product P
        if (newProductFactor == 0) {
            currentEpoch += 1;
            emit EpochUpdated(currentEpoch);
            currentScale = 0;
            emit ScaleUpdated(0);
            newP = DECIMAL_PRECISION;

            // If multiplying P by a non-zero product factor would reduce P below the scale boundary, increment the scale
        } else if (
            (currentP * newProductFactor) / DECIMAL_PRECISION < SCALE_FACTOR
        ) {
            newP =
                (currentP * newProductFactor * SCALE_FACTOR) /
                DECIMAL_PRECISION;
            currentScale += 1;
            emit ScaleUpdated(currentScale);
        } else {
            newP = (currentP * newProductFactor) / DECIMAL_PRECISION;
        }

        assert(newP > 0);
        P = newP;

        emit P_Updated(newP);
    }

    /**
     * @dev Updates G when a new A3A amount is issued.
     * @param _a3aIssuance The new A3A issuance amount
     */
    function _updateG(uint256 _a3aIssuance) internal {
        uint256 totalStableCoin = totalDeposit; // cached to save an SLOAD
        /*
         * When total deposits is 0, G is not updated. In this case, the A3A issued can not be obtained by later
         * depositors - it is missed out on, and remains in the balanceof the Stability Pool.
         *
         */
        if (totalStableCoin == 0 || _a3aIssuance == 0) {
            return;
        }

        uint256 a3aPerUnitStaked;
        a3aPerUnitStaked = _computeA3APerUnitStaked(
            _a3aIssuance,
            totalStableCoin
        );

        uint256 marginalA3AGain = a3aPerUnitStaked * P;
        uint128 currentEpoch_cached = currentEpoch;
        uint128 currentScale_cached = currentScale;

        uint256 newEpochToScaleToG = epochToScaleToG[currentEpoch_cached][
            currentScale_cached
        ] + marginalA3AGain;
        epochToScaleToG[currentEpoch_cached][
            currentScale_cached
        ] = newEpochToScaleToG;

        emit G_Updated(
            newEpochToScaleToG,
            currentEpoch_cached,
            currentScale_cached
        );
    }

    /**
     * @dev Retrieves the collateral gains of a specified `_depositor`.
     * @param _depositor The address of the depositor
     * @return TokenToUint256[] An array containing collateral gain information
     */
    function _getDepositorCollateralGains(
        address _depositor
    ) internal view returns (TokenToUint256[] memory) {
        uint256 initialDeposit = deposits[_depositor];
        if (initialDeposit == 0) {
            TokenToUint256[] memory x;
            return x;
        }

        Snapshots memory snapshots = depositSnapshots[_depositor];

        TokenToUint256[]
            memory gainPerCollateralArray = _getCollateralGainsArrayFromSnapshots(
                initialDeposit,
                snapshots
            );
        return gainPerCollateralArray;
    }

    // todo!
    function _getCollateralGainsArrayFromSnapshots(
        uint256 _initialDeposit,
        Snapshots memory _snapshots
    ) internal view returns (TokenToUint256[] memory) {
        /*
         * Grab the sum 'S' from the epoch at which the stake was made. The Collateral gain may span up to one scale change.
         * If it does, the second portion of the Collateral gain is scaled by 1e9.
         * If the gain spans no scale change, the second portion will be 0.
         */
        uint128 epochSnapshot = _snapshots.epoch;
        uint128 scaleSnapshot = _snapshots.scale;
        TokenToS[] memory tokensToSum_cached = epochToScaleToTokenToSum[
            epochSnapshot
        ][scaleSnapshot];
        uint256 tokenArrayLength = tokensToSum_cached.length;
        TokenToUint256[] memory CollateralGainsArray = new TokenToUint256[](
            tokenArrayLength
        );
        for (uint128 i = 0; i < tokenArrayLength; i++) {
            TokenToS memory S = tokensToSum_cached[i];
            uint256 relatedS_snapshot;
            for (uint128 j = 0; j < _snapshots.tokenToSArray.length; j++) {
                TokenToS memory S_snapsot = _snapshots.tokenToSArray[j];
                if (S_snapsot.tokenAddress == S.tokenAddress) {
                    relatedS_snapshot = S_snapsot.S_value;
                    break;
                }
            }
            TokenToS[] memory nextTokensToSum_cached = epochToScaleToTokenToSum[
                epochSnapshot
            ][scaleSnapshot + 1];
            uint256 nextScaleS;
            for (uint128 j = 0; j < nextTokensToSum_cached.length; j++) {
                TokenToS memory nextScaleTokenToS = nextTokensToSum_cached[j];
                if (nextScaleTokenToS.tokenAddress == S.tokenAddress) {
                    nextScaleS = nextScaleTokenToS.S_value;
                    break;
                }
            }
            uint256 P_Snapshot = _snapshots.P;

            CollateralGainsArray[i].value = _getCollateralGainFromSnapshots(
                _initialDeposit,
                S.S_value,
                nextScaleS,
                relatedS_snapshot,
                P_Snapshot
            );
            CollateralGainsArray[i].tokenAddress = S.tokenAddress;
        }

        return CollateralGainsArray;
    }

    function _getCollateralGainFromSnapshots(
        uint256 initialDeposit,
        uint256 S,
        uint256 nextScaleS,
        uint256 S_Snapshot,
        uint256 P_Snapshot
    ) internal pure returns (uint256) {
        uint256 firstPortion = S - S_Snapshot;
        uint256 secondPortion = nextScaleS / SCALE_FACTOR;
        uint256 collateralGain = (initialDeposit *
            (firstPortion + secondPortion)) /
            P_Snapshot /
            DECIMAL_PRECISION;

        return collateralGain;
    }

    function _getDepositorA3AGain(
        address _depositor,
        uint256 _marginalA3AGain
    ) internal view returns (uint256) {
        uint256 initialDeposit = deposits[_depositor];
        if (initialDeposit == 0) {
            return 0;
        }
        Snapshots memory _snapshots = depositSnapshots[_depositor];
        /*
         * Grab the sum 'G' from the epoch at which the stake was made. The A3A gain may span up to one scale change.
         * If it does, the second portion of the A3A gain is scaled by 1e9.
         * If the gain spans no scale change, the second portion will be 0.
         */
        uint256 firstEpochPortion = epochToScaleToG[_snapshots.epoch][
            _snapshots.scale
        ];
        uint256 secondEpochPortion = epochToScaleToG[_snapshots.epoch][
            _snapshots.scale + 1
        ];
        if (_snapshots.epoch == currentEpoch) {
            if (_snapshots.scale == currentScale)
                firstEpochPortion += _marginalA3AGain;
            if (_snapshots.scale + 1 == currentScale)
                secondEpochPortion += _marginalA3AGain;
        }
        uint256 gainPortions = firstEpochPortion -
            _snapshots.G +
            secondEpochPortion /
            SCALE_FACTOR;

        return
            (initialDeposit * (gainPortions)) /
            _snapshots.P /
            DECIMAL_PRECISION;
    }

    /// @dev gets compounded deposit of the user
    function _getCompoundedDepositFromSnapshots(
        uint256 _initialStake,
        Snapshots memory _snapshots
    ) internal view returns (uint256) {
        uint256 snapshot_P = _snapshots.P;

        // If stake was made before a pool-emptying event, then it has been fully cancelled with debt -- so, return 0
        if (_snapshots.epoch < currentEpoch) {
            return 0;
        }

        uint256 compoundedStake;
        uint128 scaleDiff = currentScale - _snapshots.scale;

        /* Compute the compounded stake. If a scale change in P was made during the stake's lifetime,
         * account for it. If more than one scale change was made, then the stake has decreased by a factor of
         * at least 1e-9 -- so return 0.
         */
        uint256 calculatedSnapshotP = snapshot_P == 0
            ? DECIMAL_PRECISION
            : snapshot_P;
        if (scaleDiff == 0) {
            compoundedStake = (_initialStake * P) / calculatedSnapshotP;
        } else if (scaleDiff == 1) {
            compoundedStake =
                (_initialStake * P) /
                calculatedSnapshotP /
                SCALE_FACTOR;
        } else {
            // if scaleDiff >= 2
            compoundedStake = 0;
        }

        /*
         * If compounded deposit is less than a billionth of the initial deposit, return 0.
         *
         * NOTE: originally, this line was in place to stop rounding errors making the deposit too large. However, the error
         * corrections should ensure the error in P "favors the Pool", i.e. any given compounded deposit should slightly less
         * than it's theoretical value.
         *
         * Thus it's unclear whether this line is still really needed.
         */
        if (compoundedStake < _initialStake / 1e9) {
            return 0;
        }

        return compoundedStake;
    }

    /// @dev Compute the StableCoin and Collateral rewards. Uses a "feedback" error correction, to keep
    /// the cumulative error in the P and S state variables low:s
    function _computeRewardsPerUnitStaked(
        address _collateralTokenAddress,
        uint256 _collToAdd,
        uint256 _debtToOffset,
        uint256 _totalStableCoinDeposits
    )
        internal
        returns (
            uint256 collateralGainPerUnitStaked,
            uint256 stableCoinLossPerUnitStaked
        )
    {
        /*
         * Compute the StableCoin and Collateral rewards. Uses a "feedback" error correction, to keep
         * the cumulative error in the P and S state variables low:
         *
         * 1) Form numerators which compensate for the floor division errors that occurred the last time this
         * function was called.
         * 2) Calculate "per-unit-staked" ratios.
         * 3) Multiply each ratio back by its denominator, to reveal the current floor division error.
         * 4) Store these errors for use in the next correction when this function is called.
         * 5) Note: static analysis tools complain about this "division before multiplication", however, it is intended.
         */
        uint256 collateralNumerator = _collToAdd *
            DECIMAL_PRECISION +
            collateralToLastErrorOffset[_collateralTokenAddress];

        assert(_debtToOffset <= _totalStableCoinDeposits);
        if (_debtToOffset == _totalStableCoinDeposits) {
            stableCoinLossPerUnitStaked = DECIMAL_PRECISION; // When the Pool depletes to 0, so does each deposit
            lastStableCoinLossErrorOffset = 0;
        } else {
            uint256 stableCoinLossNumerator = _debtToOffset *
                DECIMAL_PRECISION -
                lastStableCoinLossErrorOffset;
            /*
             * Add 1 to make error in quotient positive. We want "slightly too much" StableCoin loss,
             * which ensures the error in any given compoundedStableCoinDeposit favors the Stability Pool.
             */
            stableCoinLossPerUnitStaked =
                stableCoinLossNumerator /
                _totalStableCoinDeposits +
                1;
            lastStableCoinLossErrorOffset =
                stableCoinLossPerUnitStaked *
                _totalStableCoinDeposits -
                stableCoinLossNumerator;
        }

        collateralGainPerUnitStaked = (_totalStableCoinDeposits != 0)
            ? collateralNumerator / _totalStableCoinDeposits
            : 0;
        collateralToLastErrorOffset[_collateralTokenAddress] =
            collateralNumerator -
            collateralGainPerUnitStaked *
            _totalStableCoinDeposits;

        return (collateralGainPerUnitStaked, stableCoinLossPerUnitStaked);
    }

    /// @dev distributes A3A per minutes that was not spent yet
    function _triggerA3Adistribution() internal {
        uint256 issuance = _issueA3ARewards();
        _updateG(issuance);
    }

    function _issueA3ARewards() internal returns (uint256) {
        uint256 newA3ARewardTime = block.timestamp;
        uint256 totalA3ARewardsLeft_cached = totalA3ARewardsLeft;
        if (
            totalA3ARewardsLeft_cached == 0 ||
            a3aPerMinute == 0 ||
            totalDeposit == 0
        ) {
            latestA3ARewardTime = newA3ARewardTime;
            return 0;
        }

        uint256 timePassedInMinutes = (newA3ARewardTime - latestA3ARewardTime) /
            SECONDS_IN_ONE_MINUTE;
        uint256 issuance = a3aPerMinute * timePassedInMinutes;
        if (totalA3ARewardsLeft_cached < issuance) {
            issuance = totalA3ARewardsLeft_cached; // event will capture that 0 tokens left
        }
        uint256 newTotalA3ARewardsLeft = totalA3ARewardsLeft_cached - issuance;
        totalA3ARewardsLeft = newTotalA3ARewardsLeft;
        latestA3ARewardTime = newA3ARewardTime;

        emit A3ARewardIssue(issuance, newTotalA3ARewardsLeft);

        return issuance;
    }

    function _computeA3APerUnitStaked(
        uint256 _a3aIssuance,
        uint256 _totalStableCoinDeposits
    ) internal returns (uint256) {
        /*
         * Calculate the A3A-per-unit staked.  Division uses a "feedback" error correction, to keep the
         * cumulative error low in the running total G:
         *
         * 1) Form a numerator which compensates for the floor division error that occurred the last time this
         * function was called.
         * 2) Calculate "per-unit-staked" ratio.
         * 3) Multiply the ratio back by its denominator, to reveal the current floor division error.
         * 4) Store this error for use in the next correction when this function is called.
         * 5) Note: static analysis tools complain about this "division before multiplication", however, it is intended.
         */
        uint256 a3aNumerator = _a3aIssuance * DECIMAL_PRECISION + lastA3AError;

        uint256 a3aPerUnitStaked = a3aNumerator / _totalStableCoinDeposits;
        lastA3AError =
            a3aNumerator -
            (a3aPerUnitStaked * _totalStableCoinDeposits);

        return a3aPerUnitStaked;
    }

    /// @dev transfers collateral rewards tokens precalculated to the depositor
    function _sendCollateralRewardsToDepositor(
        TokenToUint256[] memory _depositorCollateralGains
    ) internal {
        for (uint256 i = 0; i < _depositorCollateralGains.length; i++) {
            if (_depositorCollateralGains[i].value == 0) {
                continue;
            }
            IERC20 collateralToken = IERC20(
                _depositorCollateralGains[i].tokenAddress
            );
            collateralToken.safeTransfer(
                msg.sender,
                _depositorCollateralGains[i].value
            );
            emit CollateralRewardRedeemed(
                msg.sender,
                _depositorCollateralGains[i].tokenAddress,
                _depositorCollateralGains[i].value
            );
        }
    }

    /// @dev transfers A3A amount to the user
    function _sendA3ARewardsToDepositor(uint256 _a3aGain) internal {
        a3aToken.transfer(msg.sender, _a3aGain);
    }
}

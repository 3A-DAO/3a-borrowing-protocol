// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/interfaces/IERC20Metadata.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/Context.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import '../interfaces/IPriceFeed.sol';
import '../interfaces/IVaultFactory.sol';
import '../interfaces/IVaultFactoryConfig.sol';
import '../interfaces/ILiquidationRouter.sol';
import '../interfaces/ISmartVaultProxy.sol';

import '../utils/constants.sol';
import '../interfaces/ITokenPriceFeed.sol';
import '../interfaces/IVaultExtraSettings.sol';
import '../utils/linked-address-list.sol';

/**
 * @title Smart Vault
 * @dev Manages creation, collateralization, borrowing, liquidation of Vaults and whitelisted methods.
 */

contract SmartVault is Context, Constants {
    string public constant VERSION = '1.3.0';

    // Events emitted by the contract
    event CollateralAdded(
        address indexed collateral,
        uint256 amount,
        uint256 newTotalAmount
    );
    event CollateralRemoved(
        address indexed collateral,
        uint256 amount,
        uint256 newTotalAmount
    );
    event CollateralRedeemed(
        address indexed collateral,
        uint256 amount,
        uint256 newTotalAmount,
        uint256 stableAmountUsed,
        uint256 feePaid
    );

    event Executed(
        address indexed caller,
        address indexed target,
        bytes4 funcSignature,
        bytes data
    );

    event DebtAdded(uint256 amount, uint256 newTotalDebt);
    event DebtRepaid(uint256 amount, uint256 newTotalDebt);
    event RewardsClaimmed(address token, uint256 amount);

    modifier onlyFactory() {
        require(_msgSender() == factory, 'only-factory');
        _;
    }

    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    address public immutable stable;
    address public immutable factory;
    address public vaultOwner;

    string public name;

    EnumerableSet.AddressSet private collateralSet;
    EnumerableSet.AddressSet private operators;

    IVaultExtraSettings public vaultExtraSettings;
    ISmartVaultProxy public smartVaultProxy;
    mapping(address => uint256) public collateral;

    uint256 public debt;

    modifier onlyVaultOwner() {
        require(_msgSender() == vaultOwner, 'only-vault-owner');
        _;
    }

    /**
     * @dev Constructor to initialize the Vault contract.
     * @param _factory Address of the VaultFactory contract.
     * @param _vaultOwner Address of the initial owner of the Vault.
     * @param _name Name of the Vault.
     * @param _vaultExtraSettings Vault extra settings address.
     * @param _smartVaultProxy Smart Vault Proxy address.
     */
    constructor(
        address _factory,
        address _vaultOwner,
        string memory _name,
        IVaultExtraSettings _vaultExtraSettings,
        ISmartVaultProxy _smartVaultProxy
    ) {
        require(_vaultOwner != address(0x0), 'vault-owner-is-0');
        require(bytes(_name).length > 0, 'name-is-empty');
        require(_factory != address(0x0), 'factory-is-0');
        require(
            address(_vaultExtraSettings) != address(0x0),
            'vault-extra-settings-is-0'
        );
        require(address(_smartVaultProxy) != address(0x0), 'vault-proxy-is-0');

        factory = _factory;
        vaultOwner = _vaultOwner;
        stable = IVaultFactory(factory).stable();
        name = _name;
        vaultExtraSettings = _vaultExtraSettings;
        smartVaultProxy = _smartVaultProxy;
    }

    /**
     * @dev Transfers ownership of the Vault to a new owner.
     * @param _newOwner Address of the new owner.
     */
    function transferVaultOwnership(address _newOwner) external onlyFactory {
        vaultOwner = _newOwner;
    }

    /**
     * @dev Executes a batch of functions on target addresses only if the methods are allowed.
     * @param _targets The contract addresses where the functions will be called.
     * @param _signatures The signatures of the functions to be executed.
     * @param _data The data to be passed to the functions.
     * @param _claimRewards The pending reward tokens to transfer to the owner vault - Optional.
     * @return _results The result of the function execution.
     */
    function executeBatch(
        address[] memory _targets,
        bytes4[] memory _signatures,
        bytes[] memory _data,
        address[] memory _claimRewards
    ) external onlyVaultOwner returns (bytes[] memory _results) {
        require(_targets.length > 0, 'Targets array cannot be empty');
        require(_signatures.length > 0, 'Signatures array cannot be empty');
        require(_data.length > 0, 'Data array cannot be empty');
        require(
            _targets.length == _signatures.length &&
                _targets.length == _data.length,
            'Lengths of targets, functions, and data arrays must match'
        );

        _results = new bytes[](_targets.length);

        for (uint i = 0; i < _targets.length; i++) {
            _results[i] = execute(_targets[i], _signatures[i], _data[i]);
        }

        if (_claimRewards.length > 0) {
            for (uint i = 0; i < _claimRewards.length; ) {
                _claimPendingRewards(_claimRewards[i]);
                unchecked {
                    i++;
                }
            }
        }

        return _results;
    }

    /**
     * @dev Executes a function on a target address only if the method is allowed.
     * @param _target The contract address where the function will be called.
     * @param _signature The signature of the function to be executed.
     * @param _data The data to be passed to the function.
     * @return _result The result of the function execution.
     */
    function execute(
        address _target,
        bytes4 _signature,
        bytes memory _data
    ) private returns (bytes memory _result) {
        require(
            smartVaultProxy.isWhitelisted(_target, _signature),
            'invalid-permission'
        );
        emit Executed(_msgSender(), _target, _signature, _data);
        _result = Address.functionCall(
            _target,
            bytes.concat(_signature, _data)
        );
    }

    /**
     * @dev Sets a new name for the Vault.
     * @param _name New name for the Vault.
     */
    function setName(string memory _name) external onlyVaultOwner {
        require(bytes(_name).length > 0, 'name-is-empty');
        name = _name;
    }

    /**
     * @dev Adds an operator to the Vault, allowing them certain permissions.
     * @param _operator Address of the operator to be added.
     */
    function addOperator(address _operator) external onlyVaultOwner {
        require(_operator != address(0x0), 'operator-is-0');
        operators.add(_operator);
    }

    /**
     * @dev Removes an operator from the Vault, revoking their permissions.
     * @param _operator Address of the operator to be removed.
     */
    function removeOperator(address _operator) external onlyVaultOwner {
        require(_operator != address(0x0), 'operator-is-0');
        operators.remove(_operator);
    }

    /**
     * @dev Checks if an address is an operator for this Vault.
     * @param _operator Address to check.
     * @return Boolean indicating whether the address is an operator.
     */
    function isOperator(address _operator) external view returns (bool) {
        return operators.contains(_operator);
    }

    /**
     * @dev Returns the number of operators in the Vault.
     * @return Length of the operators set.
     */
    function operatorsLength() external view returns (uint256) {
        return operators.length();
    }

    /**
     * @dev Returns the operator at a given index in the operators set.
     * @param _index Index of the operator.
     * @return Address of the operator at the given index.
     */
    function operatorAt(uint256 _index) external view returns (address) {
        return operators.at(_index);
    }

    /**
     * @dev Checks if a collateral token is added to the Vault.
     * @param _collateral Address of the collateral token to check.
     * @return Boolean indicating whether the collateral token is added.
     */
    function containsCollateral(
        address _collateral
    ) external view returns (bool) {
        return collateralSet.contains(_collateral);
    }

    /**
     * @dev Returns the number of collateral tokens added to the Vault.
     * @return Length of the collateral set.
     */
    function collateralsLength() external view returns (uint256) {
        return collateralSet.length();
    }

    /**
     * @dev Returns the collateral token address at a given index in the collateral set.
     * @param _index Index of the collateral token.
     * @return Address of the collateral token at the given index.
     */
    function collateralAt(uint256 _index) external view returns (address) {
        return collateralSet.at(_index);
    }

    /**
     * @dev Returns an array containing all collateral token addresses in the Vault.
     * @return Array of collateral token addresses.
     */
    function collaterals() external view returns (address[] memory) {
        address[] memory _collaterals = new address[](collateralSet.length());
        for (uint256 i = 0; i < collateralSet.length(); i++) {
            _collaterals[i] = collateralSet.at(i);
        }
        return _collaterals;
    }

    /**
     * @dev Adds a new collateral token to the Vault and updates the collateral amount.
     * @param _collateral Address of the collateral token to add.
     * @param _amount Amount of the collateral token to add.
     */
    function addCollateral(
        address _collateral,
        uint256 _amount
    ) external onlyFactory {
        require(_collateral != address(0x0), 'collateral-is-0');
        require(_amount > 0, 'amount-is-0');

        collateralSet.add(_collateral);
        uint256 _maxTokens = IVaultFactory(factory).MAX_TOKENS_PER_VAULT();
        require(collateralSet.length() <= _maxTokens, 'max-tokens-reached');

        collateral[_collateral] += _amount;

        emit CollateralAdded(_collateral, _amount, collateral[_collateral]);
    }

    /**
     * @dev Removes a collateral token from the Vault and transfers it back to the sender.
     * @param _collateral Address of the collateral token to remove.
     * @param _amount Amount of the collateral token to remove.
     * @param _to Address to receive the removed collateral.
     */
    function removeCollateral(
        address _collateral,
        uint256 _amount,
        address _to
    ) external onlyFactory {
        require(_collateral != address(0x0), 'collateral-is-0');
        require(_amount > 0, 'amount-is-0');

        collateral[_collateral] -= _amount;
        if (collateral[_collateral] == 0) {
            collateralSet.remove(_collateral);
        }

        uint256 _healthFactor = healthFactor(false);
        require(_healthFactor >= DECIMAL_PRECISION, 'health-factor-below-1');

        IERC20(_collateral).safeTransfer(_to, _amount);

        emit CollateralRemoved(_collateral, _amount, collateral[_collateral]);
    }

    /**
     * @dev Adds bad debt to the Vault.
     * @param _amount Amount of bad debt to add.
     */
    function addBadDebt(uint256 _amount) external onlyFactory {
        require(_amount > 0, 'amount-is-0');

        debt += _amount;
        emit DebtAdded(_amount, debt);
    }

    /**
     * @dev Calculates the maximum borrowable amount and the current borrowable amount.
     * @return _maxBorrowable Maximum borrowable amount.
     * @return _borrowable Current borrowable amount.
     */
    function borrowable()
        public
        view
        returns (uint256 _maxBorrowable, uint256 _borrowable)
    {
        (_maxBorrowable, _borrowable) = borrowableWithDiff(
            address(0x0),
            0,
            false,
            false
        );
    }

    /**
     * @dev Borrows a specified amount from the Vault.
     * @param _amount Amount to borrow.
     */
    function borrow(uint256 _amount) external onlyFactory {
        require(_amount > 0, 'amount-is-0');

        (uint256 _maxBorrowable, uint256 _borrowable) = borrowable();
        require(_amount <= _borrowable, 'not-enough-borrowable');

        debt += _amount;
        require(debt <= _maxBorrowable, 'max-borrowable-reached');

        emit DebtAdded(_amount, debt);
    }

    /**
     * @dev Repays a specified amount to the Vault's debt.
     * @param _amount Amount to repay.
     */
    function repay(uint256 _amount) external onlyFactory {
        require(_amount <= debt, 'amount-exceeds-debt');

        debt -= _amount;
        emit DebtRepaid(_amount, debt);
    }

    /**
     * @dev Calculates the stable amount needed and the redemption fee for redeeming collateral.
     * @param _collateral Address of the collateral token.
     * @param _collateralAmount Amount of collateral to redeem.
     * @return _stableAmountNeeded Stablecoin amount required to redeem collateral.
     * @return _redemptionFee Fee charged for the redemption.
     */
    function calcRedeem(
        address _collateral,
        uint256 _collateralAmount
    )
        public
        view
        returns (uint256 _stableAmountNeeded, uint256 _redemptionFee)
    {
        ITokenPriceFeed _priceFeed = ITokenPriceFeed(
            IVaultFactory(factory).priceFeed()
        );
        uint256 _price = _priceFeed.tokenPrice(_collateral);

        uint256 _normalizedCollateralAmount = _collateralAmount *
            (10 ** (18 - _priceFeed.decimals(_collateral)));
        _stableAmountNeeded =
            (_normalizedCollateralAmount * _price) /
            DECIMAL_PRECISION;

        (, , uint256 _redemptionKickbackRate) = vaultExtraSettings
            .getExtraSettings();

        if (_redemptionKickbackRate > 0) {
            uint256 _kickbackAmount = (_stableAmountNeeded *
                _redemptionKickbackRate) / DECIMAL_PRECISION;
            _stableAmountNeeded += _kickbackAmount;
        }
        uint256 _redemptionRate = IVaultFactoryConfig(factory).redemptionRate();
        _redemptionFee =
            (_stableAmountNeeded * _redemptionRate) /
            DECIMAL_PRECISION;
    }

    /**
     * @dev Redeems a specified amount of collateral, repays debt, and transfers collateral back to the redeemer.
     * @param _collateral Address of the collateral token to redeem.
     * @param _collateralAmount Amount of collateral to redeem.
     * @return _debtRepaid Amount of debt repaid.
     * @return _feeCollected Fee collected for the redemption.
     */
    function redeem(
        address _collateral,
        uint256 _collateralAmount
    )
        external
        onlyFactory
        returns (uint256 _debtRepaid, uint256 _feeCollected)
    {
        require(_collateral != address(0x0), 'collateral-is-0');
        require(_collateralAmount > 0, 'amount-is-0');
        require(collateralSet.contains(_collateral), 'collateral-not-added');
        require(
            collateral[_collateral] >= _collateralAmount,
            'not-enough-collateral'
        );

        uint256 _currentHealthFactor = healthFactor(true);
        uint256 _redemptionHealthFactorLimit = IVaultFactoryConfig(factory)
            .redemptionHealthFactorLimit();
        require(
            _currentHealthFactor < _redemptionHealthFactorLimit,
            'health-factor-above-redemption-limit'
        );

        (
            uint256 _debtTreshold,
            uint256 _maxRedeemablePercentage,

        ) = vaultExtraSettings.getExtraSettings();

        collateral[_collateral] -= _collateralAmount;
        (_debtRepaid, _feeCollected) = calcRedeem(
            _collateral,
            _collateralAmount
        );

        if (debt > _debtTreshold) {
            uint256 _redeemableDebt = (debt * _maxRedeemablePercentage) /
                DECIMAL_PRECISION;
            require(_debtRepaid <= _redeemableDebt, 'redeemable-debt-exceeded');
        }

        debt -= _debtRepaid;

        if (collateral[_collateral] == 0) {
            collateralSet.remove(_collateral);
        }

        IERC20(_collateral).safeTransfer(_msgSender(), _collateralAmount);

        emit CollateralRedeemed(
            _collateral,
            _collateralAmount,
            collateral[_collateral],
            _debtRepaid,
            _feeCollected
        );
        emit DebtRepaid(_debtRepaid, debt);
    }

    /**
     * @dev Computes the health factor of the Vault.
     * @param _useMlr Flag to use Minimum Loan Ratio (MLR) in health factor computation.
     * @return _healthFactor Current health factor.
     */
    function healthFactor(
        bool _useMlr
    ) public view returns (uint256 _healthFactor) {
        if (debt == 0) {
            return type(uint256).max;
        }

        (uint256 _maxBorrowable, ) = borrowableWithDiff(
            address(0x0),
            0,
            false,
            _useMlr
        );

        _healthFactor = (_maxBorrowable * DECIMAL_PRECISION) / debt;
    }

    /**
     * @dev Computes a new health factor given a new debt value.
     * @param _newDebt New debt amount to calculate the health factor.
     * @param _useMlr Flag to use Minimum Loan Ratio (MLR) in health factor computation.
     * @return _newHealthFactor Calculated new health factor based on the new debt value.
     */
    function newHealthFactor(
        uint256 _newDebt,
        bool _useMlr
    ) public view returns (uint256 _newHealthFactor) {
        if (_newDebt == 0) {
            return type(uint256).max;
        }

        (uint256 _maxBorrowable, ) = borrowableWithDiff(
            address(0x0),
            0,
            false,
            _useMlr
        );
        _newHealthFactor = (_maxBorrowable * DECIMAL_PRECISION) / _newDebt;
    }

    /**
     * @dev Computes the maximum borrowable amount and the current borrowable amount.
     * @param _collateral Address of the collateral token (0x0 for total vault borrowable).
     * @param _diffAmount Difference in collateral amount when adding/removing collateral.
     * @param _isAdd Flag indicating whether the collateral is added or removed.
     * @param _useMlr Flag to use Minimum Loan Ratio (MLR) in borrowable computation.
     * @return _maxBorrowable Maximum borrowable amount.
     * @return _borrowable Current borrowable amount based on the collateral.
     */
    function borrowableWithDiff(
        address _collateral,
        uint256 _diffAmount,
        bool _isAdd,
        bool _useMlr
    ) public view returns (uint256 _maxBorrowable, uint256 _borrowable) {
        uint256 _newCollateralAmount = collateral[_collateral];

        uint256 _borrowableAmount = 0;

        if (_collateral != address(0x0)) {
            require(
                IVaultFactory(factory).isCollateralSupported(_collateral),
                'collateral-not-supported'
            );
            if (_isAdd) {
                _newCollateralAmount += _diffAmount;
            } else {
                _newCollateralAmount -= _diffAmount;
            }
        }

        ITokenPriceFeed _priceFeed = ITokenPriceFeed(
            IVaultFactory(factory).priceFeed()
        );

        for (uint256 i = 0; i < collateralSet.length(); i++) {
            address _c = collateralSet.at(i);
            uint256 _collateralAmount = _c == _collateral
                ? _newCollateralAmount
                : collateral[_c];
            uint256 _price = _priceFeed.tokenPrice(_c);
            uint256 _divisor = _useMlr
                ? _priceFeed.mlr(_c)
                : _priceFeed.mcr(_c);
            uint256 _normalizedCollateralAmount = _collateralAmount *
                (10 ** (18 - _priceFeed.decimals(_c)));

            uint256 _collateralBorrowable = (_normalizedCollateralAmount *
                _price) / DECIMAL_PRECISION;

            _borrowableAmount +=
                (_collateralBorrowable * DECIMAL_PRECISION) /
                _divisor;
        }

        return (
            _borrowableAmount,
            (_borrowableAmount > debt) ? _borrowableAmount - debt : 0
        );
    }

    /**
     * @dev Liquidates the vault by repaying all debts with seized collateral.
     * @return _forgivenDebt Amount of debt forgiven during liquidation.
     * @return _liquidatedCollaterals Collateral Addresses liquidated..
     * @return _liquidatedAmounts Collateral Amounts liquidated.
     */
    function liquidate()
        external
        onlyFactory
        returns (
            uint256 _forgivenDebt,
            address[] memory _liquidatedCollaterals,
            uint256[] memory _liquidatedAmounts
        )
    {
        require(
            healthFactor(true) < DECIMAL_PRECISION,
            'liquidation-factor-above-1'
        );

        uint256 _debt = debt;
        debt = 0;
        ILiquidationRouter router = ILiquidationRouter(
            IVaultFactory(factory).liquidationRouter()
        );

        _liquidatedCollaterals = new address[](collateralSet.length());
        _liquidatedAmounts = new uint256[](collateralSet.length());

        for (uint256 i = 0; i < collateralSet.length(); i++) {
            address _collateral = collateralSet.at(i);
            uint256 _collateralAmount = collateral[_collateral];
            uint256 _actualCollateralBalance = IERC20(_collateral).balanceOf(
                address(this)
            );
            if (_actualCollateralBalance < _collateralAmount) {
                _collateralAmount = _actualCollateralBalance;
            }
            collateral[_collateral] = 0;

            IERC20(_collateral).safeApprove(
                IVaultFactory(factory).liquidationRouter(),
                0
            );
            IERC20(_collateral).safeApprove(
                IVaultFactory(factory).liquidationRouter(),
                _collateralAmount
            );

            _liquidatedCollaterals[i] = _collateral;
            _liquidatedAmounts[i] = _collateralAmount;

            router.addSeizedCollateral(_collateral, _collateralAmount);
        }
        router.addUnderWaterDebt(address(this), _debt);
        router.tryLiquidate();
        _forgivenDebt = _debt;

        return (_forgivenDebt, _liquidatedCollaterals, _liquidatedAmounts);
    }

    /**
     * @dev Claims pending rewards for a specific token.
     * @param _token The token address for which rewards are being claimed.
     */
    function _claimPendingRewards(address _token) private {
        require(
            !IVaultFactory(factory).isCollateralSupported(_token),
            'cant-transfer-collateral'
        );
        uint256 balance = IERC20(_token).balanceOf(address(this));
        uint256 fee = (balance * smartVaultProxy.rewardFee()) / 10000;

        require(
            IERC20(_token).transfer(vaultOwner, balance - fee),
            'reward-claim-failed'
        );
        require(
            IERC20(_token).transfer(smartVaultProxy.rewardCollector(), fee),
            'reward-fee-claim-failed'
        );

        emit RewardsClaimmed(_token, balance);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IVault {
    function vaultOwner() external view returns (address);
    function debt() external view returns (uint256);
    function transferVaultOwnership(address _newOwner) external;
    function setName(string memory _name) external;
    function containsCollateral(
        address _collateral
    ) external view returns (bool);
    function collateralsLength() external view returns (uint256);
    function collateralAt(uint256 _index) external view returns (address);
    function collaterals() external view returns (address[] memory);
    function collateral(address _collateral) external view returns (uint256);
    function factory() external view returns (address);
    function addCollateral(address _collateral, uint256 _amount) external;
    function removeCollateral(
        address _collateral,
        uint256 _amount,
        address _to
    ) external;
    function addBadDebt(uint256 _amount) external;
    function borrowable()
        external
        view
        returns (uint256 _maxBorrowable, uint256 _borrowable);
    function borrow(uint256 _amount) external;
    function repay(uint256 _amount) external;
    function calcRedeem(
        address _collateral,
        uint256 _collateralAmount
    )
        external
        view
        returns (uint256 _stableAmountNeeded, uint256 _redemptionFee);
    function redeem(
        address _collateral,
        uint256 _collateralAmount
    ) external returns (uint256 _debtRepaid, uint256 _feeCollected);
    function healthFactor(
        bool _useMlr
    ) external view returns (uint256 _healthFactor);
    function newHealthFactor(
        uint256 _newDebt,
        bool _useMlr
    ) external view returns (uint256 _newHealthFactor);
    function borrowableWithDiff(
        address _collateral,
        uint256 _diffAmount,
        bool _isAdd,
        bool _useMlr
    ) external view returns (uint256 _maxBorrowable, uint256 _borrowable);
    function liquidate() external returns (uint256 _forgivenDebt);
}

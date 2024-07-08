// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IVaultFactory {
    event NewVault(address indexed vault, string name, address indexed owner);
    event PriceFeedUpdated(address indexed priceFeed);

    function setPriceFeed(address _priceFeed) external;
    function vaultCount() external view returns (uint256);
    function lastVault() external view returns (address);
    function firstVault() external view returns (address);
    function nextVault(address _vault) external view returns (address);
    function prevVault(address _vault) external view returns (address);
    function liquidationRouter() external view returns (address);
    function MAX_TOKENS_PER_VAULT() external view returns (uint256);
    function priceFeed() external view returns (address);
    function transferVaultOwnership(address _vault, address _newOwner) external;
    function createVault(string memory _name) external returns (address);
    function addCollateralNative(address _vault) external payable;
    function removeCollateralNative(
        address _vault,
        uint256 _amount,
        address _to
    ) external;
    function addCollateral(
        address _vault,
        address _collateral,
        uint256 _amount
    ) external;
    function removeCollateral(
        address _vault,
        address _collateral,
        uint256 _amount,
        address _to
    ) external;
    function borrow(address _vault, uint256 _amount, address _to) external;
    function distributeBadDebt(address _vault, uint256 _amount) external;
    function closeVault(address _vault) external;
    function repay(address _vault, uint256 _amount) external;
    function redeem(
        address _vault,
        address _collateral,
        uint256 _collateralAmount,
        address _to
    ) external;
    function liquidate(address _vault) external;
    function isLiquidatable(address _vault) external view returns (bool);
    function isReedemable(
        address _vault,
        address _collateral
    ) external view returns (bool);
    function containsVault(address _vault) external view returns (bool);
    function stable() external view returns (address);
    function isCollateralSupported(
        address _collateral
    ) external view returns (bool);
    function vaultsByOwnerLength(
        address _owner
    ) external view returns (uint256);
    function redemptionHealthFactorLimit() external view returns (uint256);
}

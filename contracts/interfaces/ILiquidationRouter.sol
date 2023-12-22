// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface ILiquidationRouter {
    function addSeizedCollateral(address _collateral, uint256 _amount) external;

    function addUnderWaterDebt(address _vault, uint256 _amount) external;

    function removeUnderWaterDebt(uint256 _amount) external;

    function underWaterDebt() external view returns (uint256);

    function collaterals() external view returns (address[] memory);

    function collateral(address _collateral) external view returns (uint256);

    function tryLiquidate() external;

    function stabilityPool() external view returns (address);
    function auctionManager() external view returns (address);
    function lastResortLiquidation() external view returns (address);
    function distributeBadDebt(address _vault, uint256 _amount) external;
    function transferOwnership(address newOwner) external;
}

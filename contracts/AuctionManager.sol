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
import "./interfaces/ILiquidationRouter.sol";
import "./interfaces/ITokenPriceFeed.sol";
import "./interfaces/IMintableToken.sol";
import "./interfaces/ILastResortLiquidation.sol";
import "./utils/constants.sol";

/**
 * @title AuctionManager.
 * @dev Manages auctions for liquidating collateral in case of debt default.
 */
contract AuctionManager is Ownable, ReentrancyGuard, Constants {
    using SafeERC20 for IERC20;
    using SafeERC20 for IMintableToken;

    // Auction duration and lowest health factor
    uint256 public auctionDuration = 2 hours;

    uint256 public lowestHF = 1.05 ether; // 105%

    // Struct to hold auction data
    struct auctionData {
        uint256 originalDebt;
        uint256 lowestDebtToAuction;
        uint256 highestDebtToAuction;
        uint256 collateralsLength;
        address[] collateral;
        uint256[] collateralAmount;
        uint256 auctionStartTime;
        uint256 auctionEndTime;
        bool auctionEnded;
    }

    // Array to store auction data.
    auctionData[] public auctions;

    address public vaultFactory;

    // Events.
    event VaultFactoryUpdated(address indexed _vaultFactory);
    event AuctionDurationUpdated(uint256 _auctionDuration);
    event AuctionCreated(
        uint256 indexed _auctionId,
        uint256 _originalDebt,
        uint256 _lowestDebtToAuction,
        uint256 _highestDebtToAuction,
        uint256 _collateralsLength,
        address[] _collateral,
        uint256[] _collateralAmount,
        uint256 _auctionStartTime,
        uint256 _auctionEndTime
    );
    event AuctionWon(
        uint256 indexed _auctionId,
        address indexed _winner,
        uint256 _debtRepaid,
        uint256 _collateralValueGained
    );
    event AuctionEnded(uint256 indexed _auctionId);

    /**
     * @notice Sets the duration of each auction.
     * @dev Can only be called by the contract owner.
     * @param _auctionDuration Duration of the auction.
     */
    function setAuctionDuration(uint256 _auctionDuration) external onlyOwner {
        require(_auctionDuration > 0, "auction-duration-is-0");
        auctionDuration = _auctionDuration;
        emit AuctionDurationUpdated(_auctionDuration);
    }

    /**
     * @notice Sets the lowest health factor allowed for bidding.
     * @dev Can only be called by the contract owner.
     * @param _lowestHF Lowest health factor allowed for bidding.
     */
    function setLowestHealthFactor(uint256 _lowestHF) external onlyOwner {
        require(_lowestHF > 0, "lowest-hf-is-0");
        lowestHF = _lowestHF;
    }

    /**
     * @dev Sets the address of the vault factory. Can only be called by the contract owner.
     * @param _vaultFactory Address of the vault factory.
     */
    function setVaultFactory(address _vaultFactory) external onlyOwner {
        require(_vaultFactory != address(0x0), "vault-factory-is-0");
        vaultFactory = _vaultFactory;
        emit VaultFactoryUpdated(_vaultFactory);
    }

    /**
     * @dev Returns the total number of auctions created.
     * @return The total number of auctions.
     */
    function auctionsLength() external view returns (uint256) {
        return auctions.length;
    }

    /**
     * @dev Get auction information by ID.
     * @param _auctionId The ID of the auction.
     * @return Auction data structure.
     */
    function auctionInfo(uint256 _auctionId) external view returns (auctionData memory) {
        return auctions[_auctionId];
    }

    /**
     * @dev Contract constructor to initialize the vault factory address.
     * @param _vaultFactory Address of the vault factory.
     */
    constructor(address _vaultFactory) {
        require(_vaultFactory != address(0x0), "vault-factory-is-0");
        vaultFactory = _vaultFactory;
        emit VaultFactoryUpdated(_vaultFactory);
    }

    /**
     * @notice Calculate total collateral value for a specific auction.
     * @param _auctionId The ID of the auction.
     * @return Total collateral value.
     */
    function getTotalCollateralValue(uint256 _auctionId) public view returns (uint256) {
        auctionData memory _auction = auctions[_auctionId];
        ITokenPriceFeed _priceFeed = ITokenPriceFeed(IVaultFactory(vaultFactory).priceFeed());
        uint256 _totalCollateralValue = 0;
        for (uint256 i = 0; i < _auction.collateralsLength; i++) {
            uint256 _price = _priceFeed.tokenPrice(_auction.collateral[i]);
            uint256 _normalizedCollateralAmount = _auction.collateralAmount[i] *
                (10 ** (18 - _priceFeed.decimals(_auction.collateral[i])));
            uint256 _collateralValue = (_normalizedCollateralAmount * _price) / DECIMAL_PRECISION;
            _totalCollateralValue += _collateralValue;
        }
        return _totalCollateralValue;
    }

    /**
     * @dev Creates a new auction to liquidate underwater debt against collaterals.
     * Accessible only by the liquidation router.
     * @notice Allows the liquidation router to initiate a new auction for the collateralized debt.
     */
    function newAuction() external {
        ILiquidationRouter liquidationRouter = ILiquidationRouter(IVaultFactory(vaultFactory).liquidationRouter());
        require(msg.sender == address(liquidationRouter), "not-allowed");

        uint256 _debtToAuction = liquidationRouter.underWaterDebt();
        require(_debtToAuction > 0, "no-debt-to-auction");

        address[] memory _collaterals = liquidationRouter.collaterals();
        uint256[] memory _collateralAmounts = new uint256[](_collaterals.length);
        uint256 _collateralsLength = _collaterals.length;
        require(_collateralsLength > 0, "no-collaterals");

        uint256 _totalCollateralValue = 0;

        ITokenPriceFeed _priceFeed = ITokenPriceFeed(IVaultFactory(vaultFactory).priceFeed());

        for (uint256 i = 0; i < _collateralsLength; i++) {
            IERC20 collateralToken = IERC20(_collaterals[i]);
            uint256 _collateralAmount = liquidationRouter.collateral(_collaterals[i]);
            collateralToken.safeTransferFrom(address(liquidationRouter), address(this), _collateralAmount);
            _collateralAmounts[i] = _collateralAmount;

            uint256 _price = _priceFeed.tokenPrice(address(collateralToken));
            uint256 _normalizedCollateralAmount = _collateralAmount *
                (10 ** (18 - _priceFeed.decimals(address(collateralToken))));
            uint256 _collateralValue = (_normalizedCollateralAmount * _price) / DECIMAL_PRECISION;
            _totalCollateralValue += _collateralValue;
        }

        uint256 _auctionStartTime = block.timestamp;
        uint256 _auctionEndTime = _auctionStartTime + auctionDuration;

        uint256 _lowestDebtToAuction = (_totalCollateralValue * lowestHF) / DECIMAL_PRECISION;
        uint256 _highestDebtToAuction = _debtToAuction;

        if (_highestDebtToAuction < _lowestDebtToAuction) {
            uint256 _debtToAuctionTmp = _lowestDebtToAuction;
            _lowestDebtToAuction = _highestDebtToAuction;
            _highestDebtToAuction = _debtToAuctionTmp;
        }

        auctions.push(
            auctionData({
                originalDebt: _debtToAuction,
                lowestDebtToAuction: _lowestDebtToAuction,
                highestDebtToAuction: _highestDebtToAuction,
                collateralsLength: _collateralsLength,
                collateral: _collaterals,
                collateralAmount: _collateralAmounts,
                auctionStartTime: _auctionStartTime,
                auctionEndTime: _auctionEndTime,
                auctionEnded: false
            })
        );

        emit AuctionCreated(
            auctions.length - 1,
            _debtToAuction,
            _lowestDebtToAuction,
            _highestDebtToAuction,
            _collateralsLength,
            _collaterals,
            _collateralAmounts,
            _auctionStartTime,
            _auctionEndTime
        );
    }

    /**
     * @dev Get auction bid information.
     * @param _auctionId The ID of the auction.
     * @return _totalCollateralValue Total collateral value.
     * @return _debtToAuctionAtCurrentTime Debt to auction at the current time.
     */
    function bidInfo(
        uint256 _auctionId
    ) external view returns (uint256 _totalCollateralValue, uint256 _debtToAuctionAtCurrentTime) {
        auctionData memory _auction = auctions[_auctionId];
        require(!_auction.auctionEnded && block.timestamp <= _auction.auctionEndTime, "auction-ended");

        _totalCollateralValue = getTotalCollateralValue(_auctionId);
        uint256 _highestDebtToAuction = _auction.highestDebtToAuction;
        uint256 _lowestDebtToAuction = _auction.lowestDebtToAuction;
        // decrease _debtToAuction linearly to _lowestDebtToAuction over the auction duration
        _debtToAuctionAtCurrentTime =
            _highestDebtToAuction -
            ((_highestDebtToAuction - _lowestDebtToAuction) * (block.timestamp - _auction.auctionStartTime)) /
            auctionDuration;
    }

    /**
     * @dev Transfer collateral to the last resort liquidation contract.
     * @param _auctionId The ID of the auction.
     */
    function _transferToLastResortLiquidation(uint256 _auctionId) internal {
        ILiquidationRouter _liquidationRouter = ILiquidationRouter(IVaultFactory(vaultFactory).liquidationRouter());
        ILastResortLiquidation _lastResortLiquidation = ILastResortLiquidation(_liquidationRouter.lastResortLiquidation());

        auctionData memory _auction = auctions[_auctionId];
        uint256 _collateralsLength = _auction.collateralsLength;
        address[] memory _collaterals = _auction.collateral;
        uint256[] memory _collateralAmounts = _auction.collateralAmount;
        uint256 _badDebt = _auction.originalDebt;

        _lastResortLiquidation.addBadDebt(_badDebt);
        for (uint256 i = 0; i < _collateralsLength; i++) {
            IERC20 collateralToken = IERC20(_collaterals[i]);
            collateralToken.safeApprove(address(_lastResortLiquidation), 0);
            collateralToken.safeApprove(address(_lastResortLiquidation), _collateralAmounts[i]);
            _lastResortLiquidation.addCollateral(address(collateralToken), _collateralAmounts[i]);
        }
    }

    /**
     * @dev Sends a bid from the caller to the auction for a specific auction ID.
     * @param _auctionId The ID of the auction.
     * @notice Allows a bidder to participate in the auction by placing a bid.
     * If the auction period is over or has been manually ended, it transfers the bid to the last resort liquidation.
     */
    function bid(uint256 _auctionId) external nonReentrant {
        auctionData memory _auction = auctions[_auctionId];
        require(!_auction.auctionEnded, "auction-ended");

        if (block.timestamp > _auction.auctionEndTime) {
            // auction ended
            auctions[_auctionId].auctionEnded = true;
            _transferToLastResortLiquidation(_auctionId);
            emit AuctionEnded(_auctionId);
            return;
        }

        uint256 _totalCollateralValue = getTotalCollateralValue(_auctionId);
        uint256 _highestDebtToAuction = _auction.highestDebtToAuction;
        uint256 _lowestDebtToAuction = _auction.lowestDebtToAuction;
        // decrease _debtToAuction linearly to _lowestDebtToAuction over the auction duration
        uint256 _debtToAuctionAtCurrentTime = _highestDebtToAuction -
            ((_highestDebtToAuction - _lowestDebtToAuction) * (block.timestamp - _auction.auctionStartTime)) /
            auctionDuration;

        IMintableToken _stable = IMintableToken(IVaultFactory(vaultFactory).stable());
        _stable.safeTransferFrom(msg.sender, address(this), _debtToAuctionAtCurrentTime);
        _stable.burn(_debtToAuctionAtCurrentTime);

        uint256 _collateralsLength = _auction.collateralsLength;

        for (uint256 i = 0; i < _collateralsLength; i++) {
            IERC20 collateralToken = IERC20(_auction.collateral[i]);
            collateralToken.safeTransfer(msg.sender, _auction.collateralAmount[i]);
        }

        auctions[_auctionId].auctionEnded = true;
        emit AuctionWon(_auctionId, msg.sender, _debtToAuctionAtCurrentTime, _totalCollateralValue);
    }
}

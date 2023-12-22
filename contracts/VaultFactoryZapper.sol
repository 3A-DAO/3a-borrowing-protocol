// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./interfaces/IVaultFactory.sol";
import "./interfaces/IVault.sol";
import "./interfaces/ITokenPriceFeed.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title VaultFactoryZapper
 * @dev A contract that facilitates the creation of Vaults and manages their operations.
 */
contract VaultFactoryZapper is Ownable {
    using SafeERC20 for IERC20;

    IVaultFactory public vaultFactory; // Interface for interacting with VaultFactory
    string public prefix = "MyVault"; // Prefix for the Vault name

    receive() external payable {} // Fallback function to receive Matic

    /**
     * @dev Sets the VaultFactory contract address.
     * @param _vaultFactory Address of the VaultFactory contract.
     */
    function setVaultFactory(address _vaultFactory) public onlyOwner {
        require(_vaultFactory != address(0), "VaultFactory: zero address");
        vaultFactory = IVaultFactory(_vaultFactory);
    }

    /**
     * @dev Sets the prefix for Vault names.
     * @param _prefix New prefix for Vault names.
     */
    function setPrefix(string memory _prefix) public onlyOwner {
        prefix = _prefix;
    }

    /**
     * @dev Constructor to initialize the contract with the VaultFactory address.
     * @param _vaultFactory Address of the VaultFactory contract.
     */
    constructor(address _vaultFactory) {
        setVaultFactory(_vaultFactory);
    }

    /**
     * @dev Internal function to generate the name for the next Vault.
     * @param _owner Address of the Vault owner.
     * @return Name for the next Vault.
     */
    function _getNextVaultName(address _owner) internal view returns (string memory) {
        uint256 vaultCount = vaultFactory.vaultsByOwnerLength(_owner) + 1;
        return string.concat(prefix, uint2str(vaultCount));
    }

    /**
     * @dev Creates a new Vault.
     * @param _collateralToken Address of the collateral token.
     * @param _collateralAmount Amount of collateral tokens to be deposited.
     * @param _borrowAmount Amount of tokens to be borrowed against the collateral.
     * @return _vault Address of the newly created Vault.
     */
    function createVault(
        address _collateralToken,
        uint256 _collateralAmount,
        uint256 _borrowAmount
    ) external returns (address _vault) {
        _vault = vaultFactory.createVault(_getNextVaultName(msg.sender));

        if (_collateralAmount > 0) {
            IERC20(_collateralToken).safeTransferFrom(msg.sender, address(this), _collateralAmount);
            IERC20(_collateralToken).safeApprove(address(vaultFactory), _collateralAmount);
            vaultFactory.addCollateral(_vault, _collateralToken, _collateralAmount);
            if (_borrowAmount > 0) {
                vaultFactory.borrow(_vault, _borrowAmount, msg.sender);
            }
        }

        vaultFactory.transferVaultOwnership(_vault, msg.sender);
    }

    /**
     * @dev Creates a new Vault with native (Matic) collateral.
     * @param _borrowAmount Amount of tokens to be borrowed against the collateral.
     * @return _vault Address of the newly created Vault.
     */
    function createVaultNative(uint256 _borrowAmount) external payable returns (address _vault) {
        _vault = vaultFactory.createVault(_getNextVaultName(msg.sender));

        if (msg.value > 0) {
            vaultFactory.addCollateralNative{value: msg.value}(_vault);
            if (_borrowAmount > 0) {
                vaultFactory.borrow(_vault, _borrowAmount, msg.sender);
            }
        }
        vaultFactory.transferVaultOwnership(_vault, msg.sender);
    }

    /**
     * @dev Converts uint to a string.
     * @param _i Unsigned integer to be converted.
     * @return _uintAsString String representation of the input integer.
     */
    function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}

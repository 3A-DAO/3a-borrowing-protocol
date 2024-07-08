// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/access/Ownable.sol';
import '../interfaces/IMintableToken.sol';

/// @title implements owner of the MintableToken contract
contract MintableTokenOwner is Ownable {
    IMintableToken public immutable token;
    mapping(address => bool) public minters;

    event MinterAdded(address newMinter);

    // solhint-disable-next-line func-visibility
    constructor(address _token) Ownable() {
        token = IMintableToken(_token);
    }

    /// @dev mints tokens to the recipient, to be called from owner
    /// @param _recipient address to mint
    /// @param _amount amount to be minted
    function mint(address _recipient, uint256 _amount) public {
        require(
            minters[msg.sender],
            'MintableTokenOwner:mint: the sender must be in the minters list'
        );
        token.mint(_recipient, _amount);
    }

    function transferTokenOwnership(address _newOwner) public onlyOwner {
        token.transferOwnership(_newOwner);
    }

    /// @dev adds new minter
    /// @param _newMinter address of new minter
    function addMinter(address _newMinter) public onlyOwner {
        minters[_newMinter] = true;
        emit MinterAdded(_newMinter);
    }

    /// @dev removes minter from minter list
    /// @param _minter address of the minter
    function revokeMinter(address _minter) public onlyOwner {
        minters[_minter] = false;
    }
}

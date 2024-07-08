// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IFeeRecipient {
    function baseRate() external view returns (uint256);

    function getBorrowingFee(uint256 _amount) external view returns (uint256);

    function calcDecayedBaseRate(
        uint256 _currentBaseRate
    ) external view returns (uint256);

    /**
     @dev is called to make the FeeRecipient contract transfer the fees to itself. It will use transferFrom to get the
     fees from the msg.sender
     @param _amount the amount in Wei of fees to transfer
     */
    function takeFees(uint256 _amount) external returns (bool);

    function increaseBaseRate(uint256 _increase) external returns (uint256);
}

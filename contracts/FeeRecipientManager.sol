// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import '@openzeppelin/contracts/interfaces/IERC20Metadata.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import './interfaces/lynex/IRouter.sol';
import 'hardhat/console.sol';

/**
 * @title FeeRecipientManager
 * @dev Contract to receive reward tokens, swap for EURO3, and send to the cashbackpool
 */
contract FeeRecipientManager is Ownable {
    address public feeReceiver;
    IERC20Metadata public euro3;
    IRouter public router;

    event RewardsDistributed(uint256 amountEuro3);
    event RewardsWithdrawn(address[] tokens, address receiver);
    event FeeReceiverUpdated(address feeRecipient);

    /**
     * @dev Constructor to set initial values
     * @param _feeReceiver Address to receive fees
     * @param _euro3 Address of the EURO3 token
     * @param _router Address of the router contract
     */
    constructor(address _feeReceiver, address _euro3, address _router) payable {
        feeReceiver = _feeReceiver;
        euro3 = IERC20Metadata(_euro3);
        router = IRouter(_router);
    }

    /**
     * @dev Method to claim rewards in Euro3 and send it to a specific address
     * @param tokenFrom Array of token addresses to swap from
     * @param tokenTo Array of token addresses to swap to
     * @param amountOutMin Minimum amount of EURO3 to receive
     */
    function claimRewards(
        address[] memory tokenFrom,
        address[] memory tokenTo,
        // * router (dynamic)
        uint256 amountOutMin
    ) public onlyOwner {
        require(
            tokenFrom.length == tokenTo.length,
            'array-length-must-be-equal'
        );

        for (uint i = 0; i < tokenFrom.length; ) {
            IERC20Metadata _tokenFrom = IERC20Metadata(tokenFrom[i]);
            uint256 balance = _tokenFrom.balanceOf(address(this));
            console.log('token: ', tokenFrom[i]);
            console.log('BalanceBefore: ', balance);
            if (balance > 0) {
                _tokenFrom.approve(address(router), balance);

                IRouter.ExactInputSingleParams memory params = IRouter
                    .ExactInputSingleParams(
                        address(_tokenFrom),
                        tokenTo[i],
                        address(this),
                        block.timestamp + 1000, // Use `block.timestamp` instead of `deadline`
                        balance,
                        0, // Min amount Out
                        0 // limitSqrPrice
                    );
                router.exactInputSingle(params);

                IERC20Metadata usdc = IERC20Metadata(
                    tokenFrom[tokenFrom.length - 1]
                );
                console.log('USDC Balance: ', usdc.balanceOf(address(this)));
            }
            // * Todo: Remove
            uint256 balance2 = _tokenFrom.balanceOf(address(this));
            console.log('BalanceAfter: ', balance2);

            unchecked {
                i++;
            }
        }
        uint256 balanceEuro3 = euro3.balanceOf(address(this));
        console.log('EURO3: ', address(euro3));
        console.log('BalanceEURO3: ', balanceEuro3);
        require(balanceEuro3 >= amountOutMin, 'receiving-lt-minAmountOut');
        euro3.transfer(feeReceiver, balanceEuro3);

        emit RewardsDistributed(balanceEuro3);
    }

    /**
     * @dev Allows the owner to force withdraw tokens from the contract to a specified address. It should be used in case there is not a path to swap
     * @param tokenFrom Array of token addresses to withdraw from
     * @param to Address to transfer the tokens to
     */
    function forceWithdraw(
        address[] memory tokenFrom,
        address to
    ) external onlyOwner {
        for (uint i = 0; i < tokenFrom.length; ) {
            IERC20Metadata _tokenFrom = IERC20Metadata(tokenFrom[i]);
            uint256 balance = _tokenFrom.balanceOf(address(this));
            _tokenFrom.transfer(to, balance);
            unchecked {
                i++;
            }
        }
        emit RewardsWithdrawn(tokenFrom, to);
    }

    /**
     * @dev Update the fee receiver address
     * @param _feeReceiver New address to receive fees
     */
    function setfeeReceiver(address _feeReceiver) external onlyOwner {
        feeReceiver = _feeReceiver;
        emit FeeReceiverUpdated(_feeReceiver);
    }
}

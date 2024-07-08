// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) external;

    function getAmountOut(
        uint256 amountIn,
        address token0,
        address token1
    ) external view returns (uint256 amountOut);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICollateralEscrow {
    function init(address tokenAddress) external virtual;

    function depositCollateral(uint256 amount, uint256 loanID) external;

    function withdrawCollateral(
        uint256 amount,
        uint256 loanID,
        address receiver
    ) external;
}

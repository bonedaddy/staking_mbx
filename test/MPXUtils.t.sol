// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/MPXUtils.sol";

contract MPXUtilsTest is Test {
    function testCalculateUnstakePenalty18Decimals() public {
        uint256 amountA = 100 ether;
        uint256 amountB = 1 ether;
        uint256 amountC = 10000 ether;

        MPXUtils.UnstakePenalty memory penalty = MPXUtils.calculateUnstakePenalty(amountA, 18);

        assertEq(MPXUtils.totalPenaltyFee(penalty) / 1 ether, 20);

        penalty = MPXUtils.calculateUnstakePenalty(amountB, 18);
        assertEq(MPXUtils.totalPenaltyFee(penalty), 200000000000000000);

        penalty = MPXUtils.calculateUnstakePenalty(amountC, 18);
        assertEq(MPXUtils.totalPenaltyFee(penalty), 2000000000000000000000);
    }

    function testCalculateUnstakePenalty6Decimals() public {
        uint256 amountA = 100 * 1e6;
        uint256 amountB = 1 * 1e6;
        uint256 amountC = 10000 * 1e6;

        MPXUtils.UnstakePenalty memory penalty = MPXUtils.calculateUnstakePenalty(amountA, 6);
        assertEq(MPXUtils.totalPenaltyFee(penalty) / 1e6, 20);

        penalty = MPXUtils.calculateUnstakePenalty(amountB, 6);
        assertEq(MPXUtils.totalPenaltyFee(penalty), 200000);

        penalty = MPXUtils.calculateUnstakePenalty(amountC, 6);
        assertEq(MPXUtils.totalPenaltyFee(penalty), 2000000000);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/MBXUtils.sol";

contract MBXUtilsTest is Test {
    function testCalculateUnstakePenalty18Decimals() public {
        uint256 amountA = 100 ether;
        uint256 amountB = 1 ether;
        uint256 amountC = 10000 ether;

        MBXUtils.UnstakePenalty memory penalty = MBXUtils.calculateUnstakePenalty(amountA, 18, false);

        assertEq(MBXUtils.totalPenaltyFee(penalty) / 1 ether, 20);

        penalty = MBXUtils.calculateUnstakePenalty(amountB, 18, false);
        assertEq(MBXUtils.totalPenaltyFee(penalty), 200000000000000000);

        penalty = MBXUtils.calculateUnstakePenalty(amountC, 18, false);
        assertEq(MBXUtils.totalPenaltyFee(penalty), 2000000000000000000000);
    }

    function testCalculateUnstakePenalty6Decimals() public {
        uint256 amountA = 100 * 1e6;
        uint256 amountB = 1 * 1e6;
        uint256 amountC = 10000 * 1e6;

        MBXUtils.UnstakePenalty memory penalty = MBXUtils.calculateUnstakePenalty(amountA, 6, false);
        assertEq(MBXUtils.totalPenaltyFee(penalty) / 1e6, 20);

        penalty = MBXUtils.calculateUnstakePenalty(amountB, 6, false);
        assertEq(MBXUtils.totalPenaltyFee(penalty), 200000);

        penalty = MBXUtils.calculateUnstakePenalty(amountC, 6, false);
        assertEq(MBXUtils.totalPenaltyFee(penalty), 2000000000);
    }

    function testCalculateMinUnstakePenalty18Decimals() public {
        uint256 amountA = 100 ether;
        uint256 amountB = 1 ether;
        uint256 amountC = 10000 ether;

        MBXUtils.UnstakePenalty memory penalty = MBXUtils.calculateUnstakePenalty(amountA, 18, true);

        assertEq(MBXUtils.totalPenaltyFee(penalty) / 1 ether, 10);

        penalty = MBXUtils.calculateUnstakePenalty(amountB, 18, true);
        assertEq(MBXUtils.totalPenaltyFee(penalty), 100000000000000000);

        penalty = MBXUtils.calculateUnstakePenalty(amountC, 18, true);
        assertEq(MBXUtils.totalPenaltyFee(penalty), 1000000000000000000000);
    }

    function testCalculateMinUnstakePenalty6Decimals() public {
        uint256 amountA = 100 * 1e6;
        uint256 amountB = 1 * 1e6;
        uint256 amountC = 10000 * 1e6;

        MBXUtils.UnstakePenalty memory penalty = MBXUtils.calculateUnstakePenalty(amountA, 6, false);
        assertEq(MBXUtils.totalPenaltyFee(penalty) / 1e6, 20);

        penalty = MBXUtils.calculateUnstakePenalty(amountB, 6, true);
        assertEq(MBXUtils.totalPenaltyFee(penalty), 100000);

        penalty = MBXUtils.calculateUnstakePenalty(amountC, 6, true);
        assertEq(MBXUtils.totalPenaltyFee(penalty), 1000000000);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FeeDistributor} from "../../src/core/FeeDistributor.sol";

/**
 * @title MaliciousReceiver
 * @notice Mock contract for testing reentrancy protection
 * @dev Attempts to re-enter FeeDistributor's receive function
 */
contract MaliciousReceiver {
    FeeDistributor public feeDistributor;
    uint256 public attackCount;

    constructor(address _feeDistributor) {
        feeDistributor = FeeDistributor(payable(_feeDistributor));
    }

    function attack() external {
        (bool success,) = address(feeDistributor).call{value: 1 ether}("");
        require(success, "Initial send failed");
    }

    receive() external payable {
        if (attackCount < 2) {
            attackCount++;
            // Try to re-enter through receive
            (bool success,) = address(feeDistributor).call{value: 0.1 ether}("");
            require(success, "Reentrant send failed");
        }
    }
}

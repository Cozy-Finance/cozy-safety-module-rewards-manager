// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IWithdrawerErrors {
  /// @notice Thrown when a withdrawal is attempted that exceeds available undripped rewards for a pool.
  error BalanceTooLow();
}

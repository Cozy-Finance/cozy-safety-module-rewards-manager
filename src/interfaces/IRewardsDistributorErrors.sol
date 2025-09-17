// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IRewardsDistributorErrors {
  /// @notice Thrown when an drip reward pool array is not the same length as the number of reward pools.
  error InvalidLength();
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IDepositorEvents {
  /// @notice Emitted when a user deposits.
  /// @param caller_ The caller of the deposit.
  /// @param rewardPoolId_ The reward pool ID that the user deposited into.
  /// @param assetAmount_ The amount of the underlying asset deposited.
  event Deposited(address indexed caller_, uint16 indexed rewardPoolId_, uint256 assetAmount_);
}

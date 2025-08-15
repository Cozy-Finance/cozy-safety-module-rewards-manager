// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IWithdrawerEvents {
  /// @notice Emitted when reward assets are withdrawn by a depositor.
  /// @param depositor_ The original rewards depositor.
  /// @param rewardPoolId_ The reward pool ID that the despotior withdrew from.
  /// @param withdrawAmount_ The amount of rewards withdrawn.
  /// @param receiver_ The receiver of the withdrawn rewards.
  event Withdrawn(address indexed depositor_, uint16 indexed rewardPoolId_, uint256 withdrawAmount_, address receiver_);
}

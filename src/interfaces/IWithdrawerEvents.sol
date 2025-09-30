// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IWithdrawerEvents {
  /// @notice Emitted when reward assets are withdrawn by an owner.
  /// @param owner_ The owner of the rewards deposit.
  /// @param rewardPoolId_ The reward pool ID that the owner withdrew from.
  /// @param withdrawAmount_ The amount of rewards withdrawn.
  /// @param receiver_ The receiver of the withdrawn rewards.
  event Withdrawn(address indexed owner_, uint16 rewardPoolId_, uint256 withdrawAmount_, address indexed receiver_);
}

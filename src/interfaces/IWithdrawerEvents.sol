// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IWithdrawerEvents {
  /// @notice Emitted when reward assets are withdrawn by a depositor.
  /// @param caller_ The caller of the withdraw function.
  /// @param owner_ The owner of the deposited funds.
  /// @param receiver_ The receiver of the withdrawn rewards.
  /// @param rewardPoolId_ The reward pool ID that the owner withdrew from.
  /// @param withdrawAmount_ The amount of rewards withdrawn.
  event Withdrawn(
    address indexed caller_,
    address indexed owner_,
    address indexed receiver_,
    uint16 rewardPoolId_,
    uint256 withdrawAmount_
  );
}

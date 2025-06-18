// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IWithdrawerEvents {
  /// @notice Emitted when a protocol withdraws undripped rewards.
  /// @param caller_ The address that initiated the withdrawal.
  /// @param rewardPoolId_ The ID of the reward pool being withdrawn from.
  /// @param rewardAsset_ The token being withdrawn.
  /// @param amount_ The amount of the token withdrawn.
  event Withdrawn(
    address indexed caller_,
    uint16 indexed rewardPoolId_,
    address indexed rewardAsset_,
    address to_,
    uint256 amount_
  );
}

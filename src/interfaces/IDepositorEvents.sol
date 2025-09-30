// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IDepositorEvents {
  /// @notice Emitted when a user deposits.
  /// @param caller_ The caller of the deposit.
  /// @param owner_ The owner of the deposited assets.
  /// @param receiver_ The address receiving credit for the deposit.
  /// @param rewardPoolId_ The reward pool ID that the user deposited into.
  /// @param depositAmount_ The amount of the underlying asset deposited.
  /// @param depositFeeAmount_ The amount of the underlying asset used to pay the deposit fee.
  event Deposited(
    address indexed caller_,
    address indexed owner_,
    address indexed receiver_,
    uint16 rewardPoolId_,
    uint256 depositAmount_,
    uint256 depositFeeAmount_
  );
}

// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";

interface IDepositorEvents {
  /// @notice Emitted when a user deposits.
  /// @param caller_ The caller of the deposit.
  /// @param receiver_ The receiver of the deposit receipt tokens.
  /// @param depositReceiptToken_ The deposit receipt token for the reward pool.
  /// @param assetAmount_ The amount of the underlying asset deposited.
  /// @param depositReceiptTokenAmount_ The amount of deposit receipt tokens minted.
  event Deposited(
    address indexed caller_,
    address indexed receiver_,
    IReceiptToken indexed depositReceiptToken_,
    uint256 assetAmount_,
    uint256 depositReceiptTokenAmount_
  );

  /// @notice Emitted when a user redeems undripped rewards.
  /// @param caller_ The caller of the redemption.
  /// @param receiver_ The receiver of the undripped reward assets.
  /// @param owner_ The owner of the deposit receipt tokens which are being redeemed.
  /// @param depositReceiptToken_ The deposit receipt token for the reward pool.
  /// @param depositReceiptTokenAmount_ The amount of deposit receipt tokens being redeemed.
  /// @param rewardAssetAmount_ The amount of undripped reward assets being redeemed.
  event RedeemedUndrippedRewards(
    address caller_,
    address indexed receiver_,
    address indexed owner_,
    IReceiptToken indexed depositReceiptToken_,
    uint256 depositReceiptTokenAmount_,
    uint256 rewardAssetAmount_
  );
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IReceiptToken} from "cozy-safety-module-libs/interfaces/IReceiptToken.sol";

interface IStakerEvents {
  /// @notice Emitted when a user stakes.
  /// @param caller_ The address that called the stake function.
  /// @param depositor_ The address that deposited/staked the underlying asset.
  /// @param receiver_ The address that received the stkReceiptTokens.
  /// @param stakePoolId_ The stake pool ID that the user staked in.
  /// @param stkReceiptToken_ The stkReceiptToken that was minted.
  /// @param assetAmount_ The amount of the underlying asset staked.
  event Staked(
    address indexed caller_,
    address indexed depositor_,
    address indexed receiver_,
    uint16 stakePoolId_,
    IReceiptToken stkReceiptToken_,
    uint256 assetAmount_
  );

  /// @notice Emitted when a user unstakes.
  /// @param caller_ The address that called the unstake function.
  /// @param receiver_ The address that received the unstaked assets.
  /// @param owner_ The owner of the stkReceiptTokens being unstaked.
  /// @param stakePoolId_ The stake pool ID that the user unstaked from.
  /// @param stkReceiptToken_ The stkReceiptToken that was burned.
  /// @param stkReceiptTokenAmount_ The amount of stkReceiptTokens burned.
  event Unstaked(
    address caller_,
    address indexed receiver_,
    address indexed owner_,
    uint16 indexed stakePoolId_,
    IReceiptToken stkReceiptToken_,
    uint256 stkReceiptTokenAmount_
  );
}

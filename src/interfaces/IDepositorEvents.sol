// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";

interface IDepositorEvents {
  /// @dev Emitted when a user deposits.
  event Deposited(
    address indexed caller_,
    address indexed receiver_,
    IReceiptToken indexed depositReceiptToken_,
    uint256 assetAmount_,
    uint256 depositReceiptTokenAmount_
  );

  /// @dev Emitted when a user redeems rewards.
  event RedeemedUndrippedRewards(
    address caller_,
    address indexed receiver_,
    address indexed owner_,
    IReceiptToken indexed depositReceiptToken_,
    uint256 depositTokenAmount_,
    uint256 rewardAssetAmount_
  );
}

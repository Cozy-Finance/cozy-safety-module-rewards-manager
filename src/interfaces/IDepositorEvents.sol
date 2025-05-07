// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IReceiptToken} from "cozy-safety-module-libs/interfaces/IReceiptToken.sol";

interface IDepositorEvents {
  /// @notice Emitted when a user deposits.
  /// @param caller_ The caller of the deposit.
  /// @param rewardPoolId_ The reward pool ID that the user deposited into.
  /// @param depositAmount_ The amount of the underlying asset deposited.
  /// @param depositFeeAmount_ The amount of the underlying asset used to pay the deposit fee.
  event Deposited(
    address indexed caller_, uint16 indexed rewardPoolId_, uint256 depositAmount_, uint256 depositFeeAmount_
  );
}

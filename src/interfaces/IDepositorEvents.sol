// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";

interface IDepositorEvents {
  /// @notice Emitted when a user deposits.
  /// @param caller_ The caller of the deposit.
  /// @param receiver_ The receiver of the deposit receipt tokens.
  /// @param rewardPoolId_ The reward pool ID that the user deposited into.
  /// @param assetAmount_ The amount of the underlying asset deposited.
  event Deposited(
    address indexed caller_, address indexed receiver_, uint16 indexed rewardPoolId_, uint256 assetAmount_
  );
}

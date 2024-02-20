// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {RewardsManagerState} from "../lib/RewardsManagerStates.sol";

interface IStateChangerEvents {
  /// @notice Emitted when the rewards manager changes state.
  /// @param updatedTo_ The new state of the rewards manager.
  event RewardsManagerStateUpdated(RewardsManagerState indexed updatedTo_);
}

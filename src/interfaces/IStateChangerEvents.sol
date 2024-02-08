// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {RewardsManagerState} from "../lib/RewardsManagerStates.sol";

interface IStateChangerEvents {
  /// @notice Emitted when the Rewards Manager changes state.
  event RewardsManagerStateUpdated(RewardsManagerState indexed updatedTo_);
}

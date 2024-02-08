// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Governable} from "cozy-safety-module-shared/lib/Governable.sol";
import {IStateChangerEvents} from "../interfaces/IStateChangerEvents.sol";
import {RewardsManagerState} from "./RewardsManagerStates.sol";
import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";

abstract contract StateChanger is RewardsManagerCommon, Governable, IStateChangerEvents {
  function pause() external {
    if (msg.sender != owner && msg.sender != pauser && msg.sender != address(cozyManager)) revert Unauthorized();
    if (rewardsManagerState == RewardsManagerState.PAUSED) revert InvalidStateTransition();

    // Drip rewards before pausing.
    dripRewards();
    rewardsManagerState = RewardsManagerState.PAUSED;
    emit RewardsManagerStateUpdated(RewardsManagerState.PAUSED);
  }

  function unpause() external {
    if (msg.sender != owner && msg.sender != address(cozyManager)) revert Unauthorized();
    if (rewardsManagerState == RewardsManagerState.ACTIVE) revert InvalidStateTransition();

    rewardsManagerState = RewardsManagerState.ACTIVE;
    // Drip rewards after unpausing.
    dripRewards();
    emit RewardsManagerStateUpdated(RewardsManagerState.ACTIVE);
  }
}

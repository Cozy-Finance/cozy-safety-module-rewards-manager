// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Governable} from "cozy-safety-module-shared/lib/Governable.sol";
import {SafetyModuleState} from "cozy-safety-module-shared/lib/SafetyModuleStates.sol";
import {RewardsModuleCommon} from "./RewardsModuleCommon.sol";
import {ReservePool, RewardPool} from "./structs/Pools.sol";
import {ICommonErrors} from "../interfaces/ICommonErrors.sol";

abstract contract Configurator is RewardsModuleCommon, Governable {
  function applyConfigUpdates() external {
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) revert ICommonErrors.InvalidState();

    // A config update may change the rewards weights, which breaks the invariants that we use to do claimable rewards
    // accounting. It may no longer hold that:
    //    claimableRewards[reservePool][rewardPool].cumulativeClaimedRewards <=
    //        rewardPools[rewardPool].cumulativeDrippedRewards*reservePools[reservePool].rewardsWeight
    // So, before finalizing, we drip rewards, update claimable reward indices and reset the cumulative rewards values
    // to 0.
    ReservePool[] storage reservePools_ = reservePools;
    RewardPool[] storage rewardPools_ = rewardPools;
    _dripAndResetCumulativeRewardsValues(reservePools_, rewardPools_);
  }

  /// @notice Returns true if the provided configs are valid for the rewards module, false otherwise.
  function isValidUpdate(
    ReservePool[] storage reservePools_,
    RewardPool[] storage rewardPools_,
    mapping(ITrigger => Trigger) storage triggerData_,
    UpdateConfigsCalldataParams calldata configUpdates_,
    IManager manager_
  ) internal view returns (bool) {
    // Validate the configuration parameters.
    if (
      !isValidConfiguration(
        configUpdates_.reservePoolConfigs,
        configUpdates_.rewardPoolConfigs,
        configUpdates_.delaysConfig,
        manager_.allowedReservePools(),
        manager_.allowedRewardPools()
      )
    ) return false;

    // Validate number of reserve and rewards pools. It is only possible to add new pools, not remove existing ones.
    uint256 numExistingReservePools_ = reservePools_.length;
    uint256 numExistingRewardPools_ = rewardPools_.length;
    if (
      configUpdates_.reservePoolConfigs.length < numExistingReservePools_
        || configUpdates_.rewardPoolConfigs.length < numExistingRewardPools_
    ) return false;

    // Validate existing reserve pools.
    for (uint16 i = 0; i < numExistingReservePools_; i++) {
      if (reservePools_[i].asset != configUpdates_.reservePoolConfigs[i].asset) return false;
    }

    // Validate existing reward pools.
    for (uint16 i = 0; i < numExistingRewardPools_; i++) {
      if (rewardPools_[i].asset != configUpdates_.rewardPoolConfigs[i].asset) return false;
    }

    for (uint16 i = 0; i < configUpdates_.triggerConfigUpdates.length; i++) {
      // Triggers that have successfully called trigger() on the safety module cannot be updated.
      if (triggerData_[configUpdates_.triggerConfigUpdates[i].trigger].triggered) return false;
    }

    return true;
  }
}

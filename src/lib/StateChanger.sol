// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {Governable} from "cozy-safety-module-libs/lib/Governable.sol";
import {IStateChangerEvents} from "../interfaces/IStateChangerEvents.sol";
import {RewardsManagerState} from "./RewardsManagerStates.sol";
import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";
import {IRewardsDistributorErrors} from "../interfaces/IRewardsDistributorErrors.sol";
import {RewardPool} from "./structs/Pools.sol";

abstract contract StateChanger is RewardsManagerCommon, Governable, IStateChangerEvents {
  /// @notice Pause the rewards manager.
  /// @dev Only the owner, pauser, or Cozy manager can pause the rewards manager.
  /// @dev Note that by default all reward pools are dripped when pausing. If you want to pause without dripping from
  /// specific reward pools, you can use the other pause function which accepts bool[] memory dripRewardPool_ instead.
  function pause() external {
    if (msg.sender != owner && msg.sender != pauser && msg.sender != address(cozyManager)) revert Unauthorized();
    if (rewardsManagerState == RewardsManagerState.PAUSED) revert InvalidStateTransition();

    // Drip rewards before pausing.
    dripRewards();
    rewardsManagerState = RewardsManagerState.PAUSED;
    emit RewardsManagerStateUpdated(RewardsManagerState.PAUSED);
  }

  /// @notice Pause the rewards manager and drip only specified reward pools.
  /// @dev Only the owner, pauser, or Cozy manager can pause the rewards manager.
  /// @param dripRewardPool_ Whether to drip rewards for each reward pool.
  function pause(bool[] memory dripRewardPool_) external {
    if (msg.sender != owner && msg.sender != pauser && msg.sender != address(cozyManager)) revert Unauthorized();
    if (rewardsManagerState == RewardsManagerState.PAUSED) revert InvalidStateTransition();
    if (dripRewardPool_.length != rewardPools.length) revert IRewardsDistributorErrors.InvalidLength();

    // Drip specified reward pools before pausing.
    for (uint256 i = 0; i < rewardPools.length; i++) {
      if (dripRewardPool_[i]) {
        RewardPool storage rewardPool_ = rewardPools[i];
        _dripRewardPool(rewardPools[i]);
      }
    }

    rewardsManagerState = RewardsManagerState.PAUSED;
    emit RewardsManagerStateUpdated(RewardsManagerState.PAUSED);
  }

  /// @notice Unpause the rewards manager.
  /// @dev Only the owner or Cozy manager can unpause the rewards manager.
  /// @dev Note that by default all reward pools are dripped when unpausing. If you want to unpause without dripping
  /// from specific reward pools, you can use the other unpause function which accepts bool[] memory dripRewardPool_
  /// instead.
  function unpause() external {
    if (msg.sender != owner && msg.sender != address(cozyManager)) revert Unauthorized();
    if (rewardsManagerState == RewardsManagerState.ACTIVE) revert InvalidStateTransition();

    rewardsManagerState = RewardsManagerState.ACTIVE;
    // Drip rewards after unpausing.
    dripRewards();
    emit RewardsManagerStateUpdated(RewardsManagerState.ACTIVE);
  }

  /// @notice Unpause the rewards manager and drip only specified reward pools.
  /// @dev Only the owner or Cozy manager can unpause the rewards manager.
  /// @param dripRewardPool_ Whether to drip rewards for each reward pool.
  function unpause(bool[] memory dripRewardPool_) external {
    if (msg.sender != owner && msg.sender != address(cozyManager)) revert Unauthorized();
    if (rewardsManagerState == RewardsManagerState.ACTIVE) revert InvalidStateTransition();
    if (dripRewardPool_.length != rewardPools.length) revert IRewardsDistributorErrors.InvalidLength();

    rewardsManagerState = RewardsManagerState.ACTIVE;

    // Drip specified reward pools after unpausing.
    for (uint256 i = 0; i < rewardPools.length; i++) {
      if (dripRewardPool_[i]) {
        RewardPool storage rewardPool_ = rewardPools[i];
        _dripRewardPool(rewardPool_);
      }
    }

    emit RewardsManagerStateUpdated(RewardsManagerState.ACTIVE);
  }
}

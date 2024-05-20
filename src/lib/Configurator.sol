// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {Governable} from "cozy-safety-module-shared/lib/Governable.sol";
import {ConfiguratorLib} from "./ConfiguratorLib.sol";
import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";
import {IConfiguratorErrors} from "../interfaces/IConfiguratorErrors.sol";
import {RewardPoolConfig, StakePoolConfig} from "./structs/Configs.sol";
import {StakePool, RewardPool} from "./structs/Pools.sol";

abstract contract Configurator is RewardsManagerCommon, Governable {
  /// @notice Execute config update to the rewards manager.
  /// @param stakePoolConfigs_ The array of new stake pool configs. The array must contain configs for all existing
  /// stake pools sorted by stake pool ID (with potentially updated rewards weights, but the same underlying asset).
  /// Appended to the existing stake pool configs, the array may also include new stake pool configs, which must be
  /// sorted by the underlying asset address and must be unique (i.e., no two stake pools can have the same underlying
  /// asset). The rewards weight of the stake pools must sum to ZOC.
  /// @param rewardPoolConfigs_ The array of new reward pool configs (with potentially updated drip models, but the same
  /// underlying asset). The array must contain configs for all existing reward pools sorted by reward pool ID. Appended
  /// to the existing stake pool configs, the array may also include new reward pool configs.
  function updateConfigs(StakePoolConfig[] calldata stakePoolConfigs_, RewardPoolConfig[] calldata rewardPoolConfigs_)
    external
    onlyOwner
  {
    // A config update may change the rewards weights, which breaks the invariants that used to do claimable rewards
    // accounting. It may no longer hold that:
    //    claimableRewards[stakePoolId][rewardPoolId].cumulativeClaimedRewards <=
    //        rewardPools[rewardPoolId].cumulativeDrippedRewards.mulDivDown(stakePools[stakePoolId].rewardsWeight, ZOC)
    // To mantain the invariant, before applying the update: we drip rewards, update claimable reward indices and
    // reset the cumulative rewards values to 0. This reset is also executed when a config update occurs in the PAUSED
    // state, but in that case, the rewards are not dripped; the rewards are dripped when the rewards manager first
    // transitions to PAUSED.
    _dripAndResetCumulativeRewardsValues(stakePools, rewardPools);

    ConfiguratorLib.updateConfigs(
      stakePools,
      rewardPools,
      assetToStakePoolIds,
      stkReceiptTokenToStakePoolIds,
      receiptTokenFactory,
      stakePoolConfigs_,
      rewardPoolConfigs_,
      allowedStakePools,
      allowedRewardPools
    );
  }

  /// @notice Update pauser to `newPauser_`.
  /// @param newPauser_ The new pauser.
  function updatePauser(address newPauser_) external {
    if (newPauser_ == address(cozyManager)) revert IConfiguratorErrors.InvalidConfiguration();
    _updatePauser(newPauser_);
  }
}

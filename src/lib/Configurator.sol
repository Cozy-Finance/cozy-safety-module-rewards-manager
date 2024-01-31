// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Ownable} from "cozy-safety-module-shared/lib/Ownable.sol";
import {ConfiguratorLib} from "./ConfiguratorLib.sol";
import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";
import {RewardPoolConfig, StakePoolConfig} from "./structs/Configs.sol";
import {StakePool, RewardPool} from "./structs/Pools.sol";

abstract contract Configurator is RewardsManagerCommon, Ownable {
  /// @notice Execute config update to the rewards manager.
  /// @param stakePoolConfigs_ The array of new stake pool configs, sorted by associated reward pool ID. The array
  /// may also include config for new stake pools.
  /// @param rewardPoolConfigs_  The array of new reward pool configs, sorted by associated reward pool ID. The array
  /// may also include config for new reward pools.
  function updateConfigs(StakePoolConfig[] calldata stakePoolConfigs_, RewardPoolConfig[] calldata rewardPoolConfigs_)
    external
    onlyOwner
  {
    // A config update may change the rewards weights, which breaks the invariants that we use to do claimable rewards
    // accounting. It may no longer hold that:
    //    claimableRewards[stakePool][rewardPool].cumulativeClaimedRewards <=
    //        rewardPools[rewardPool].cumulativeDrippedRewards*stakePools[stakePool].rewardsWeight
    // So, before applying the update, we drip rewards, update claimable reward indices and reset the cumulative rewards
    // values to 0.
    StakePool[] storage stakePools_ = stakePools;
    RewardPool[] storage rewardPools_ = rewardPools;
    _dripAndResetCumulativeRewardsValues(stakePools_, rewardPools_);

    ConfiguratorLib.updateConfigs(
      stakePools_,
      rewardPools_,
      stkReceiptTokenToStakePoolIds,
      receiptTokenFactory,
      stakePoolConfigs_,
      rewardPoolConfigs_,
      allowedStakePools,
      allowedRewardPools
    );
  }
}

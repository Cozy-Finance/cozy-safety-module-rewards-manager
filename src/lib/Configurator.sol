// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Governable} from "cozy-safety-module-shared/lib/Governable.sol";
import {SafetyModuleState} from "cozy-safety-module-shared/lib/SafetyModuleStates.sol";
import {ConfiguratorLib} from "./ConfiguratorLib.sol";
import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";
import {ReservePool, RewardPool} from "./structs/Pools.sol";
import {RewardPoolConfig} from "./structs/Rewards.sol";
import {ICommonErrors} from "../interfaces/ICommonErrors.sol";

abstract contract Configurator is RewardsManagerCommon, Governable {
  /// @notice Execute config update to the rewards manager.
  /// @param rewardPoolConfigs_  The array of new reward pool configs, sorted by associated reward pool ID. The array
  /// may also include config for new reward pools.
  /// @param rewardsWeights_ The array of new rewards weights, sorted by associated reserve pool ID. The length of the
  /// weights must match `safetyModule.numReservePools()`.
  function updateConfigs(RewardPoolConfig[] calldata rewardPoolConfigs_, uint16[] calldata rewardsWeights_) external {
    // A config update may change the rewards weights, which breaks the invariants that we use to do claimable rewards
    // accounting. It may no longer hold that:
    //    claimableRewards[reservePool][rewardPool].cumulativeClaimedRewards <=
    //        rewardPools[rewardPool].cumulativeDrippedRewards*reservePools[reservePool].rewardsWeight
    // So, before applying the update, we drip rewards, update claimable reward indices and reset the cumulative rewards
    // values to 0.
    ReservePool[] storage reservePools_ = reservePools;
    RewardPool[] storage rewardPools_ = rewardPools;
    _dripAndResetCumulativeRewardsValues(reservePools_, rewardPools_);

    ConfiguratorLib.updateConfigs(
      reservePools_,
      rewardPools_,
      stkReceiptTokenToReservePoolIds,
      receiptTokenFactory,
      rewardPoolConfigs_,
      rewardsWeights_,
      safetyModule,
      cozyManager
    );
  }
}

// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IConfiguratorErrors} from "../interfaces/IConfiguratorErrors.sol";
import {IConfiguratorEvents} from "../interfaces/IConfiguratorEvents.sol";
import {StakePool, RewardPool, IdLookup} from "./structs/Pools.sol";
import {RewardPoolConfig, StakePoolConfig} from "./structs/Configs.sol";

library ConfiguratorLib {
  /// @notice Returns true if the provided configs are valid for the rewards manager, false otherwise.
  /// @param stakePools_ The array of existing stake pools.
  /// @param rewardPools_ The array of existing reward pools.
  /// @param assetToStakePoolIds_ The mapping of asset to stake pool IDs index lookups.
  /// @param stakePoolConfigs_ The array of stake pool configs. These configs must obey requirements described in
  /// `Configurator.updateConfigs`.
  /// @param rewardPoolConfigs_ The array of reward pool configs. These configs must obey requirements described in
  /// `Configurator.updateConfigs`.
  /// @param allowedStakePools_ The maximum number of allowed stake pools.
  /// @param allowedRewardPools_ The maximum number of allowed reward pools.
  /// @return True if the provided configs are valid for the rewards manager, false otherwise.
  function isValidUpdate(
    StakePool[] storage stakePools_,
    RewardPool[] storage rewardPools_,
    mapping(IERC20 => IdLookup) storage assetToStakePoolIds_,
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    uint16 allowedStakePools_,
    uint16 allowedRewardPools_
  ) internal view returns (bool) {
    uint256 numExistingStakePools_ = stakePools_.length;
    uint256 numExistingRewardPools_ = rewardPools_.length;

    // Validate the configuration parameters.
    if (
      !isValidConfiguration(
        stakePoolConfigs_,
        rewardPoolConfigs_,
        numExistingStakePools_,
        numExistingRewardPools_,
        allowedStakePools_,
        allowedRewardPools_
      )
    ) return false;

    // Validate existing stake pools. The existing stake pool's underlying asset cannot change.
    for (uint16 i = 0; i < numExistingStakePools_; i++) {
      if (stakePools_[i].asset != stakePoolConfigs_[i].asset) return false;
    }

    // Validate new stake pools. The new stake pool's underlying asset cannot already be in use by an existing stake
    // pool.
    for (uint256 i = numExistingStakePools_; i < stakePoolConfigs_.length; i++) {
      if (assetToStakePoolIds_[stakePoolConfigs_[i].asset].exists) return false;
    }

    // Validate existing reward pools. The existing reward pool's underlying asset cannot change.
    for (uint16 i = 0; i < numExistingRewardPools_; i++) {
      if (rewardPools_[i].asset != rewardPoolConfigs_[i].asset) return false;
    }

    return true;
  }

  /// @notice Returns true if the provided configs are generically valid for a rewards manager, false otherwise.
  /// @param stakePoolConfigs_ The array of stake pool configs.
  /// @param rewardPoolConfigs_ The array of reward pool configs.
  /// @param numExistingStakePools_ The number of existing stake pools.
  /// @param numExistingRewardPools_ The number of existing reward pools.
  /// @param allowedStakePools_ The maximum number of allowed stake pools.
  /// @param allowedRewardPools_ The maximum number of allowed reward pools.
  /// @return True if the provided configs are generically valid for a rewards manager, false otherwise.
  function isValidConfiguration(
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    uint256 numExistingStakePools_,
    uint256 numExistingRewardPools_,
    uint16 allowedStakePools_,
    uint16 allowedRewardPools_
  ) internal pure returns (bool) {
    // Validate number of stake pools. The number of stake pools configs must be greater than or equal to the number of
    // existing stake pools, and less than or equal to the maximum allowed stake pools.
    if (stakePoolConfigs_.length > allowedStakePools_ || stakePoolConfigs_.length < numExistingStakePools_) {
      return false;
    }

    // Validate number of reward pools. The number of reward pools configs must be greater than or equal to the number
    // of existing reward pools, and less than or equal to the maximum allowed reward pools.
    if (rewardPoolConfigs_.length > allowedRewardPools_ || rewardPoolConfigs_.length < numExistingRewardPools_) {
      return false;
    }

    if (stakePoolConfigs_.length != 0) {
      uint16 rewardsWeightSum_ = 0;

      for (uint256 i = 0; i < stakePoolConfigs_.length; i++) {
        rewardsWeightSum_ += stakePoolConfigs_[i].rewardsWeight;

        // New stake pool configs in the array must be sorted and not contain duplicate assets.
        if (
          i > numExistingStakePools_ && address(stakePoolConfigs_[i].asset) <= address(stakePoolConfigs_[i - 1].asset)
        ) return false;
      }

      // The sum of all stake pool rewards weights must be equivalent to a ZOC.
      if (rewardsWeightSum_ != MathConstants.ZOC) return false;
    }

    return true;
  }

  // @notice Execute config update to the rewards manager.
  /// @param stakePools_ The array of existing stake pools.
  /// @param rewardPools_ The array of existing reward pools.
  /// @param assetToStakePoolIds_ The mapping of asset to stake pool IDs index lookups.
  /// @param stkReceiptTokenToStakePoolIds_ The mapping of stkReceiptToken to stake pool IDs index lookups.
  /// @param receiptTokenFactory_ The receipt token factory.
  /// @param stakePoolConfigs_ The array of stake pool configs. These configs must obey requirements described in
  /// `Configurator.updateConfigs`.
  /// @param rewardPoolConfigs_ The array of reward pool configs. These configs must obey requirements described in
  /// `Configurator.updateConfigs`.
  /// @param allowedStakePools_ The maximum number of allowed stake pools.
  /// @param allowedRewardPools_ The maximum number of allowed reward pools.
  function updateConfigs(
    StakePool[] storage stakePools_,
    RewardPool[] storage rewardPools_,
    mapping(IERC20 => IdLookup) storage assetToStakePoolIds_,
    mapping(IReceiptToken => IdLookup) storage stkReceiptTokenToStakePoolIds_,
    IReceiptTokenFactory receiptTokenFactory_,
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    uint16 allowedStakePools_,
    uint16 allowedRewardPools_
  ) public {
    if (
      !isValidUpdate(
        stakePools_,
        rewardPools_,
        assetToStakePoolIds_,
        stakePoolConfigs_,
        rewardPoolConfigs_,
        allowedStakePools_,
        allowedRewardPools_
      )
    ) revert IConfiguratorErrors.InvalidConfiguration();

    applyConfigUpdates(
      stakePools_,
      rewardPools_,
      assetToStakePoolIds_,
      stkReceiptTokenToStakePoolIds_,
      receiptTokenFactory_,
      stakePoolConfigs_,
      rewardPoolConfigs_
    );
  }

  /// @notice Apply config updates to the rewards manager's stake and reward pools.
  /// @param stakePools_ The array of existing stake pools.
  /// @param rewardPools_ The array of existing reward pools.
  /// @param assetToStakePoolIds_ The mapping of asset to stake pool IDs index lookups.
  /// @param stkReceiptTokenToStakePoolIds_ The mapping of stkReceiptToken to stake pool IDs index lookups.
  /// @param receiptTokenFactory_ The receipt token factory.
  /// @param stakePoolConfigs_ The array of stake pool configs. These configs must obey requirements described in
  /// `Configurator.updateConfigs`.
  /// @param rewardPoolConfigs_ The array of reward pool configs. These configs must obey requirements described in
  /// `Configurator.updateConfigs`.
  function applyConfigUpdates(
    StakePool[] storage stakePools_,
    RewardPool[] storage rewardPools_,
    mapping(IERC20 => IdLookup) storage assetToStakePoolIds_,
    mapping(IReceiptToken => IdLookup) storage stkReceiptTokenToStakePoolIds_,
    IReceiptTokenFactory receiptTokenFactory_,
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_
  ) public {
    // Update existing stake pool weights. No need to update the stake pool asset since it cannot change.
    uint16 numExistingStakePools_ = uint16(stakePools_.length);
    for (uint16 i = 0; i < numExistingStakePools_; i++) {
      StakePool storage stakePool_ = stakePools_[i];
      stakePool_.rewardsWeight = stakePoolConfigs_[i].rewardsWeight;
    }

    // Initialize new stake pools.
    for (uint16 i = numExistingStakePools_; i < stakePoolConfigs_.length; i++) {
      initializeStakePool(
        stakePools_, assetToStakePoolIds_, stkReceiptTokenToStakePoolIds_, receiptTokenFactory_, stakePoolConfigs_[i], i
      );
    }

    // Update existing reward pool drip models. No need to update the reward pool asset since it cannot change.
    uint16 numExistingRewardPools_ = uint16(rewardPools_.length);
    for (uint16 i = 0; i < numExistingRewardPools_; i++) {
      rewardPools_[i].dripModel = rewardPoolConfigs_[i].dripModel;
    }

    // Initialize new reward pools.
    for (uint16 i = numExistingRewardPools_; i < rewardPoolConfigs_.length; i++) {
      initializeRewardPool(rewardPools_, receiptTokenFactory_, rewardPoolConfigs_[i], i);
    }

    emit IConfiguratorEvents.ConfigUpdatesApplied(stakePoolConfigs_, rewardPoolConfigs_);
  }

  /// @notice Initializes a new stake pool when it is added to the rewards manager.
  /// @param stakePools_ The array of existing stake pools.
  /// @param assetToStakePoolIds_ The mapping of asset to stake pool IDs index lookups.
  /// @param stkReceiptTokenToStakePoolIds_ The mapping of stkReceiptToken to stake pool IDs index lookups.
  /// @param receiptTokenFactory_ The receipt token factory.
  /// @param stakePoolConfig_ The stake pool config.
  /// @param stakePoolId_ The ID of the stake pool.
  function initializeStakePool(
    StakePool[] storage stakePools_,
    mapping(IERC20 => IdLookup) storage assetToStakePoolIds_,
    mapping(IReceiptToken stkReceiptToken_ => IdLookup stakePoolId_) storage stkReceiptTokenToStakePoolIds_,
    IReceiptTokenFactory receiptTokenFactory_,
    StakePoolConfig calldata stakePoolConfig_,
    uint16 stakePoolId_
  ) internal {
    IReceiptToken stkReceiptToken_ = receiptTokenFactory_.deployReceiptToken(
      stakePoolId_, IReceiptTokenFactory.PoolType.STAKE, stakePoolConfig_.asset.decimals()
    );
    stakePools_.push(
      StakePool({
        amount: 0,
        asset: stakePoolConfig_.asset,
        stkReceiptToken: stkReceiptToken_,
        rewardsWeight: stakePoolConfig_.rewardsWeight
      })
    );
    stkReceiptTokenToStakePoolIds_[stkReceiptToken_] = IdLookup({index: stakePoolId_, exists: true});
    assetToStakePoolIds_[stakePoolConfig_.asset] = IdLookup({index: stakePoolId_, exists: true});

    emit IConfiguratorEvents.StakePoolCreated(stakePoolId_, stkReceiptToken_, stakePoolConfig_.asset);
  }

  /// @notice Initializes a new reward pool when it is added to the rewards manager.
  /// @param rewardPools_ The array of existing reward pools.
  /// @param receiptTokenFactory_ The receipt token factory.
  /// @param rewardPoolConfig_ The reward pool config.
  /// @param rewardPoolId_ The ID of the reward pool.
  function initializeRewardPool(
    RewardPool[] storage rewardPools_,
    IReceiptTokenFactory receiptTokenFactory_,
    RewardPoolConfig calldata rewardPoolConfig_,
    uint16 rewardPoolId_
  ) internal {
    IReceiptToken rewardDepositReceiptToken_ = receiptTokenFactory_.deployReceiptToken(
      rewardPoolId_, IReceiptTokenFactory.PoolType.REWARD, rewardPoolConfig_.asset.decimals()
    );

    rewardPools_.push(
      RewardPool({
        asset: rewardPoolConfig_.asset,
        undrippedRewards: 0,
        cumulativeDrippedRewards: 0,
        dripModel: rewardPoolConfig_.dripModel,
        depositReceiptToken: rewardDepositReceiptToken_,
        lastDripTime: uint128(block.timestamp)
      })
    );

    emit IConfiguratorEvents.RewardPoolCreated(rewardPoolId_, rewardDepositReceiptToken_, rewardPoolConfig_.asset);
  }
}

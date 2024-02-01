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
  function isValidUpdate(
    StakePool[] storage stakePools_,
    RewardPool[] storage rewardPools_,
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    uint16 allowedStakePools_,
    uint16 allowedRewardPools_
  ) internal view returns (bool) {
    // Validate the configuration parameters.
    if (!isValidConfiguration(stakePoolConfigs_, rewardPoolConfigs_, allowedStakePools_, allowedRewardPools_)) {
      return false;
    }

    // Validate number of stake and reward pools. It is only possible to add new pools, not remove existing ones.
    uint256 numExistingStakePools_ = stakePools_.length;
    uint256 numExistingRewardPools_ = rewardPools_.length;
    if (stakePoolConfigs_.length < numExistingStakePools_ || rewardPoolConfigs_.length < numExistingRewardPools_) {
      return false;
    }

    // Validate existing stake pools.
    for (uint16 i = 0; i < numExistingStakePools_; i++) {
      if (stakePools_[i].asset != stakePoolConfigs_[i].asset) return false;
    }

    // Validate existing reward pools.
    for (uint16 i = 0; i < numExistingRewardPools_; i++) {
      if (rewardPools_[i].asset != rewardPoolConfigs_[i].asset) return false;
    }

    return true;
  }

  /// @notice Returns true if the provided configs are generically valid, false otherwise.
  /// @dev Does not include rewards manager-specific checks, e.g. checks based on its existing stake and reward pools.
  function isValidConfiguration(
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    uint16 allowedStakePools_,
    uint16 allowedRewardPools_
  ) internal pure returns (bool) {
    // Validate number of stake pools.
    if (stakePoolConfigs_.length > allowedStakePools_) return false;

    // Validate number of reward pools.
    if (rewardPoolConfigs_.length > allowedRewardPools_) return false;

    // Validate rewards weights.
    if (stakePoolConfigs_.length != 0) {
      uint16 rewardsWeightSum_ = 0;
      for (uint16 i = 0; i < stakePoolConfigs_.length; i++) {
        rewardsWeightSum_ += stakePoolConfigs_[i].rewardsWeight;
      }
      if (rewardsWeightSum_ != MathConstants.ZOC) return false;
    }

    return true;
  }

  function updateConfigs(
    StakePool[] storage stakePools_,
    RewardPool[] storage rewardPools_,
    mapping(IReceiptToken => IdLookup) storage stkReceiptTokenToStakePoolIds_,
    IReceiptTokenFactory receiptTokenFactory_,
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    uint16 allowedStakePools_,
    uint16 allowedRewardPools_
  ) public {
    if (
      !isValidUpdate(
        stakePools_, rewardPools_, stakePoolConfigs_, rewardPoolConfigs_, allowedStakePools_, allowedRewardPools_
      )
    ) revert IConfiguratorErrors.InvalidConfiguration();

    applyConfigUpdates(
      stakePools_,
      rewardPools_,
      stkReceiptTokenToStakePoolIds_,
      receiptTokenFactory_,
      stakePoolConfigs_,
      rewardPoolConfigs_
    );
  }

  /// @notice Apply queued updates to safety module config.
  function applyConfigUpdates(
    StakePool[] storage stakePools_,
    RewardPool[] storage rewardPools_,
    mapping(IReceiptToken => IdLookup) storage stkReceiptTokenToStakePoolIds_,
    IReceiptTokenFactory receiptTokenFactory_,
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_
  ) public {
    // Update existing stake pool weights. No need to update the stake pool asset since it cannot change.
    uint256 numExistingStakePools_ = stakePools_.length;
    for (uint256 i = 0; i < numExistingStakePools_; i++) {
      StakePool storage stakePool_ = stakePools_[i];
      stakePool_.rewardsWeight = stakePoolConfigs_[i].rewardsWeight;
    }

    // Initialize new stake pools.
    for (uint256 i = numExistingStakePools_; i < stakePoolConfigs_.length; i++) {
      initializeStakePool(stakePools_, stkReceiptTokenToStakePoolIds_, receiptTokenFactory_, stakePoolConfigs_[i]);
    }

    // Update existing reward pool drip models. No need to update the reward pool asset since it cannot change.
    uint256 numExistingRewardPools_ = rewardPools_.length;
    for (uint256 i = 0; i < numExistingRewardPools_; i++) {
      rewardPools_[i].dripModel = rewardPoolConfigs_[i].dripModel;
    }

    // Initialize new reward pools.
    for (uint256 i = numExistingRewardPools_; i < rewardPoolConfigs_.length; i++) {
      initializeRewardPool(rewardPools_, receiptTokenFactory_, rewardPoolConfigs_[i]);
    }

    emit IConfiguratorEvents.ConfigUpdatesApplied(stakePoolConfigs_, rewardPoolConfigs_);
  }

  /// @dev Initializes a new stake pool when it is added to the rewards manager.
  function initializeStakePool(
    StakePool[] storage stakePools_,
    mapping(IReceiptToken stkReceiptToken_ => IdLookup stakePoolId_) storage stkReceiptTokenToStakePoolIds_,
    IReceiptTokenFactory receiptTokenFactory_,
    StakePoolConfig calldata stakePoolConfig_
  ) internal {
    uint16 stakePoolId_ = uint16(stakePools_.length);

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

    emit IConfiguratorEvents.StakePoolCreated(stakePoolId_, stkReceiptToken_, stakePoolConfig_.asset);
  }

  /// @dev Initializes a new reward pool when it is added to the rewards manager.
  function initializeRewardPool(
    RewardPool[] storage rewardPools_,
    IReceiptTokenFactory receiptTokenFactory_,
    RewardPoolConfig calldata rewardPoolConfig_
  ) internal {
    uint16 rewardPoolId_ = uint16(rewardPools_.length);

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

    emit IConfiguratorEvents.RewardPoolCreated(rewardPoolId_, rewardPoolConfig_.asset, rewardDepositReceiptToken_);
  }
}

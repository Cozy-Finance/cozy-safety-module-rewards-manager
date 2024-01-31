// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {SafeCastLib} from "cozy-safety-module-shared/lib/SafeCastLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {SafetyModuleState} from "cozy-safety-module-shared/lib/SafetyModuleStates.sol";
import {ICommonErrors} from "../interfaces/ICommonErrors.sol";
import {ISafetyModule} from "../interfaces/ISafetyModule.sol";
import {IManager} from "../interfaces/IManager.sol";
import {IConfiguratorErrors} from "../interfaces/IConfiguratorErrors.sol";
import {ReservePool, RewardPool, IdLookup} from "./structs/Pools.sol";
import {RewardPoolConfig} from "./structs/Rewards.sol";

library ConfiguratorLib {
  using FixedPointMathLib for uint256;
  using SafeCastLib for uint256;

  /// @notice Emitted when a reserve pool is created.
  event ReservePoolCreated(
    uint16 indexed reservePoolId, IReceiptToken stkReceiptToken, IReceiptToken safetyModuleReceiptToken
  );

  /// @notice Emitted when an reward pool is created.
  event RewardPoolCreated(uint16 indexed rewardPoolid, IERC20 rewardAsset, IReceiptToken depositReceiptToken);

  /// @dev Emitted when a rewards manager's configuration updates are applied.
  event ConfigUpdatesApplied(RewardPoolConfig[] rewardPoolConfigs, uint16[] rewardsWeights);

  /// @notice Returns true if the provided configs are valid for the rewards manager, false otherwise.
  function isValidUpdate(
    RewardPool[] storage rewardPools_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    uint16[] calldata rewardsWeights_,
    ISafetyModule safetyModule_,
    IManager manager_
  ) internal view returns (bool) {
    // Validate the configuration parameters.
    if (!isValidConfiguration(rewardPoolConfigs_, rewardsWeights_, safetyModule_, manager_.allowedRewardPools())) {
      return false;
    }

    // Validate number of rewards pools. It is only possible to add new pools, not remove existing ones.
    uint256 numExistingRewardPools_ = rewardPools_.length;
    if (rewardPoolConfigs_.length < numExistingRewardPools_) return false;

    // Validate existing reward pools.
    for (uint16 i = 0; i < numExistingRewardPools_; i++) {
      if (rewardPools_[i].asset != rewardPoolConfigs_[i].asset) return false;
    }

    return true;
  }

  /// @notice Returns true if the provided configs are generically valid, false otherwise.
  /// @dev Does not include rewards manager-specific checks, e.g. checks based on its existing reserve and reward pools.
  function isValidConfiguration(
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    uint16[] calldata rewardsWeights_,
    ISafetyModule safetyModule_,
    uint256 maxRewardPools_
  ) internal view returns (bool) {
    // Validate number of reward pools.
    if (rewardPoolConfigs_.length > maxRewardPools_) return false;

    // Validate rewards weights length.
    if (rewardsWeights_.length != safetyModule_.numReservePools()) return false;

    // Validate rewards weights.
    uint16 rewardsWeightSum_ = 0;
    for (uint16 i = 0; i < rewardsWeights_.length; i++) {
      rewardsWeightSum_ += rewardsWeights_[i];
    }
    if (rewardsWeightSum_ != MathConstants.ZOC) return false;

    return true;
  }

  function updateConfigs(
    ReservePool[] storage reservePools_,
    RewardPool[] storage rewardPools_,
    mapping(IReceiptToken => IdLookup) storage stkReceiptTokenToReservePoolIds_,
    IReceiptTokenFactory receiptTokenFactory_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    uint16[] calldata rewardsWeights_,
    ISafetyModule safetyModule_,
    IManager manager_
  ) public {
    if (!isValidUpdate(rewardPools_, rewardPoolConfigs_, rewardsWeights_, safetyModule_, manager_)) {
      revert IConfiguratorErrors.InvalidConfiguration();
    }

    applyConfigUpdates(
      reservePools_,
      rewardPools_,
      stkReceiptTokenToReservePoolIds_,
      receiptTokenFactory_,
      rewardPoolConfigs_,
      rewardsWeights_,
      safetyModule_
    );
  }

  /// @notice Apply queued updates to safety module config.
  function applyConfigUpdates(
    ReservePool[] storage reservePools_,
    RewardPool[] storage rewardPools_,
    mapping(IReceiptToken => IdLookup) storage stkReceiptTokenToReservePoolIds_,
    IReceiptTokenFactory receiptTokenFactory_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    uint16[] calldata rewardsWeights_,
    ISafetyModule safetyModule_
  ) public {
    if (safetyModule_.safetyModuleState() == SafetyModuleState.TRIGGERED) revert ICommonErrors.InvalidState();

    // Update existing reserve pool weights.
    uint256 numExistingReservePools_ = reservePools_.length;
    for (uint256 i = 0; i < numExistingReservePools_; i++) {
      ReservePool storage reservePool_ = reservePools_[i];
      reservePool_.rewardsWeight = rewardsWeights_[i];
    }

    // Initialize new reserve pools.
    for (uint256 i = numExistingReservePools_; i < rewardsWeights_.length; i++) {
      // This will revert if `i > safetyModule_.numReservePools()`.
      // TODO: Change this after we have fixed the reserve pool struct in the core protocol.
      (,,,,, IReceiptToken safetyModuleReceiptToken_,) = safetyModule_.reservePools(i);
      initializeReservePool(
        reservePools_,
        stkReceiptTokenToReservePoolIds_,
        receiptTokenFactory_,
        safetyModuleReceiptToken_,
        rewardsWeights_[i]
      );
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

    emit ConfigUpdatesApplied(rewardPoolConfigs_, rewardsWeights_);
  }

  /// @dev Initializes a new reserve pool when it is added to the rewards manager.
  function initializeReservePool(
    ReservePool[] storage reservePools_,
    mapping(IReceiptToken stkReceiptToken_ => IdLookup reservePoolId_) storage stkReceiptTokenToReservePoolIds_,
    IReceiptTokenFactory receiptTokenFactory_,
    IReceiptToken safetyModuleReceiptToken_,
    uint16 rewardsWeight_
  ) internal {
    uint16 reservePoolId_ = uint16(reservePools_.length);

    IReceiptToken stkReceiptToken_ = receiptTokenFactory_.deployReceiptToken(
      reservePoolId_, IReceiptTokenFactory.PoolType.STAKE, safetyModuleReceiptToken_.decimals()
    );
    reservePools_.push(
      ReservePool({
        amount: 0,
        safetyModuleReceiptToken: safetyModuleReceiptToken_,
        stkReceiptToken: stkReceiptToken_,
        rewardsWeight: rewardsWeight_
      })
    );
    stkReceiptTokenToReservePoolIds_[stkReceiptToken_] = IdLookup({index: reservePoolId_, exists: true});

    emit ReservePoolCreated(reservePoolId_, stkReceiptToken_, safetyModuleReceiptToken_);
  }

  /// @dev Initializes a new reward pool when it is added to the rewards manager.
  function initializeRewardPool(
    RewardPool[] storage rewardPools_,
    IReceiptTokenFactory receiptTokenFactory_,
    RewardPoolConfig calldata rewardPoolConfig_
  ) internal {
    uint16 rewardPoolid_ = uint16(rewardPools_.length);

    IReceiptToken rewardDepositReceiptToken_ = receiptTokenFactory_.deployReceiptToken(
      rewardPoolid_, IReceiptTokenFactory.PoolType.REWARD, rewardPoolConfig_.asset.decimals()
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

    emit RewardPoolCreated(rewardPoolid_, rewardPoolConfig_.asset, rewardDepositReceiptToken_);
  }
}

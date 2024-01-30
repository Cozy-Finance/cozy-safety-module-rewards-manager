// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IReceiptToken} from "../interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "../interfaces/IReceiptTokenFactory.sol";
import {ICommonErrors} from "../interfaces/ICommonErrors.sol";
import {IConfiguratorErrors} from "../interfaces/IConfiguratorErrors.sol";
import {ITrigger} from "../interfaces/ITrigger.sol";
import {IManager} from "../interfaces/IManager.sol";
import {ReservePool, RewardPool, IdLookup} from "./structs/Pools.sol";
import {SafetyModuleState, TriggerState} from "./SafetyModuleStates.sol";
import {MathConstants} from "./MathConstants.sol";
import {SafeCastLib} from "./SafeCastLib.sol";

library ConfiguratorLib {
  using FixedPointMathLib for uint256;
  using SafeCastLib for uint256;

  /// @dev Emitted when a safety module's queued configuration updates are applied.
  event ConfigUpdatesFinalized(
    ReservePoolConfig[] reservePoolConfigs,
    RewardPoolConfig[] rewardPoolConfigs
  );

  /// @notice Emitted when an reward pool is created.
  event RewardPoolCreated(uint16 indexed rewardPoolid, address rewardAssetAddress, address depositTokenAddress);

  /// @notice Execute queued updates to safety module configs.
  /// @param lastConfigUpdate_ Metadata about the most recently queued configuration update.
  /// @param safetyModuleState_ The state of the safety module.
  /// @param reservePools_ The array of existing reserve pools.
  /// @param rewardPools_ The array of existing reward pools.
  /// @param delays_ The existing delays config.
  /// @param stkTokenToReservePoolIds_ The mapping of stktokens to reserve pool IDs.
  /// @param configUpdates_ The new configs. Includes:
  /// - reservePoolConfigs: The array of new reserve pool configs, sorted by associated ID. The array may also
  /// include config for new reserve pools.
  /// - rewardPoolConfigs: The array of new reward pool configs, sorted by associated ID. The
  /// array may also include config for new reward pools.
  /// - triggerConfigUpdates: The array of trigger config updates. It only needs to include config for updates to
  /// existing triggers or new triggers.
  /// - delaysConfig: The new delays config.
  function finalizeUpdateConfigs(
    ConfigUpdateMetadata storage lastConfigUpdate_,
    SafetyModuleState safetyModuleState_,
    ReservePool[] storage reservePools_,
    RewardPool[] storage rewardPools_,
    mapping(ITrigger => Trigger) storage triggerData_,
    Delays storage delays_,
    mapping(IReceiptToken => IdLookup) storage stkTokenToReservePoolIds_,
    IReceiptTokenFactory receiptTokenFactory_,
    UpdateConfigsCalldataParams calldata configUpdates_
  ) external {
    if (safetyModuleState_ == SafetyModuleState.TRIGGERED) revert ICommonErrors.InvalidState();
    if (block.timestamp < lastConfigUpdate_.configUpdateTime) revert ICommonErrors.InvalidStateTransition();
    if (block.timestamp > lastConfigUpdate_.configUpdateDeadline) revert ICommonErrors.InvalidStateTransition();
    if (
      keccak256(
        abi.encode(
          configUpdates_.reservePoolConfigs,
          configUpdates_.rewardPoolConfigs,
          configUpdates_.triggerConfigUpdates,
          configUpdates_.delaysConfig
        )
      ) != lastConfigUpdate_.queuedConfigUpdateHash
    ) revert IConfiguratorErrors.InvalidConfiguration();

    // Reset the config update hash.
    lastConfigUpdate_.queuedConfigUpdateHash = 0;
    applyConfigUpdates(
      reservePools_,
      rewardPools_,
      triggerData_,
      delays_,
      stkTokenToReservePoolIds_,
      receiptTokenFactory_,
      configUpdates_
    );
  }

  /// @notice Returns true if the provided configs are valid for the rewards manager, false otherwise.
  function isValidUpdate(
    RewardsPoolConfig[] calldata rewardPoolConfigs_,
    uint16[] calldata rewardsWeights_,
    IManager manager_
  ) internal view returns (bool) {
    // Validate the configuration parameters.
    if (!isValidConfiguration(rewardPoolConfigs_, rewardsWeights_, manager_.allowedRewardPools())) return false;

    // Validate number of rewards pools. It is only possible to add new pools, not remove existing ones.
    uint256 numExistingRewardPools_ = rewardPools_.length;
    if (rewardPoolConfigs_.length < numExistingRewardPools_) return false;

    // Validate existing reward pools.
    for (uint16 i = 0; i < numExistingRewardPools_; i++) {
      if (rewardPools_[i].asset != configUpdates_.rewardPoolConfigs[i].asset) return false;
    }

    return true;
  }

  /// @notice Returns true if the provided configs are generically valid, false otherwise.
  /// @dev Does not include rewards manager-specific checks, e.g. checks based on existing reserve and reward pools.
  function isValidConfiguration(
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    uint16[] calldata rewardsWeights_,
    uint256 maxRewardPools_
  ) internal pure returns (bool) {
    // Validate number of reward pools.
    if (rewardPoolConfigs_.length > maxRewardPools_) return false;

    // Validate rewards weights.
    uint16 rewardsWeightSum_ = 0;
    for (uint16 i = 0; i < rewardsWeights_.length; i++) {
      rewardsWeightSum_ += rewardsWeights_[i];
    }
    if (rewardsWeightSum_ != MathConstants.ZOC) return false;

    return true;
  }

  /// @notice Apply queued updates to safety module config.
  function applyConfigUpdates(
    ReservePool[] storage reservePools_,
    RewardPool[] storage rewardPools_,
    mapping(IReceiptToken => IdLookup) storage stkTokenToReservePoolIds_,
    IReceiptTokenFactory receiptTokenFactory_,
    UpdateConfigsCalldataParams calldata configUpdates_
  ) public {
    // Update existing reserve pool weights.
    uint256 numExistingReservePools_ = reservePools_.length;
    for (uint256 i = 0; i < numExistingReservePools_; i++) {
      ReservePool storage reservePool_ = reservePools_[i];
      reservePool_.rewardsWeight = rewardsWeights_[i];
    }

    // Initialize new reserve pools.
    for (uint256 i = numExistingReservePools_; i < configUpdates_.reservePoolConfigs.length; i++) {
      initializeReservePool(
        reservePools_, stkTokenToReservePoolIds_, receiptTokenFactory_, configUpdates_.reservePoolConfigs[i]
      );
    }

    // Update existing reward pool drip models. No need to update the reward pool asset since it cannot change.
    uint256 numExistingRewardPools_ = rewardPools_.length;
    for (uint256 i = 0; i < numExistingRewardPools_; i++) {
      rewardPools_[i].dripModel = configUpdates_.rewardPoolConfigs[i].dripModel;
    }

    // Initialize new reward pools.
    for (uint256 i = numExistingRewardPools_; i < rewardPoolConfigs_.length; i++) {
      initializeRewardPool(rewardPools_, receiptTokenFactory_, rewardPoolConfigs_[i]);
    }

    emit ConfigUpdatesFinalized(
      configUpdates_.reservePoolConfigs,
      configUpdates_.rewardPoolConfigs,
      configUpdates_.triggerConfigUpdates,
      configUpdates_.delaysConfig
    );
  }

  /// @dev Initializes a new reward pool when it is added to the safety module.
  function initializeRewardPool(
    RewardPool[] storage rewardPools_,
    IReceiptTokenFactory receiptTokenFactory_,
    RewardPoolConfig calldata rewardPoolConfig_
  ) internal {
    uint16 rewardPoolid_ = uint16(rewardPools_.length);

    IReceiptToken rewardDepositToken_ = receiptTokenFactory_.deployReceiptToken(
      rewardPoolid_, IReceiptTokenFactory.PoolType.REWARD, rewardPoolConfig_.asset.decimals()
    );

    rewardPools_.push(
      RewardPool({
        asset: rewardPoolConfig_.asset,
        undrippedRewards: 0,
        cumulativeDrippedRewards: 0,
        dripModel: rewardPoolConfig_.dripModel,
        depositToken: rewardDepositToken_,
        lastDripTime: uint128(block.timestamp)
      })
    );

    emit RewardPoolCreated(rewardPoolid_, address(rewardPoolConfig_.asset), address(rewardDepositToken_));
  }
}

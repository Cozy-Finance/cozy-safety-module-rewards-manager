// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {RewardPoolConfig, StakePoolConfig} from "../lib/structs/Configs.sol";

interface IConfiguratorEvents {
  /// @notice Emitted when a stake pool is created.
  /// @param stakePoolId The ID of the stake pool.
  /// @param stkReceiptToken The receipt token for the stake pool.
  /// @param asset The underlying asset of the stake pool.
  event StakePoolCreated(uint16 indexed stakePoolId, IReceiptToken stkReceiptToken, IERC20 asset);

  /// @notice Emitted when an reward pool is created.
  /// @param rewardPoolId The ID of the reward pool.
  /// @param depositReceiptToken The receipt token for the reward pool.
  /// @param asset The underlying asset of the reward pool.
  event RewardPoolCreated(uint16 indexed rewardPoolId, IReceiptToken depositReceiptToken, IERC20 asset);

  /// @notice Emitted when a rewards manager's config updates are applied.
  /// @param stakePoolConfigs The updated stake pool configs.
  /// @param rewardPoolConfigs The updated reward pool configs.
  event ConfigUpdatesApplied(StakePoolConfig[] stakePoolConfigs, RewardPoolConfig[] rewardPoolConfigs);
}

// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IGovernable} from "cozy-safety-module-shared/interfaces/IGovernable.sol";
import {IRewardsManager} from "./IRewardsManager.sol";
import {RewardPoolConfig, StakePoolConfig} from "../lib/structs/Configs.sol";

interface ICozyManager is IGovernable {
  /// @notice Deploys a new Rewards Manager with the provided parameters.
  /// @param owner_ The owner of the rewards manager.
  /// @param pauser_ The pauser of the rewards manager.
  /// @param stakePoolConfigs_ The array of stake pool configs, sorted by underlying asset address.
  /// @param rewardPoolConfigs_  The array of new reward pool configs, sorted by reward pool ID.
  /// @param salt_ Used to compute the resulting address of the rewards manager.
  function createRewardsManager(
    address owner_,
    address pauser_,
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    bytes32 salt_
  ) external returns (IRewardsManager rewardsManager_);
}

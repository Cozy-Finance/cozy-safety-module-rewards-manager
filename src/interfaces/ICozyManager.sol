// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IGovernable} from "cozy-safety-module-shared/interfaces/IGovernable.sol";
import {IRewardsManager} from "./IRewardsManager.sol";
import {IRewardsManagerFactory} from "./IRewardsManagerFactory.sol";
import {RewardPoolConfig, StakePoolConfig} from "../lib/structs/Configs.sol";

interface ICozyManager is IGovernable {
  /// @notice Deploys a new rewards manager with the provided parameters.
  /// @param owner_ The owner of the rewards manager.
  /// @param pauser_ The pauser of the rewards manager.
  /// @param stakePoolConfigs_ The array of stake pool configs, sorted by underlying asset address.
  /// @param rewardPoolConfigs_  The array of new reward pool configs, sorted by reward pool ID.
  /// @param salt_ Used to compute the resulting address of the rewards manager.
  /// @return rewardsManager_ The newly created rewards manager.
  function createRewardsManager(
    address owner_,
    address pauser_,
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    bytes32 salt_
  ) external returns (IRewardsManager rewardsManager_);

  /// @notice Returns the rewards manager factory.
  /// @return rewardsManagerFactory_ The rewards manager factory.
  function rewardsManagerFactory() external view returns (IRewardsManagerFactory rewardsManagerFactory_);

  /// @notice Pauses an list of reward managers.
  /// @param rewardsManagers_ The array of rewards managers to pause.
  function pause(IRewardsManager[] calldata rewardsManagers_) external;

  /// @notice Unpauses an list of reward managers.
  /// @param rewardsManagers_ The array of rewards managers to unpause.
  function unpause(IRewardsManager[] calldata rewardsManagers_) external;
}

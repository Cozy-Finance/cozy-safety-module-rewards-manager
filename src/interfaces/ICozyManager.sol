// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IGovernable} from "cozy-safety-module-libs/interfaces/IGovernable.sol";
import {IRewardsManager} from "./IRewardsManager.sol";
import {IRewardsManagerFactory} from "./IRewardsManagerFactory.sol";
import {ICozyManagerEvents} from "./ICozyManagerEvents.sol";
import {RewardPoolConfig, StakePoolConfig} from "../lib/structs/Configs.sol";

interface ICozyManager is IGovernable, ICozyManagerEvents {
  /// @notice Cozy protocol RewardsManagerFactory.
  function rewardsManagerFactory() external view returns (IRewardsManagerFactory rewardsManagerFactory_);

  /// @notice The default claim fee used for RewardsManagers, represented as a ZOC (e.g. 500 = 5%).
  function claimFee() external view returns (uint16);

  /// @notice The default deposit fee used for RewardsManagers, represented as a ZOC (e.g. 500 = 5%).
  function depositFee() external view returns (uint16);

  /// @notice Update the default claim fee used for RewardsManagers.
  /// @param claimFee_ The new default claim fee.
  function updateClaimFee(uint16 claimFee_) external;

  /// @notice Update the default deposit fee used for RewardsManagers.
  /// @param depositFee_ The new default deposit fee.
  function updateDepositFee(uint16 depositFee_) external;

  /// @notice Update the claim fee for a specific RewardsManager.
  /// @param rewardsManager_ The RewardsManager to update the claim fee for.
  /// @param claimFee_ The new fee claim fee for the RewardsManager.
  function updateOverrideClaimFee(IRewardsManager rewardsManager_, uint16 claimFee_) external;

  /// @notice Update the deposit fee for a specific RewardsManager.
  /// @param rewardsManager_ The RewardsManager to update the deposit fee for.
  /// @param depositFee_ The new fee deposit fee for the RewardsManager.
  function updateOverrideDepositFee(IRewardsManager rewardsManager_, uint16 depositFee_) external;

  /// @notice Reset the override claim fee for the specified RewardsManager back to the default.
  /// @param rewardsManager_ The RewardsManager to update the claim fee for.
  function resetOverrideClaimFee(IRewardsManager rewardsManager_) external;

  /// @notice Reset the override deposit fee for the specified RewardsManager back to the default.
  /// @param rewardsManager_ The RewardsManager to update the deposit fee for.
  function resetOverrideDepositFee(IRewardsManager rewardsManager_) external;

  /// @notice For the specified RewardsManager, returns the claim fee.
  function getClaimFee(IRewardsManager rewardsManager_) external view returns (uint16);

  /// @notice For the specified RewardsManager, returns the deposit fee.
  function getDepositFee(IRewardsManager rewardsManager_) external view returns (uint16);

  /// @notice Batch pauses rewardsManagers_. The manager's pauser or owner can perform this action.
  /// @param rewardsManagers_ The array of rewards managers to pause.
  function pause(IRewardsManager[] calldata rewardsManagers_) external;

  /// @notice Batch unpauses rewardsManagers_. The manager's owner can perform this action.
  /// @param rewardsManagers_ The array of rewards managers to unpause.
  function unpause(IRewardsManager[] calldata rewardsManagers_) external;

  /// @notice Deploys a new Rewards Manager with the provided parameters.
  /// @param owner_ The owner of the rewards manager.
  /// @param pauser_ The pauser of the rewards manager.
  /// @param stakePoolConfigs_ The array of stake pool configs. These configs must obey requirements described in
  /// `Configurator.updateConfigs`.
  /// @param rewardPoolConfigs_  The array of reward pool configs. These configs must obey requirements described in
  /// `Configurator.updateConfigs`.
  /// @param salt_ Used to compute the resulting address of the rewards manager.
  /// @return rewardsManager_ The newly created rewards manager.
  function createRewardsManager(
    address owner_,
    address pauser_,
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    bytes32 salt_
  ) external returns (IRewardsManager rewardsManager_);

  /// @notice Given a `caller_` and `salt_`, compute and return the address of the RewardsManager deployed with
  /// `createRewardsManager`.
  /// @param caller_ The caller of the `createRewardsManager` function.
  /// @param salt_ Used to compute the resulting address of the rewards manager along with `caller_`.
  function computeRewardsManagerAddress(address caller_, bytes32 salt_) external view returns (address);
}

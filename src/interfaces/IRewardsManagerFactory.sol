// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {ISafetyModule} from "./ISafetyModule.sol";
import {IRewardsManager} from "./IRewardsManager.sol";
import {RewardPoolConfig, StakePoolConfig} from "../lib/structs/Configs.sol";

interface IRewardsManagerFactory {
  /// @dev Emitted when a new Rewards Manager is deployed.
  event RewardsManagerDeployed(IRewardsManager rewardsManager, ISafetyModule safetyModule);

  function computeAddress(bytes32 baseSalt_) external view returns (address);

  function deployRewardsManager(
    address owner_,
    address pauser_,
    address safetyModuleAddress_,
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    bytes32 baseSalt_
  ) external returns (IRewardsManager rewardsManager_);

  function salt(bytes32 baseSalt_) external view returns (bytes32);

  function rewardsManagerLogic() external view returns (IRewardsManager);
}

// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IManager} from "./IManager.sol";
import {IRewardsManager} from "./IRewardsManager.sol";
import {RewardPoolConfig} from "../lib/structs/Rewards.sol";

interface IRewardsManagerFactory {
  /// @dev Emitted when a new Rewards Manager is deployed.
  event RewardsManagerDeployed(IRewardsManager rewardsManager);

  function computeAddress(bytes32 baseSalt_) external view returns (address);

  function deployRewardsManager(
    address owner_,
    address pauser_,
    address safetyModuleAddress_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    uint16[] calldata rewardsWeights_,
    bytes32 baseSalt_
  ) external returns (IRewardsManager rewardsManager_);

  function cozyManager() external view returns (IManager);

  function salt(bytes32 baseSalt_) external view returns (bytes32);

  function rewardsManagerLogic() external view returns (IRewardsManager);
}

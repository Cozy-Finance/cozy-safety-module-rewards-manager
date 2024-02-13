// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {Governable} from "cozy-safety-module-shared/lib/Governable.sol";
import {ICozyManager} from "./interfaces/ICozyManager.sol";
import {IRewardsManager} from "./interfaces/IRewardsManager.sol";
import {IRewardsManagerFactory} from "./interfaces/IRewardsManagerFactory.sol";
import {RewardPoolConfig, StakePoolConfig} from "./lib/structs/Configs.sol";
import {ConfiguratorLib} from "./lib/ConfiguratorLib.sol";

contract CozyManager is Governable, ICozyManager {
  /// @notice Cozy protocol RewardsManagerFactory.
  IRewardsManagerFactory public immutable rewardsManagerFactory;

  /// @dev Thrown when an reward manager's configuration does not meet all requirements.
  error InvalidConfiguration();

  /// @param owner_ The Cozy protocol owner.
  /// @param pauser_ The Cozy protocol pauser.
  /// @param rewardsManagerFactory_ The Cozy protocol RewardsManagerFactory.
  constructor(address owner_, address pauser_, IRewardsManagerFactory rewardsManagerFactory_) {
    _assertAddressNotZero(owner_);
    _assertAddressNotZero(address(rewardsManagerFactory_));
    __initGovernable(owner_, pauser_);

    rewardsManagerFactory = rewardsManagerFactory_;
  }

  // -------------------------------------------------
  // -------- Batched Rewards Manager Actions --------
  // -------------------------------------------------

  /// @notice Batch pauses rewardsManagers_. The manager's pauser or owner can perform this action.
  function pause(IRewardsManager[] calldata rewardsManagers_) external {
    if (msg.sender != pauser && msg.sender != owner) revert Unauthorized();
    for (uint256 i = 0; i < rewardsManagers_.length; i++) {
      rewardsManagers_[i].pause();
    }
  }

  /// @notice Batch unpauses rewardsManagers_. The manager's owner can perform this action.
  function unpause(IRewardsManager[] calldata rewardsManagers_) external onlyOwner {
    for (uint256 i = 0; i < rewardsManagers_.length; i++) {
      rewardsManagers_[i].unpause();
    }
  }

  // ----------------------------------------
  // -------- Permissionless Actions --------
  // ----------------------------------------

  /// @notice Deploys a new Rewards Manager with the provided parameters.
  /// @param owner_ The owner of the rewards manager.
  /// @param pauser_ The pauser of the rewards manager.
  /// @param stakePoolConfigs_ The array of stake pool configs, sorted by sorted by underlying asset address.
  /// @param rewardPoolConfigs_  The array of new reward pool configs, sorted by reward pool ID.
  /// @param salt_ Used to compute the resulting address of the rewards manager.
  function createRewardsManager(
    address owner_,
    address pauser_,
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    bytes32 salt_
  ) external returns (IRewardsManager rewardsManager_) {
    _assertAddressNotZero(owner_);
    _assertAddressNotZero(pauser_);

    rewardsManager_ =
      rewardsManagerFactory.deployRewardsManager(owner_, pauser_, stakePoolConfigs_, rewardPoolConfigs_, salt_);
  }
}

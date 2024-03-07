// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Governable} from "cozy-safety-module-shared/lib/Governable.sol";
import {ICozyManager} from "./interfaces/ICozyManager.sol";
import {IRewardsManager} from "./interfaces/IRewardsManager.sol";
import {IRewardsManagerFactory} from "./interfaces/IRewardsManagerFactory.sol";
import {RewardPoolConfig, StakePoolConfig} from "./lib/structs/Configs.sol";

contract CozyManager is Governable, ICozyManager {
  /// @notice Cozy protocol RewardsManagerFactory.
  IRewardsManagerFactory public immutable rewardsManagerFactory;

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
  /// @param rewardsManagers_ The array of rewards managers to pause.
  function pause(IRewardsManager[] calldata rewardsManagers_) external {
    if (msg.sender != pauser && msg.sender != owner) revert Unauthorized();
    for (uint256 i = 0; i < rewardsManagers_.length; i++) {
      rewardsManagers_[i].pause();
    }
  }

  /// @notice Batch unpauses rewardsManagers_. The manager's owner can perform this action.
  /// @param rewardsManagers_ The array of rewards managers to unpause.
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
  /// @param stakePoolConfigs_ The array of stake pool configs. These configs must obey requirements described in
  /// `Configurator.updateConfigs`.
  /// @param rewardPoolConfigs_  The array of reward pool configs. These configs must obey requirements described in
  /// `Configurator.updateConfigs`.
  /// @param salt_ Used to compute the resulting address of the rewards manager along with `msg.sender`.
  /// @return rewardsManager_ The newly created rewards manager.
  function createRewardsManager(
    address owner_,
    address pauser_,
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    bytes32 salt_
  ) external returns (IRewardsManager rewardsManager_) {
    _assertAddressNotZero(owner_);
    _assertAddressNotZero(pauser_);

    bytes32 deploySalt_ = _computeDeploySalt(msg.sender, salt_);

    rewardsManager_ =
      rewardsManagerFactory.deployRewardsManager(owner_, pauser_, stakePoolConfigs_, rewardPoolConfigs_, deploySalt_);
  }

  /// @notice Given a `caller_` and `salt_`, compute and return the address of the RewardsManager deployed with
  /// `createRewardsManager`.
  /// @param caller_ The caller of the `createRewardsManager` function.
  /// @param salt_ Used to compute the resulting address of the rewards manager along with `caller_`.
  function computeRewardsManagerAddress(address caller_, bytes32 salt_) external view returns (address) {
    bytes32 deploySalt_ = _computeDeploySalt(caller_, salt_);
    return rewardsManagerFactory.computeAddress(deploySalt_);
  }

  /// @notice Given a `caller_` and `salt_`, return the salt used to compute the RewardsManager address deployed from
  /// the `rewardsManagerFactory`.
  /// @param caller_ The caller of the `createRewardsManager` function.
  /// @param salt_ Used to compute the resulting address of the rewards manager along with `caller_`.
  function _computeDeploySalt(address caller_, bytes32 salt_) internal pure returns (bytes32) {
    // To avoid front-running of RewardsManager deploys, msg.sender is used for the deploy salt.
    return keccak256(abi.encodePacked(salt_, caller_));
  }
}

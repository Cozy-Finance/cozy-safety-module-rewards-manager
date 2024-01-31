// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {ISafetyModule} from "./interfaces/ISafetyModule.sol";
import {Configurator} from "./lib/Configurator.sol";
import {ConfiguratorLib} from "./lib/ConfiguratorLib.sol";
import {RewardsManagerCommon} from "./lib/RewardsManagerCommon.sol";
import {Depositor} from "./lib/Depositor.sol";
import {RewardsDistributor} from "./lib/RewardsDistributor.sol";
import {Staker} from "./lib/Staker.sol";
import {RewardPoolConfig, StakePoolConfig} from "./lib/structs/Configs.sol";

contract RewardsManager is RewardsManagerCommon, Configurator, Depositor, RewardsDistributor, Staker {
  /// @dev Thrown if the contract is already initialized.
  error Initialized();

  constructor(IReceiptTokenFactory receiptTokenFactory_, uint8 allowedStakePools_, uint8 allowedRewardPools_) {
    _assertAddressNotZero(address(receiptTokenFactory_));
    receiptTokenFactory = receiptTokenFactory_;
    allowedStakePools = allowedStakePools_;
    allowedRewardPools = allowedRewardPools_;
  }

  function initialize(
    address owner_,
    address pauser_,
    StakePoolConfig[] calldata stakePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_
  ) external {
    if (address(receiptTokenFactory) != address(0)) revert Initialized();

    // Rewards managers are minimal proxies, so the owner and pauser is set to address(0) in the constructor for the
    // logic contract. When the rewards manager is initialized for the minimal proxy, we update the owner and pauser.
    __initGovernable(owner_, pauser_);

    ConfiguratorLib.applyConfigUpdates(
      stakePools, rewardPools, stkReceiptTokenToStakePoolIds, receiptTokenFactory, stakePoolConfigs_, rewardPoolConfigs_
    );
  }
}

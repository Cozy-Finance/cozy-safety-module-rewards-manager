// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {Configurator} from "./lib/Configurator.sol";
import {ConfiguratorLib} from "./lib/ConfiguratorLib.sol";
import {RewardsManagerCommon} from "./lib/RewardsManagerCommon.sol";
import {RewardsManagerInspector} from "./lib/RewardsManagerInspector.sol";
import {Depositor} from "./lib/Depositor.sol";
import {RewardsDistributor} from "./lib/RewardsDistributor.sol";
import {Staker} from "./lib/Staker.sol";
import {StateChanger} from "./lib/StateChanger.sol";
import {RewardPoolConfig, StakePoolConfig} from "./lib/structs/Configs.sol";
import {IConfiguratorErrors} from "./interfaces/IConfiguratorErrors.sol";
import {ICozyManager} from "./interfaces/ICozyManager.sol";

contract RewardsManager is
  RewardsManagerCommon,
  RewardsManagerInspector,
  Configurator,
  Depositor,
  RewardsDistributor,
  Staker,
  StateChanger
{
  bool public initialized;

  /// @dev Thrown if the contract is already initialized.
  error Initialized();

  constructor(
    ICozyManager cozyManager_,
    IReceiptTokenFactory receiptTokenFactory_,
    uint8 allowedStakePools_,
    uint8 allowedRewardPools_
  ) {
    _assertAddressNotZero(address(cozyManager_));
    _assertAddressNotZero(address(receiptTokenFactory_));
    cozyManager = cozyManager_;
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
    if (initialized) revert Initialized();
    if (
      !ConfiguratorLib.isValidConfiguration(
        stakePoolConfigs_, rewardPoolConfigs_, 0, allowedStakePools, allowedRewardPools
      )
    ) revert IConfiguratorErrors.InvalidConfiguration();

    // Rewards managers are minimal proxies, so the owner and pauser is set to address(0) in the constructor for the
    // logic contract. When the rewards manager is initialized for the minimal proxy, we update the owner and pauser.
    __initGovernable(owner_, pauser_);

    ConfiguratorLib.applyConfigUpdates(
      stakePools,
      rewardPools,
      assetToStakePoolIds,
      stkReceiptTokenToStakePoolIds,
      receiptTokenFactory,
      stakePoolConfigs_,
      rewardPoolConfigs_
    );
    initialized = true;
  }
}

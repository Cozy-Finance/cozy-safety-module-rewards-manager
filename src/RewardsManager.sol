// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {ISafetyModule} from "./interfaces/ISafetyModule.sol";
import {IManager} from "./interfaces/IManager.sol";
import {Configurator} from "./lib/Configurator.sol";
import {ConfiguratorLib} from "./lib/ConfiguratorLib.sol";
import {RewardsManagerCommon} from "./lib/RewardsManagerCommon.sol";
import {Depositor} from "./lib/Depositor.sol";
import {RewardsDistributor} from "./lib/RewardsDistributor.sol";
import {Staker} from "./lib/Staker.sol";
import {RewardPoolConfig} from "./lib/structs/Rewards.sol";

contract RewardsManager is RewardsManagerCommon, Configurator, Depositor, RewardsDistributor, Staker {
  /// @dev Thrown if the contract is already initialized.
  error Initialized();

  constructor(IManager manager_, IReceiptTokenFactory receiptTokenFactory_) {
    _assertAddressNotZero(address(manager_));
    _assertAddressNotZero(address(receiptTokenFactory_));
    cozyManager = manager_;
    receiptTokenFactory = receiptTokenFactory_;
  }

  function initialize(
    address owner_,
    address pauser_,
    address safetyModuleAddress_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    uint16[] calldata rewardsWeights_
  ) external {
    if (address(safetyModule) != address(0)) revert Initialized();

    // Rewards managers are minimal proxies, so the owner and pauser is set to address(0) in the constructor for the
    // logic contract. When the rewards manager is initialized for the minimal proxy, we update the owner and pauser.
    __initGovernable(owner_, pauser_);

    ISafetyModule safetyModule_ = ISafetyModule(safetyModuleAddress_);
    ConfiguratorLib.applyConfigUpdates(
      reservePools,
      rewardPools,
      stkReceiptTokenToReservePoolIds,
      receiptTokenFactory,
      rewardPoolConfigs_,
      rewardsWeights_,
      safetyModule_
    );
    safetyModule = safetyModule_;
  }
}

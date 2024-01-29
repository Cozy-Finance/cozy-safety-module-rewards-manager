// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {ISafetyModule} from "./interfaces/ISafetyModule.sol";
import {IReceiptTokenFactory} from "./interfaces/IReceiptTokenFactory.sol";
import {RewardsModuleConfigurator} from "./lib/RewardsModuleConfigurator.sol";
import {RewardsModuleCommon} from "./lib/RewardsModuleCommon.sol";
import {RewardsModuleDepositor} from "./lib/RewardsModuleDepositor.sol";
import {RewardsModuleDistributor} from "./lib/RewardsModuleDistributor.sol";
import {RewardsModuleStaker} from "./lib/RewardsModuleStaker.sol";

contract RewardsModule is
  RewardsModuleCommon,
  RewardsModuleConfigurator,
  RewardsModuleDepositor,
  RewardsModuleDistributor,
  RewardsModuleStaker
{
  /// @dev Thrown if the contract is already initialized.
  error Initialized();

  constructor(IReceiptTokenFactory receiptTokenFactory_) {
    receiptTokenFactory = receiptTokenFactory_;
  }

  function initialize(address owner_, address pauser_, address safetyModule_) external {
    if (address(safetyModule) != address(0)) revert Initialized();

    // Safety Modules are minimal proxies, so the owner and pauser is set to address(0) in the constructor for the logic
    // contract. When the rewards module is initialized for the minimal proxy, we update the owner and pauser.
    __initGovernable(owner_, pauser_);

    safetyModule = ISafetyModule(safetyModule_);
  }
}

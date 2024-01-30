// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {SafetyModuleState} from "cozy-safety-module-shared/lib/SafetyModuleStates.sol";

contract MockSafetyModule {
  SafetyModuleState public safetyModuleState;

  constructor(SafetyModuleState _safetyModuleState) {
    safetyModuleState = _safetyModuleState;
  }

  function setSafetyModuleState(SafetyModuleState _safetyModuleState) public {
    safetyModuleState = _safetyModuleState;
  }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Governable} from "cozy-safety-module-shared/lib/Governable.sol";
import {SafetyModuleState} from "cozy-safety-module-shared/lib/SafetyModuleStates.sol";
import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";
import {ReservePool, RewardPool} from "./structs/Pools.sol";
import {ICommonErrors} from "../interfaces/ICommonErrors.sol";

abstract contract Configurator is RewardsManagerCommon, Governable {}

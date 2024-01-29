// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Governable} from "cozy-safety-module-shared/lib/Governable.sol";
import {RewardsModuleCommon} from "./RewardsModuleCommon.sol";

// TODO
abstract contract Configurator is RewardsModuleCommon, Governable {}

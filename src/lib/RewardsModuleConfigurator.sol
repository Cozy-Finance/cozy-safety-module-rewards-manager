// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Governable} from "./Governable.sol";
import {RewardsModuleCommon} from "./RewardsModuleCommon.sol";

// TODO
abstract contract RewardsModuleConfigurator is RewardsModuleCommon, Governable {}

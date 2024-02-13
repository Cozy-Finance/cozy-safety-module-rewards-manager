// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";

struct RewardPoolConfig {
  IERC20 asset;
  IDripModel dripModel;
}

struct StakePoolConfig {
  IERC20 asset;
  uint16 rewardsWeight;
}

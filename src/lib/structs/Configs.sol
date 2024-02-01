// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IDripModel} from "../../interfaces/IDripModel.sol";

struct RewardPoolConfig {
  IERC20 asset;
  IDripModel dripModel;
}

struct StakePoolConfig {
  IERC20 asset;
  uint16 rewardsWeight;
}

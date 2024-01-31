// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IDripModel} from "../../interfaces/IDripModel.sol";

struct AssetPool {
  // The total balance of assets held by a RewardsManager, should be equivalent to
  // token.balanceOf(address(this)), discounting any assets directly sent
  // to the RewardsManager via direct transfer.
  uint256 amount;
}

struct StakePool {
  uint256 amount;
  IERC20 asset;
  IReceiptToken stkReceiptToken;
  /// @dev The weighting of each stkToken's claim to all reward pools in terms of a ZOC. Must sum to 1.
  /// e.g. stkTokenA = 10%, means they're eligible for up to 10% of each pool, scaled to their balance of stkTokenA
  /// wrt totalSupply.
  uint16 rewardsWeight;
}

struct RewardPool {
  uint256 undrippedRewards;
  /// @dev The cumulative amount of rewards dripped to the pool since the last weight change. This value is reset to 0
  /// anytime rewards weights are updated.
  uint256 cumulativeDrippedRewards;
  uint128 lastDripTime;
  IERC20 asset;
  IDripModel dripModel;
  IReceiptToken depositReceiptToken;
}

struct IdLookup {
  uint16 index;
  bool exists;
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";

// Used to track the rewards a user is entitled to for a given (stake pool, reward pool) pair.
struct UserRewardsData {
  // The total amount of rewards accrued by the user.
  uint256 accruedRewards;
  // The index snapshot the relevant claimable rewards data, when the user's accrued rewards were updated. The index
  // snapshot must update each time the user's accrued rewards are updated.
  uint256 indexSnapshot;
}

struct ClaimRewardsArgs {
  // The ID of the stake pool.
  uint16 stakePoolId;
  // The address that will receive the rewards.
  address receiver;
  // The address that owns the stkReceiptTokens.
  address owner;
}

// Used to track the total rewards all users are entitled to for a given (stake pool, reward pool) pair.
struct ClaimableRewardsData {
  // The cumulative amount of rewards that are claimable. This value is reset to 0 on each config update.
  uint256 cumulativeClaimableRewards;
  // The index snapshot the relevant claimable rewards data, when the cumulative claimed rewards were updated. The index
  // snapshot must update each time the cumulative claimed rewards are updated.
  uint256 indexSnapshot;
}

// Used as a return type for the `previewClaimableRewards` function.
struct PreviewClaimableRewards {
  // The ID of the stake pool.
  uint16 stakePoolId;
  // An array of preview claimable rewards data with one entry for each reward pool.
  PreviewClaimableRewardsData[] claimableRewardsData;
}

struct PreviewClaimableRewardsData {
  // The ID of the reward pool.
  uint16 rewardPoolId;
  // The amount of claimable rewards.
  uint256 amount;
  // The reward asset.
  IERC20 asset;
}

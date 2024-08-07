// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";
import {RewardsManagerCalculationsLib} from "./RewardsManagerCalculationsLib.sol";
import {StakePool, RewardPool} from "./structs/Pools.sol";
import {ClaimableRewardsData, UserRewardsData} from "./structs/Rewards.sol";

abstract contract RewardsManagerInspector is RewardsManagerCommon {
  uint256 internal constant POOL_AMOUNT_FLOOR = 1;

  /// @notice Returns the reward manager's stake pools.
  /// @return stakePools_ The stake pools.
  function getStakePools() external view returns (StakePool[] memory) {
    return stakePools;
  }

  /// @notice Returns the reward manager's reward pools.
  /// @return rewardPools_ The reward pools.
  function getRewardPools() external view returns (RewardPool[] memory) {
    return rewardPools;
  }

  /// @notice Returns the rewards for a user in a stake pool.
  /// @param stakePoolId_ The ID of the stake pool.
  /// @param user The user's address.
  /// @return userRewards_ The array of user rewards data.
  function getUserRewards(uint16 stakePoolId_, address user) external view returns (UserRewardsData[] memory) {
    return userRewards[stakePoolId_][user];
  }

  /// @notice Returns all claimable rewards for all stake pools and reward pools.
  /// @return claimableRewards_ The claimable rewards data.
  function getClaimableRewards() external view returns (ClaimableRewardsData[][] memory) {
    uint256 numStakePools_ = stakePools.length;
    uint256 numRewardPools_ = rewardPools.length;

    ClaimableRewardsData[][] memory claimableRewards_ = new ClaimableRewardsData[][](numStakePools_);
    for (uint16 i = 0; i < numStakePools_; i++) {
      claimableRewards_[i] = new ClaimableRewardsData[](numRewardPools_);
      mapping(uint16 => ClaimableRewardsData) storage stakePoolClaimableRewards_ = claimableRewards[i];
      for (uint16 j = 0; j < numRewardPools_; j++) {
        claimableRewards_[i][j] = stakePoolClaimableRewards_[j];
      }
    }

    return claimableRewards_;
  }

  /// @notice Returns all claimable rewards for a given stake pool.
  /// @param stakePoolId_ The ID of the stake pool.
  /// @return claimableRewards_ The claimable rewards data.
  function getClaimableRewards(uint16 stakePoolId_) external view returns (ClaimableRewardsData[] memory) {
    mapping(uint16 => ClaimableRewardsData) storage stakePoolClaimableRewards_ = claimableRewards[stakePoolId_];

    uint256 numRewardPools_ = rewardPools.length;
    ClaimableRewardsData[] memory claimableRewards_ = new ClaimableRewardsData[](numRewardPools_);
    for (uint16 i = 0; i < numRewardPools_; i++) {
      claimableRewards_[i] = stakePoolClaimableRewards_[i];
    }

    return claimableRewards_;
  }

  /// @notice The pool amount for the purposes of performing conversions. We set a floor once reward
  /// deposit receipt tokens have been initialized to avoid divide-by-zero errors that would occur when the supply
  /// of reward deposit receipt tokens > 0, but the `poolAmount` = 0, which can occur due to drip.
  function _poolAmountWithFloor(uint256 poolAmount_) internal pure override returns (uint256) {
    return poolAmount_ > POOL_AMOUNT_FLOOR ? poolAmount_ : POOL_AMOUNT_FLOOR;
  }
}

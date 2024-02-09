// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";
import {RewardsManagerCalculationsLib} from "./RewardsManagerCalculationsLib.sol";
import {StakePool, RewardPool} from "./structs/Pools.sol";
import {ClaimableRewardsData} from "./structs/Rewards.sol";

abstract contract RewardsManagerInspector is RewardsManagerCommon {
  uint256 internal constant POOL_AMOUNT_FLOOR = 1;

  /// @notice Converts a reward pool's reward asset amount to the corresponding reward deposit receipt token amount.
  function convertRewardAssetToReceiptTokenAmount(uint256 rewardPoolId_, uint256 rewardAssetAmount_)
    external
    view
    returns (uint256 depositReceiptTokenAmount_)
  {
    depositReceiptTokenAmount_ = RewardsManagerCalculationsLib.convertToReceiptTokenAmount(
      rewardAssetAmount_,
      rewardPools[rewardPoolId_].depositReceiptToken.totalSupply(),
      /// We set a floor to avoid divide-by-zero errors that would occur when the supply of deposit receipt tokens >
      /// 0, but the `poolAmount` == 0, which can occur due to drip.
      _poolAmountWithFloor(rewardPools[rewardPoolId_].undrippedRewards)
    );
  }

  /// @notice Converts a reward pool's reward deposit receipt token amount to the corresponding reward asset amount.
  function convertRewardReceiptTokenToAssetAmount(uint256 rewardPoolId_, uint256 depositReceiptTokenAmount_)
    external
    view
    returns (uint256 rewardAssetAmount_)
  {
    rewardAssetAmount_ = RewardsManagerCalculationsLib.convertToAssetAmount(
      depositReceiptTokenAmount_,
      rewardPools[rewardPoolId_].depositReceiptToken.totalSupply(),
      // We set a floor to avoid divide-by-zero errors that would occur when the supply of depositReceiptTokens >
      // 0, but the `poolAmount` == 0, which can occur due to drip.
      _poolAmountWithFloor(rewardPools[rewardPoolId_].undrippedRewards)
    );
  }

  /// @notice Converts a stake pool's stake asset amount to the corresponding stake receipt token amount.
  function convertStakeAssetToReceiptTokenAmount(uint256 stakePoolId_, uint256 stakeAssetAmount_)
    external
    view
    returns (uint256 stakeReceiptTokenAmount_)
  {
    StakePool memory stakePool_ = stakePools[stakePoolId_];
    stakeReceiptTokenAmount_ = RewardsManagerCalculationsLib.convertToReceiptTokenAmount(
      stakeAssetAmount_, stakePool_.stkReceiptToken.totalSupply(), stakePool_.amount
    );
  }

  /// @notice Converts a stake pool's stake receipt token amount to the corresponding stake asset amount.
  function convertStakeReceiptTokenToAssetAmount(uint256 stakePoolId_, uint256 stakeReceiptTokenAmount_)
    external
    view
    returns (uint256 stakeAssetAmount_)
  {
    StakePool memory stakePool_ = stakePools[stakePoolId_];
    stakeAssetAmount_ = RewardsManagerCalculationsLib.convertToAssetAmount(
      stakeReceiptTokenAmount_, stakePool_.stkReceiptToken.totalSupply(), stakePool_.amount
    );
  }

  /// @notice The pool amount for the purposes of performing conversions. We set a floor once reward
  /// deposit receipt tokens have been initialized to avoid divide-by-zero errors that would occur when the supply
  /// of reward deposit receipt tokens > 0, but the `poolAmount` = 0, which can occur due to drip.
  function _poolAmountWithFloor(uint256 poolAmount_) internal pure override returns (uint256) {
    return poolAmount_ > POOL_AMOUNT_FLOOR ? poolAmount_ : POOL_AMOUNT_FLOOR;
  }

  function getStakePools() external view returns (StakePool[] memory) {
    return stakePools;
  }

  function getRewardPools() external view returns (RewardPool[] memory) {
    return rewardPools;
  }

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

  function getClaimableRewards(uint16 stakePoolId_) external view returns (ClaimableRewardsData[] memory) {
    mapping(uint16 => ClaimableRewardsData) storage stakePoolClaimableRewards_ = claimableRewards[stakePoolId_];

    uint256 numRewardPools_ = rewardPools.length;
    ClaimableRewardsData[] memory claimableRewards_ = new ClaimableRewardsData[](numRewardPools_);
    for (uint16 i = 0; i < numRewardPools_; i++) {
      claimableRewards_[i] = stakePoolClaimableRewards_[i];
    }

    return claimableRewards_;
  }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {SafeERC20} from "cozy-safety-module-libs/lib/SafeERC20.sol";
import {MathConstants} from "cozy-safety-module-libs/lib/MathConstants.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {RewardsManagerState} from "./RewardsManagerStates.sol";
import {RewardPool} from "./structs/Pools.sol";
import {DepositorRewardsData} from "./structs/Rewards.sol";
import {RewardsManagerCommon} from "./RewardsManagerCommon.sol";
import {RewardMathLib} from "./RewardMathLib.sol";

abstract contract Withdrawer is RewardsManagerCommon {
  using SafeERC20 for IERC20;
  using FixedPointMathLib for uint256;

  /// @notice Emitted when reward assets are withdrawn by a depositor.
  /// @param depositor_ The address that withdrew the reward assets.
  /// @param rewardPoolId_ The ID of the reward pool.
  /// @param amount_ The amount of reward assets withdrawn.
  /// @param receiver_ The address that received the withdrawn assets.
  event RewardAssetsWithdrawn(
    address indexed depositor_, uint16 indexed rewardPoolId_, uint256 amount_, address receiver_
  );

  /// @notice Thrown when attempting to withdraw more than available balance.
  error InsufficientWithdrawableBalance();

  /// @notice Withdraw reward assets that have not been dripped yet.
  /// @param rewardPoolId_ The ID of the reward pool to withdraw from.
  /// @param amount_ The amount of reward assets to withdraw.
  /// @param receiver_ The address that will receive the withdrawn assets.
  function withdrawRewardAssets(uint16 rewardPoolId_, uint256 amount_, address receiver_) external {
    if (rewardsManagerState == RewardsManagerState.PAUSED) revert InvalidState();
    if (amount_ == 0) revert AmountIsZero();

    // Update and get current withdrawable balance
    uint256 withdrawable_ = _updateAndGetWithdrawableBalance(rewardPoolId_, msg.sender);
    if (amount_ > withdrawable_) revert InsufficientWithdrawableBalance();

    // Update depositor balance
    depositorRewards[rewardPoolId_][msg.sender].withdrawableRewards = withdrawable_ - amount_;

    // Update pool accounting
    RewardPool storage rewardPool_ = rewardPools[rewardPoolId_];
    rewardPool_.undrippedRewards -= amount_;
    assetPools[rewardPool_.asset].amount -= amount_;

    // Transfer assets
    rewardPool_.asset.safeTransfer(receiver_, amount_);

    emit RewardAssetsWithdrawn(msg.sender, rewardPoolId_, amount_, receiver_);
  }

  /// @notice Get the current withdrawable balance for a depositor.
  /// @param rewardPoolId_ The ID of the reward pool.
  /// @param depositor_ The address of the depositor.
  /// @return The current withdrawable balance.
  function getWithdrawableBalance(uint16 rewardPoolId_, address depositor_) external view returns (uint256) {
    RewardPool storage rewardPool_ = rewardPools[rewardPoolId_];
    DepositorRewardsData storage info_ = depositorRewards[rewardPoolId_][depositor_];

    // Check epoch first
    if (info_.epoch < rewardPool_.epoch || info_.withdrawableRewards == 0) return 0;

    if (info_.logIndexSnapshot == rewardPool_.logIndex) return info_.withdrawableRewards; // No change since last update

    // Calculate current balance
    uint256 deltaLogIndex_ = rewardPool_.logIndex - info_.logIndexSnapshot;
    return info_.withdrawableRewards.mulWadDown(RewardMathLib.expNeg(deltaLogIndex_));
  }

  /// @dev Updates and returns the current withdrawable balance for a depositor.
  function _updateAndGetWithdrawableBalance(uint16 rewardPoolId_, address depositor_) internal returns (uint256) {
    RewardPool storage rewardPool_ = rewardPools[rewardPoolId_];
    DepositorRewardsData storage info_ = depositorRewards[rewardPoolId_][depositor_];

    // Check epoch first
    if (info_.epoch < rewardPool_.epoch || info_.withdrawableRewards == 0) {
      // Reset to current epoch with 0 balance
      info_.withdrawableRewards = 0;
      info_.logIndexSnapshot = rewardPool_.logIndex;
      info_.epoch = rewardPool_.epoch;
      return 0;
    }

    if (info_.logIndexSnapshot != rewardPool_.logIndex) {
      // Update balance to current time
      uint256 deltaLogIndex_ = rewardPool_.logIndex - info_.logIndexSnapshot;
      info_.withdrawableRewards = info_.withdrawableRewards.mulWadDown(RewardMathLib.expNeg(deltaLogIndex_));
      info_.logIndexSnapshot = rewardPool_.logIndex;
    }

    return info_.withdrawableRewards;
  }
}

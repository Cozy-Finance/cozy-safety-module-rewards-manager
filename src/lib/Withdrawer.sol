// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-libs/interfaces/IERC20.sol";
import {SafeERC20} from "cozy-safety-module-libs/lib/SafeERC20.sol";
import {MathConstants} from "cozy-safety-module-libs/lib/MathConstants.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {RewardsManagerState} from "./RewardsManagerStates.sol";
import {RewardPool} from "./structs/Pools.sol";
import {DepositorInfo} from "./structs/Rewards.sol";
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
    uint256 withdrawable = _updateAndGetWithdrawableBalance(rewardPoolId_, msg.sender);
    if (amount_ > withdrawable) revert InsufficientWithdrawableBalance();

    // Update depositor balance
    depositorInfos[rewardPoolId_][msg.sender].balance = withdrawable - amount_;

    // Update pool accounting
    RewardPool storage rewardPool = rewardPools[rewardPoolId_];
    rewardPool.undrippedRewards -= amount_;
    assetPools[rewardPool.asset].amount -= amount_;

    // Transfer assets
    rewardPool.asset.safeTransfer(receiver_, amount_);

    emit RewardAssetsWithdrawn(msg.sender, rewardPoolId_, amount_, receiver_);
  }

  /// @notice Get the current withdrawable balance for a depositor.
  /// @param rewardPoolId_ The ID of the reward pool.
  /// @param depositor_ The address of the depositor.
  /// @return The current withdrawable balance.
  function getWithdrawableBalance(uint16 rewardPoolId_, address depositor_) external view returns (uint256) {
    DepositorInfo storage info = depositorInfos[rewardPoolId_][depositor_];
    uint256 currentLogIndex = rewardPoolLogIndex[rewardPoolId_];

    if (currentLogIndex == type(uint256).max || info.balance == 0) return 0; // Full drip occurred or no balance

    if (info.logIndexSnapshot == currentLogIndex) return info.balance; // No change since last update

    // Calculate current balance
    uint256 deltaLogIndex = currentLogIndex - info.logIndexSnapshot;
    return info.balance.mulWadDown(RewardMathLib.expNeg(deltaLogIndex));
  }

  /// @dev Updates and returns the current withdrawable balance for a depositor.
  function _updateAndGetWithdrawableBalance(uint16 rewardPoolId_, address depositor_) internal returns (uint256) {
    DepositorInfo storage info = depositorInfos[rewardPoolId_][depositor_];
    uint256 currentLogIndex = rewardPoolLogIndex[rewardPoolId_];

    if (currentLogIndex == type(uint256).max || info.balance == 0) return 0; // Full drip occurred or no balance

    if (info.logIndexSnapshot != currentLogIndex) {
      // Update balance to current time
      uint256 deltaLogIndex = currentLogIndex - info.logIndexSnapshot;
      info.balance = info.balance.mulWadDown(RewardMathLib.expNeg(deltaLogIndex));
      info.logIndexSnapshot = currentLogIndex;
    }

    return info.balance;
  }
}
